import 'dart:async';

import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The native sign-in SDK, faked at the plugin's own platform seam so the
/// real `GoogleSignIn` code runs on top of it.
class FakeSignInPlatform extends GoogleSignInPlatform
    with MockPlatformInterfaceMixin {
  /// The account a silent restore finds, if any.
  String? rememberedEmail;

  /// The account the operator picks in the interactive sheet.
  String? pickedEmail;

  /// While set, a silent restore does not answer until it completes.
  Completer<void>? lightweightHang;

  /// Thrown by a silent restore, the way a misconfigured client fails.
  Object? lightweightError;

  /// Whether the operator cancels the interactive sheet.
  bool cancels = false;

  /// Whether drive.file has been granted (without prompting).
  bool granted = false;

  /// Thrown by the Drive consent screen, the way "Don't Allow" fails.
  Object? grantError;

  int tokenSerial = 0;
  final cleared = <String>[];
  final promptedFor = <List<String>>[];
  bool signedOut = false;

  AuthenticationResults _results(String email) => AuthenticationResults(
        user: GoogleSignInUserData(email: email, id: 'id-$email'),
        authenticationTokens: const AuthenticationTokenData(idToken: 'id'),
      );

  /// Thrown by the next `init` only, the way a first launch can fail on a
  /// flaky keychain and then work.
  Object? initErrorOnce;

  @override
  Future<void> init(InitParameters params) async {
    final error = initErrorOnce;
    initErrorOnce = null;
    if (error != null) throw error;
  }

  @override
  Future<AuthenticationResults?> attemptLightweightAuthentication(
      AttemptLightweightAuthenticationParameters params) async {
    final hang = lightweightHang;
    if (hang != null) await hang.future;
    if (lightweightError != null) throw lightweightError!;
    final email = rememberedEmail;
    return email == null ? null : _results(email);
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(
      AuthenticateParameters params) async {
    if (cancels || pickedEmail == null) {
      throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled);
    }
    rememberedEmail = pickedEmail;
    signedOut = false;
    return _results(pickedEmail!);
  }

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
      ClientAuthorizationTokensForScopesParameters params) async {
    if (params.request.promptIfUnauthorized) {
      promptedFor.add(params.request.scopes);
      if (grantError != null) throw grantError!;
      granted = true;
    }
    if (!granted || signedOut) return null;
    return ClientAuthorizationTokenData(accessToken: 'token-${++tokenSerial}');
  }

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
          ServerAuthorizationTokensForScopesParameters params) async =>
      null;

  @override
  Future<void> clearAuthorizationToken(
          ClearAuthorizationTokenParams params) async =>
      cleared.add(params.accessToken);

  @override
  Future<void> signOut(SignOutParams params) async {
    signedOut = true;
    rememberedEmail = null;
  }

  @override
  Future<void> disconnect(DisconnectParams params) async => signOut(
      const SignOutParams());
}

