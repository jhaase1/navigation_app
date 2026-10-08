import 'dart:async';

import 'package:http/http.dart' as http;

import '../app_fault.dart';

/// Where Drive requests get their credentials, without ever prompting.
abstract class DriveCredentials {
  /// Authorization headers for Drive, fetched fresh, or null when the
  /// operator has to sign in first.
  Future<Map<String, String>?> headers();

  /// Drops a token Drive rejected, so the next [headers] call fetches a new
  /// one instead of handing the dead one back.
  Future<void> invalidate(Map<String, String> rejected);
}

/// An HTTP client that authorizes every request just before it is sent.
///
/// The obvious alternative — `authClient()` from
/// `extension_google_sign_in_as_googleapis_auth` — wraps ONE access token,
/// stamps it with a made-up one-year expiry and has no refresh token. Google
/// access tokens live about an hour, so a client built at launch starts
/// failing with 401 an hour into a service. Asking for headers per request
/// lets the sign-in SDK hand back its cached token or refresh it silently.
///
/// Every request also has a deadline. Without one a half-open connection
/// would hold the backup scheduler's single-flight queue forever.
class AuthorizedDriveClient extends http.BaseClient {
  final DriveCredentials _credentials;
  final http.Client _inner;
  final Duration timeout;

  /// For uploads and media downloads, which move a whole configuration.
  final Duration transferTimeout;

  AuthorizedDriveClient(
    this._credentials, {
    http.Client? inner,
    this.timeout = const Duration(seconds: 30),
    this.transferTimeout = const Duration(seconds: 120),
  }) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Buffered so the body can be sent a second time after a 401.
    final body = await request.finalize().toBytes();
    final deadline = _isTransfer(request.url) ? transferTimeout : timeout;

    var response = await _sendOnce(request, body, deadline);
    if (response.$1.statusCode == 401) {
      await _credentials.invalidate(response.$2);
      response = await _sendOnce(request, body, deadline);
    }
    return response.$1;
  }

  Future<(http.StreamedResponse, Map<String, String>)> _sendOnce(
    http.BaseRequest original,
    List<int> body,
    Duration deadline,
  ) async {
    // Fetching a token can refresh it over the network, so it gets the
    // request's deadline too.
    final auth = await _credentials.headers().timeout(deadline);
    if (auth == null) {
      throw AppFault.backup(
        BackupFailureKind.authExpired,
        'Sign in to Google Drive in Settings to resume backups.',
      );
    }
    final request = http.Request(original.method, original.url)
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection
      // The rebuilt request computes its own length from [body].
      ..headers.addAll(Map.of(original.headers)
        ..removeWhere((k, _) => k.toLowerCase() == 'content-length'))
      ..headers.addAll(auth)
      ..bodyBytes = body;

    final streamed = await _inner.send(request).timeout(deadline);
    // Read the whole body inside the deadline too: headers can arrive and
    // the body then stall.
    final bytes = await streamed.stream.toBytes().timeout(deadline);
    return (
      http.StreamedResponse(
        Stream.value(bytes),
        streamed.statusCode,
        contentLength: bytes.length,
        request: streamed.request,
        headers: streamed.headers,
        isRedirect: streamed.isRedirect,
        persistentConnection: streamed.persistentConnection,
        reasonPhrase: streamed.reasonPhrase,
      ),
      auth,
    );
  }

  static bool _isTransfer(Uri url) =>
      url.path.startsWith('/upload/') || url.queryParameters['alt'] == 'media';

  @override
  void close() => _inner.close();
}
