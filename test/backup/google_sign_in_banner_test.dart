import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/widgets/backup/google_sign_in_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/drive_controller.dart';
import 'support/fake_sign_in_platform.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<BackupController> show(WidgetTester tester,
      FakeSignInPlatform platform) async {
    final controller = driveController(platform);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: GoogleSignInBanner(controller: controller)),
    ));
    await controller.driveAccount!.restore();
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('launching signed out asks for a sign-in, and signing in clears it',
      (tester) async {
    final controller =
        await show(tester, FakeSignInPlatform()..pickedEmail = driveTestAccount);
    expect(find.textContaining('Backups are off'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Backups are off'), findsNothing);
    await controller.dispose();
  });

  testWidgets('a sign-in that fails outside the SDK still says why',
      (tester) async {
    final controller = await show(
        tester,
        FakeSignInPlatform()
          ..authenticateError = PlatformException(
              code: 'google_sign_in',
              message: 'No active configuration. Make sure GIDClientID is set '
                  'in Info.plist.'));

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No active configuration'), findsOneWidget);
    await controller.dispose();
  });

  testWidgets('"Not now" puts it away', (tester) async {
    final controller = await show(tester, FakeSignInPlatform());

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Backups are off'), findsNothing);
    await controller.dispose();
  });

  testWidgets('says nothing when the saved session comes back on its own',
      (tester) async {
    final controller = await show(
        tester,
        FakeSignInPlatform()
          ..rememberedEmail = driveTestAccount
          ..granted = true);

    expect(find.byType(MaterialBanner), findsNothing);
    await controller.dispose();
  });

  testWidgets('names the right account when the wrong one is signed in',
      (tester) async {
    final controller = await show(
        tester, FakeSignInPlatform()..rememberedEmail = 'volunteer@gmail.com');

    expect(find.textContaining('volunteer@gmail.com'), findsOneWidget);
    expect(find.textContaining(driveTestAccount), findsOneWidget);
    await controller.dispose();
  });

  testWidgets('a build without Drive never shows it', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: GoogleSignInBanner(controller: BackupController.disabled())),
    ));

    expect(find.byType(MaterialBanner), findsNothing);
  });
}
