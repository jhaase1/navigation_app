import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import 'authorized_drive_client.dart';

enum DriveAccountState {
  /// The saved session has not been looked at yet. Nothing should ask the
  /// operator to sign in while this is the state: they may already be.
  checking,
  signedOut,
  signedIn,
  wrongAccount,
}

@immutable
class DriveAccountStatus {
  final DriveAccountState state;

  /// The Google account involved: the one signed in, or the wrong one that
  /// was refused. Null otherwise.
  final String? email;

  const DriveAccountStatus(this.state, [this.email]);
}

/// The project's shared Google account, signed in on this machine.
///
/// Only ever prompts from [signIn], which the operator triggers from
/// Settings. Everything the backup engine calls — [headers], [restore] —
/// is silent: a sign-in sheet popping up mid-service would be the modal
/// interruption the status surface was designed to avoid.
class GoogleDriveAccount implements DriveCredentials {
  /// Lets the app create files in, and see only, folders it made itself.
  static const driveFileScope = 'https://www.googleapis.com/auth/drive.file';
  static const _scopes = [driveFileScope];

  /// The only account backups may go to. Anything else is refused, so a
  /// volunteer signing in with a personal account does not scatter the
  /// church's configuration into their own Drive.
  final String expectedAccount;
  final GoogleSignIn _signIn;

  final ValueNotifier<DriveAccountStatus> _status =
      ValueNotifier(const DriveAccountStatus(DriveAccountState.checking));
  GoogleSignInAccount? _account;
  Future<void>? _initialized;
  Future<void>? _restored;

  /// Why the last silent restore got no answer, until one does. See
  /// [headers]: no answer is not the same as signed out.
  (Object, StackTrace)? _unanswered;

  /// How long a silent restore may take before it counts as no answer.
  final Duration restoreTimeout;

  GoogleDriveAccount({
    required this.expectedAccount,
    GoogleSignIn? signIn,
    this.restoreTimeout = const Duration(seconds: 15),
  }) : _signIn = signIn ?? GoogleSignIn.instance;

  ValueListenable<DriveAccountStatus> get status => _status;

  Future<void> _ready() =>
      _initialized ??= _forgetOnError(_signIn.initialize(), () {
        _initialized = null;
      });

  /// Shares one attempt between callers, but not a failed one: remembering
  /// a failure left backups signed out — and Sign in broken — until the app
  /// restarted.
  static Future<void> _forgetOnError(
          Future<void> attempt, void Function() forget) =>
      attempt.catchError((Object e, StackTrace s) {
        forget();
        Error.throwWithStackTrace(e, s);
      });

  bool _isExpected(String email) =>
      email.trim().toLowerCase() == expectedAccount.trim().toLowerCase();

  /// Picks up a previous session without any UI.
  Future<void> restore() =>
      _restored ??= _forgetOnError(_restore(), () => _restored = null);

  Future<void> _restore() async {
    var failed = true;
    try {
      final adopted = await () async {
        await _ready();
        final account = await _signIn.attemptLightweightAuthentication();
        return account != null && await _adopt(account);
      }()
          .timeout(restoreTimeout);
      failed = false;
      _unanswered = null;
      if (adopted) return;
    } on GoogleSignInException catch (e, s) {
      // A refusal (a misconfigured client, say) is an answer: signed out,
      // and the real message resurfaces the moment the operator taps Sign
      // in. The SDK's catch-all is not one.
      _unanswered =
          e.code == GoogleSignInExceptionCode.unknownError ? (e, s) : null;
    } on PlatformException catch (e, s) {
      // How a token refresh that could not reach Google comes back.
      _unanswered = (e, s);
    } on TimeoutException catch (e, s) {
      _unanswered = (e, s);
    }
    // Still checking while there is no answer, so nothing asks for a
    // sign-in that cannot work offline.
    if (_unanswered == null &&
        _status.value.state == DriveAccountState.checking) {
      _status.value = const DriveAccountStatus(DriveAccountState.signedOut);
    }
    // Refused (offline at launch) or never answered is not "nobody signed
    // in": let the next restore — the next backup's headers() — ask again
    // instead of caching signed out until someone signs in by hand.
    if (failed) _restored = null;
  }

  /// Interactive sign-in, then the Drive grant. Operator-triggered only.
  Future<void> signIn() async {
    await _ready();
    final GoogleSignInAccount account;
    try {
      account = await _signIn.authenticate(scopeHint: _scopes);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        if (_status.value.state == DriveAccountState.checking) {
          _status.value = const DriveAccountStatus(DriveAccountState.signedOut);
        }
        return;
      }
      rethrow;
    }
    if (!await _adopt(account)) return;
    await account.authorizationClient.authorizeScopes(_scopes);
  }

  Future<void> signOut() async {
    await _ready();
    await _signIn.signOut();
    _account = null;
    _unanswered = null;
    _status.value = const DriveAccountStatus(DriveAccountState.signedOut);
  }

  /// Takes [account] if it is the expected one. A wrong account is signed
  /// straight back out before it is ever asked for Drive access.
  Future<bool> _adopt(GoogleSignInAccount account) async {
    _unanswered = null;
    if (!_isExpected(account.email)) {
      await _signIn.signOut();
      _account = null;
      _status.value =
          DriveAccountStatus(DriveAccountState.wrongAccount, account.email);
      return false;
    }
    _account = account;
    _status.value =
        DriveAccountStatus(DriveAccountState.signedIn, account.email);
    return true;
  }

  @override
  Future<Map<String, String>?> headers() async {
    await restore();
    final account = _account;
    if (account == null) {
      // No answer is handed on as the failure it was, which the Drive client
      // reports as offline and the scheduler retries. Null would read as
      // "sign in again", a fix that cannot work offline.
      final unanswered = _unanswered;
      if (unanswered != null) {
        Error.throwWithStackTrace(unanswered.$1, unanswered.$2);
      }
      return null;
    }
    return account.authorizationClient
        .authorizationHeaders(_scopes, promptIfNecessary: false);
  }

  @override
  Future<void> invalidate(Map<String, String> rejected) async {
    final bearer = rejected['Authorization'];
    if (bearer == null || !bearer.startsWith('Bearer ')) return;
    await _signIn.authorizationClient
        .clearAuthorizationToken(accessToken: bearer.substring(7));
  }
}
