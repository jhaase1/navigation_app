import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/drive/authorized_drive_client.dart';

/// Hands out a fresh bearer token each time, the way the sign-in SDK does
/// once an old one has been cleared.
class _Credentials implements DriveCredentials {
  int issued = 0;
  bool signedIn = true;
  final invalidated = <String>[];

  @override
  Future<Map<String, String>?> headers() async {
    if (!signedIn) return null;
    issued++;
    return {'Authorization': 'Bearer token-$issued'};
  }

  @override
  Future<void> invalidate(Map<String, String> rejected) async =>
      invalidated.add(rejected['Authorization']!);
}

void main() {
  late _Credentials credentials;
  late List<http.Request> seen;

  setUp(() {
    credentials = _Credentials();
    seen = [];
  });

  AuthorizedDriveClient clientWith(
    Future<http.Response> Function(http.Request) handler, {
    Duration timeout = const Duration(seconds: 30),
  }) =>
      AuthorizedDriveClient(
        credentials,
        inner: MockClient((r) {
          seen.add(r);
          return handler(r);
        }),
        timeout: timeout,
        transferTimeout: timeout,
      );

  test('every request carries a freshly fetched token', () async {
    final client = clientWith((_) async => http.Response('ok', 200));

    await client.get(Uri.parse('https://www.googleapis.com/drive/v3/files'));
    await client.get(Uri.parse('https://www.googleapis.com/drive/v3/files'));

    expect(seen.map((r) => r.headers['Authorization']),
        ['Bearer token-1', 'Bearer token-2']);
  });

  test('signed out: fails as authExpired without touching the network',
      () async {
    credentials.signedIn = false;
    final client = clientWith((_) async => http.Response('ok', 200));

    await expectLater(
      client.get(Uri.parse('https://www.googleapis.com/drive/v3/files')),
      throwsA(isA<AppFault>()
          .having((f) => f.kind, 'kind', BackupFailureKind.authExpired.name)),
    );
    expect(seen, isEmpty);
  });

  test('a rejected token is cleared and the request retried once', () async {
    final client = clientWith((r) async =>
        r.headers['Authorization'] == 'Bearer token-1'
            ? http.Response('expired', 401)
            : http.Response('ok', 200));

    final response =
        await client.get(Uri.parse('https://www.googleapis.com/drive/v3/files'));

    expect(response.statusCode, 200);
    expect(credentials.invalidated, ['Bearer token-1']);
    expect(seen, hasLength(2));
  });

  test('a second rejection is passed through, not retried forever', () async {
    final client = clientWith((_) async => http.Response('expired', 401));

    final response =
        await client.get(Uri.parse('https://www.googleapis.com/drive/v3/files'));

    expect(response.statusCode, 401);
    expect(seen, hasLength(2));
  });

  test('the retried request sends the same body', () async {
    final client = clientWith((r) async =>
        r.headers['Authorization'] == 'Bearer token-1'
            ? http.Response('expired', 401)
            : http.Response('ok', 200));

    await client.post(
      Uri.parse('https://www.googleapis.com/upload/drive/v3/files'),
      headers: {'content-type': 'multipart/related; boundary="b"'},
      body: '--b\r\nbody bytes\r\n--b--',
    );

    expect(seen.map((r) => r.body).toSet(), {'--b\r\nbody bytes\r\n--b--'});
    expect(seen.last.headers['content-type'],
        'multipart/related; boundary="b"');
  });

  group('a sign-in SDK failure while fetching a token is an AppFault', () {
    // Not a raw exception: one of those reaches the pill with no operation,
    // under a key nothing clears, and with no Sign in button.
    final cases = <(String, Object, BackupFailureKind)>[
      (
        // Refresh token revoked or expired: only a sign-in fixes it.
        'the token endpoint refusing the refresh',
        PlatformException(
            code: 'org.openid.appauth.oauth_token: -10',
            message: 'invalid_grant'),
        BackupFailureKind.authExpired,
      ),
      (
        'the SDK no longer having the user',
        const GoogleSignInException(
            code: GoogleSignInExceptionCode.userMismatch,
            description: 'The user is no longer signed in.'),
        BackupFailureKind.authExpired,
      ),
      (
        'no network for the refresh',
        PlatformException(
            code: 'org.openid.appauth.general: -5',
            message: 'The Internet connection appears to be offline.'),
        BackupFailureKind.offline,
      ),
      (
        'an unexplained SDK error',
        const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
            description: 'The operation couldn’t be completed.'),
        BackupFailureKind.offline,
      ),
      (
        'the keychain failing',
        const GoogleSignInException(
            code: GoogleSignInExceptionCode.providerConfigurationError),
        BackupFailureKind.offline,
      ),
    ];
    for (final (name, error, kind) in cases) {
      test('$name is ${kind.name}', () async {
        final client = AuthorizedDriveClient(
          _ThrowingCredentials(error),
          inner: MockClient((r) async {
            seen.add(r);
            return http.Response('ok', 200);
          }),
        );

        await expectLater(
          client.get(Uri.parse('https://www.googleapis.com/drive/v3/files')),
          throwsA(isA<AppFault>()
              .having((f) => f.kind, 'kind', kind.name)
              .having((f) => f.cause, 'cause', error)),
        );
        expect(seen, isEmpty);
      });
    }
  });

  test('a request that never answers times out instead of hanging', () async {
    final client = clientWith((_) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 50));

    await expectLater(
      client.get(Uri.parse('https://www.googleapis.com/drive/v3/files')),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('a sign-in SDK that never answers is held to the same deadline',
      () async {
    // Asking for a token can refresh it over the network. Left unbounded, a
    // hung refresh would hold the backup queue forever.
    final client = AuthorizedDriveClient(
      _HungCredentials(),
      inner: MockClient((_) async => http.Response('ok', 200)),
      timeout: const Duration(milliseconds: 50),
      transferTimeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      client.get(Uri.parse('https://www.googleapis.com/drive/v3/files')),
      throwsA(isA<TimeoutException>()),
    ).timeout(const Duration(seconds: 5));
  });
}

class _HungCredentials implements DriveCredentials {
  @override
  Future<Map<String, String>?> headers() => Completer<Map<String, String>?>().future;

  @override
  Future<void> invalidate(Map<String, String> rejected) async {}
}

class _ThrowingCredentials implements DriveCredentials {
  final Object error;
  _ThrowingCredentials(this.error);

  @override
  Future<Map<String, String>?> headers() async => throw error;

  @override
  Future<void> invalidate(Map<String, String> rejected) async {}
}
