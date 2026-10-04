import 'package:flutter/foundation.dart';
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

  GoogleDriveAccount({required this.expectedAccount, GoogleSignIn? signIn})
      : _signIn = signIn ?? GoogleSignIn.instance;

  ValueListenable<DriveAccountStatus> get status => _status;

  Future<void> _ready() => _initialized ??= _signIn.initialize();

  bool _isExpected(String email) =>
      email.trim().toLowerCase() == expectedAccount.trim().toLowerCase();

  /// Picks up a previous session without any UI.
  Future<void> restore() => _restored ??= _restore();

  Future<void> _restore() async {
    try {
      await _ready();
      final account = await _signIn.attemptLightweightAuthentication();
      if (account != null && await _adopt(account)) return;
    } on GoogleSignInException {
      // Signed out is the honest answer. A misconfigured client resurfaces
      // with its real message the moment the operator taps Sign in.
    }
    if (_status.value.state == DriveAccountState.checking) {
      _status.value = const DriveAccountStatus(DriveAccountState.signedOut);
    }
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
    _status.value = const DriveAccountStatus(DriveAccountState.signedOut);
  }

  /// Takes [account] if it is the expected one. A wrong account is signed
  /// straight back out before it is ever asked for Drive access.
  Future<bool> _adopt(GoogleSignInAccount account) async {
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
    if (account == null) return null;
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
