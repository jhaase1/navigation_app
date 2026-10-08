import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:navigation_app/services/backup/drive/google_drive_account.dart';

import 'support/fake_sign_in_platform.dart';

const _expected = 'Ops.Account@example.com';

void main() {
  late FakeSignInPlatform platform;

  setUp(() {
    platform = FakeSignInPlatform();
    GoogleSignInPlatform.instance = platform;
  });

  GoogleDriveAccount account() =>
      GoogleDriveAccount(expectedAccount: _expected, signIn: GoogleSignIn.instance);

  group('restoring a previous session', () {
    test('until the saved session is checked, it says so', () {
      expect(account().status.value.state, DriveAccountState.checking);
    });

    test('a restore the SDK refuses leaves it signed out, not checking',
        () async {
      platform.lightweightError = const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError);
      final a = account();

      await a.restore();

      expect(a.status.value.state, DriveAccountState.signedOut);
      expect(await a.headers(), isNull);
    });

    test('the expected account comes back signed in with a token', () async {
      platform
        ..rememberedEmail = _expected
        ..granted = true;
      final a = account();

      await a.restore();

      expect(a.status.value.state, DriveAccountState.signedIn);
      expect(a.status.value.email, _expected);
      expect(await a.headers(), {'Authorization': 'Bearer token-1',
          'X-Goog-AuthUser': '0'});
    });

    test('nobody remembered: signed out, no token, no prompt', () async {
      final a = account();

      await a.restore();

      expect(a.status.value.state, DriveAccountState.signedOut);
      expect(await a.headers(), isNull);
      expect(platform.promptedFor, isEmpty);
    });

    test('headers restore lazily when nobody called restore first', () async {
      platform
        ..rememberedEmail = _expected
        ..granted = true;

      expect(await account().headers(), isNotNull);
    });

    test('a remembered account that is the wrong one is not used', () async {
      platform
        ..rememberedEmail = 'volunteer@gmail.com'
        ..granted = true;
      final a = account();

      await a.restore();

      expect(a.status.value.state, DriveAccountState.wrongAccount);
      expect(a.status.value.email, 'volunteer@gmail.com');
      expect(await a.headers(), isNull);
    });

    test('signed in but drive.file never granted: no token, no prompt',
        () async {
      platform.rememberedEmail = _expected;
      final a = account();

      await a.restore();

      expect(await a.headers(), isNull);
      expect(platform.promptedFor, isEmpty);
    });
  });

  group('interactive sign-in', () {
    test('the expected account, in any case, signs in and grants drive.file',
        () async {
      platform.pickedEmail = _expected.toLowerCase();
      final a = account();

      await a.signIn();

      expect(a.status.value.state, DriveAccountState.signedIn);
      expect(platform.promptedFor, [
        [GoogleDriveAccount.driveFileScope]
      ]);
      expect(await a.headers(), isNotNull);
    });

    test('the wrong account is signed straight back out', () async {
      platform.pickedEmail = 'volunteer@gmail.com';
      final a = account();

      await a.signIn();

      expect(a.status.value.state, DriveAccountState.wrongAccount);
      expect(a.status.value.email, 'volunteer@gmail.com');
      expect(platform.signedOut, isTrue);
      expect(platform.promptedFor, isEmpty,
          reason: 'never ask a wrong account for Drive access');
      expect(await a.headers(), isNull);
    });

    test('cancelling the sheet leaves it signed out without an error',
        () async {
      platform.cancels = true;
      final a = account();

      await a.signIn();

      expect(a.status.value.state, DriveAccountState.signedOut);
    });
  });

  test('a rejected token is cleared so the next one is fresh', () async {
    platform
      ..rememberedEmail = _expected
      ..granted = true;
    final a = account();
    final first = (await a.headers())!;

    await a.invalidate(first);

    expect(platform.cleared, ['token-1']);
    expect((await a.headers())!['Authorization'], 'Bearer token-2');
  });

  test('signing out drops the account and its token', () async {
    platform
      ..rememberedEmail = _expected
      ..granted = true;
    final a = account();
    await a.restore();

    await a.signOut();

    expect(a.status.value.state, DriveAccountState.signedOut);
    expect(await a.headers(), isNull);
  });

  group('a sign-in SDK that fails once is asked again', () {
    // Remembering the failed attempt meant one bad launch-time init left
    // backups signed out — and Sign in broken — until the app restarted.
    test('restore', () async {
      platform
        ..rememberedEmail = _expected
        ..granted = true
        ..initErrorOnce = StateError('keychain busy');
      final a = account();

      await expectLater(a.restore(), throwsA(anything));
      await a.restore();

      expect(a.status.value.state, DriveAccountState.signedIn);
    });

    test('headers', () async {
      platform
        ..rememberedEmail = _expected
        ..granted = true
        ..initErrorOnce = StateError('keychain busy');
      final a = account();

      await expectLater(a.headers(), throwsA(anything));
      expect(await a.headers(), isNotNull);
    });

    test('Sign in', () async {
      platform
        ..pickedEmail = _expected
        ..initErrorOnce = StateError('keychain busy');
      final a = account();

      await expectLater(a.signIn(), throwsA(anything));
      await a.signIn();

      expect(a.status.value.state, DriveAccountState.signedIn);
    });
  });

  group('a silent restore that did not get an answer is tried again', () {
    test('after the SDK refused it (offline at launch)', () async {
      platform.lightweightError = const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError);
      final a = account();
      await a.restore();
      expect(a.status.value.state, DriveAccountState.signedOut);

      platform
        ..lightweightError = null
        ..rememberedEmail = _expected
        ..granted = true;

      expect(await a.headers(), isNotNull,
          reason: 'one bad launch must not leave backups signed out');
      expect(a.status.value.state, DriveAccountState.signedIn);
    });

    test('after it never answered', () async {
      platform
        ..rememberedEmail = _expected
        ..granted = true
        ..lightweightHang = Completer<void>();
      final a = GoogleDriveAccount(
          expectedAccount: _expected,
          signIn: GoogleSignIn.instance,
          restoreTimeout: const Duration(milliseconds: 50));

      await a.restore().timeout(const Duration(seconds: 2));
      expect(a.status.value.state, DriveAccountState.signedOut);

      platform.lightweightHang = null;
      expect(await a.headers().timeout(const Duration(seconds: 2)), isNotNull);
    });
  });
}
