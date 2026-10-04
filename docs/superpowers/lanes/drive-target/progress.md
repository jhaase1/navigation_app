# Lane: Drive target and auth — progress

Date: 2026-10-03
Branch: `lane/drive-target` (worktree `.worktrees/drive-target`), off `main` at
`5b4c707`. Not pushed.
Plan: `plan.md` in this folder.

## Done

| Plan task | Commit | Proof |
|---|---|---|
| 1 Dependencies | `daf629e` | analyze clean |
| 2 `FakeDrive` | `1281b9a` | used by every Drive test below |
| 3 Contract suite on both targets | `1281b9a` | 12/12 against `MockBackupTarget` (passed before any Drive code existed), 12/12 against `DriveBackupTarget` |
| 4–5 `DriveBackupTarget` + error mapping | `1281b9a` | `drive_backup_target_test.dart` 32/32 |
| 6 `AuthorizedDriveClient` | `a46f054` | 6/6 |
| 7 `GoogleDriveAccount` | `a46f054` | 10/10 |
| 8 Retention + fault context | `3acc1b0` | `backup_retention_test.dart` 9/9; the three context-stamping tests confirmed failing with the fix reverted |
| 9 Target selection + wiring | `1e8caa8` | 4/4 |
| 10 Google Drive settings tile | `1e8caa8` | one Class 2 test, signed out → tap → "Backing up to …" |
| — Sign-in prompts (requested 2026-10-04) | see git log | `google_sign_in_banner_test.dart` 5/5, popover +1, account +2, page +1 |

**Sign-in prompts.** On request, sign-in is offered where the operator
already looks, not only in Settings. There's a "Sign in to Google" button in
the pill's popover whenever the active condition is `authExpired` (replacing
Retry, which cannot fix it), and a dismissible `MaterialBanner` above the
page when a Drive build is signed out or on the wrong account. Both are
non-modal. A modal at launch was offered and declined, because it would
cover the controls after a mid-service restart. The account now starts in a
`checking` state, so the banner never flashes on a machine whose saved
session is about to come back. The controller starts that check at launch.

Also fixed: `BackupScheduler.stop()` cancelled its timers only after an
`await`, so a caller that couldn't await it (a widget's `dispose`) left the
10-minute sweep timer alive. Found by the page test; timers now cancel
synchronously.

Every new test file was written before its implementation and run red first.
The failures were the expected missing-symbol compile errors, not
assertions, except Task 8, whose engine tests were also run red against the
reverted fix.

Sweep on Windows: `flutter analyze` clean. `flutter test` 763 passed, 1
failed: `test/backup/startup_test.dart` "SingleInstance the OS lock refuses
another process…", which fails identically on `main` on this machine.

## Found along the way

- **An unstamped fault would have stuck forever.** The controller files
  conditions under `fault.operation` (`backup_controller.dart`, `_raise`). A
  fault from a real target carries no operation, so it would have landed
  under `unknown`, and no later pull or push success removes that key. The
  mock never showed this because its scripted faults always name `pull`.
  Fixed in the engine (`AppFault.withContext`, applied in
  `_withStorageBoundary`).
- **The googleapis auth bridge freezes one token.**
  `extension_google_sign_in_as_googleapis_auth` 3.0.0 `authClient()` builds
  credentials with a made-up one-year expiry and no refresh token. Built
  once, it would fail with 401 about an hour into a service. Hence
  `AuthorizedDriveClient`.
- **A trashed folder lists as empty, not as an error.** That is why the
  folder is checked on every operation.

## Limitations

- **Never run against real Google Drive or real Google sign-in.** All Drive
  behaviour is proven against `FakeDrive`, which is faithful to the request
  shapes `googleapis` 17 actually sends (the real client runs end to end
  against it) but is still a fake. Plan Task 12, the hand test on the Mac mini
  and iPad, has not happened.
- **Apple configuration not done (plan Task 11).** Neither `Info.plist`
  carries `GIDClientID` or the reversed-client-id `CFBundleURLTypes`, and the
  macOS entitlements lack `keychain-access-groups`. Two things block it: the
  OAuth client IDs, which only the account owner can create, and a Mac to
  build and sign on. Until it's done, **do not build with
  `BACKUP_GOOGLE_ACCOUNT` set**: sign-in will fail at the native layer.
  Builds without the define are unaffected and behave exactly as on `main`.
- **No macOS or iOS build of this branch.** It was developed on Windows. The
  Phase 0 spike built `google_sign_in` 7.2.0 on both Apple platforms, but
  `googleapis` and the extension package are new since then.
- **Retention values (50 revisions, 90 days) are a proposal** awaiting
  Daniel's/John's OK. They are in `BackupService.retentionKeepCount` /
  `retentionKeepFor`.
- **No screenshots of the banner or the popover button either.** Same reason.
- **No screenshots.** The Settings tile is new UI. The lane process requires
  a looked-at screenshot from the macOS app, and that needs the Mac.
- **No cross-family review** of the outline or the code yet.
- **Wrong-account wording.** When the wrong account is signed in, the pill's
  message is the generic "Sign in to Google Drive in Settings…". The tile
  itself names both accounts.
