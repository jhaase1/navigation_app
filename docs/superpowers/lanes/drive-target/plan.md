# Lane: Drive target and auth (Phase 4) — outline

**Tier 3.** New persisted keys, a new storage protocol, and the first real
off-machine write of operator configuration. Being wrong here is invisible
until the day a backup is needed.

Branch `lane/drive-target`, worktree `.worktrees/drive-target`, off `main` at
`5b4c707`.

Spec: `docs/superpowers/specs/2026-08-21-drive-backup-and-status-surface-design.md`
(§Drive specifics, §Authentication, §Failure taxonomy, §Phasing item 4).
Spike: `docs/superpowers/spikes/2026-08-21-google-signin-platform-spike.md`.

## Goal

Backups leave the machine. `DriveBackupTarget` implements
`BackupTargetAbstract` against Google Drive v3. The Mac mini and the iPad both
sign in to the project's shared Google account, and the engine that has run
against `MockBackupTarget` since Phase 2 runs unchanged against Drive.
Retention actually runs.

## Decisions

Settled by the spec or the spike unless marked **NEW**.

1. **One shared Google account, signed in through OAuth on each machine.**
   The project's account is a normal Google account, used through
   `google_sign_in`.
   - **NEW:** it is *not* a Google Cloud "service account". A service account
     would need a private key shipped inside the app, which anyone with the
     binary could extract. Since 2025 service accounts also have no Drive
     storage quota of their own.
2. **NEW — the account address is not committed.** The repo is public.
   - It is supplied at build time: `--dart-define=BACKUP_GOOGLE_ACCOUNT=<address>`.
   - Drive backup is **on only when that define is set** and the platform is
     macOS or iOS. Otherwise the controller stays `disabled()`, as today, and
     `BACKUP_MOCK=true` still wins.
   - When set, the signed-in account must match it, case-insensitively. A
     volunteer signing in with a personal account is refused rather than
     scattering backups into the wrong Drive.
3. **Scope `drive.file`, in a visible folder** named `Production Control
   Backups`, so the backups can be found and recovered by hand.
4. **macOS and iOS only.** `google_sign_in` 7.2.0 has no Linux or Windows
   implementation (spike). Elsewhere, Settings says Drive backup runs on the
   Mac and iPad.
5. **Server checksum.** `BackupRevision.bodyChecksum` is Drive's own
   `md5Checksum`, which is the same algorithm as `bodyChecksumOf` in
   `canonical_json.dart:39`. `fetch` recomputes MD5 over the downloaded bytes
   and throws `malformedRemote` on a mismatch.
6. **Target identity is `drive:<account, lowercased>`.** The folder id is
   *not* part of it.
   - **NEW:** if the folder is trashed or deleted, the target finds or creates a
     fresh one, which is empty. The engine's existing pull branch 2 (remote
     empty while the pointer is set) then invalidates the head and raises
     `targetMissing`. That is the spec's "distinct condition that invalidates
     the pointer", with no new engine code.
7. **Folder discovery**, in this order:
   1. Use the persisted folder id (`backup_drive_folder`, stored as
      `<account>|<folderId>`).
   2. Otherwise search for folders carrying our marker `appProperties
      {navBackup: root}`.
   3. Otherwise create one.

   If two machines both created one, the **oldest `createdTime` wins, ties go
   to id**. The folder is re-checked (`files.get`, fields `id,trashed`) at the
   start of every public operation. It costs one request per operation, about
   every 10 minutes, and it is the only way to notice a trashed parent: listing
   children of a trashed folder returns an empty list, not an error.
8. **Revision metadata lives in `appProperties`:**
   - `navBackup=revision`
   - `contentHash`
   - `parentRevisionId` (omitted when null)
   - `deviceLabel`
   - `schemaVersion`

   Drive caps each key plus value at 124 bytes. **NEW:** `deviceLabel` is
   truncated on a UTF-8 boundary to fit. Only marker-tagged, untrashed files
   count as revisions, so anything dropped into the folder by hand is ignored.
9. **Ordering:** `orderBy=createdTime desc` on server time. Drive cannot order
   by id, so ties are broken on the client by id, descending, matching
   `MockBackupTarget._ordered`. File names are never used for ordering.
10. **NEW — prune moves files to the trash, it doesn't delete them.** A wrong
    prune is then recoverable for 30 days from the Drive web UI. The cutoff
    uses an injectable clock (`DateTime.now` in production).
11. **NEW — retention policy: keep the newest 50, and keep anything under 90
    days old.** A revision is trashed only when it fails both. **Needs
    Daniel's/John's OK.** Prune runs from the scheduler's 10-minute sweep, at
    most once per 24 h per run of the app (tracked in memory, no new persisted
    key). A prune failure is surfaced with `operation: 'prune'` and never
    blocks a push.
12. **NEW — fresh credentials on every request.**
    `extension_google_sign_in_as_googleapis_auth.authClient()` wraps one access
    token with a fake one-year expiry and no refresh token. Real tokens die
    after about an hour, so a client built once would start failing with 401
    mid-service. Instead:
    - `AuthorizedDriveClient` asks `authorizationHeaders(promptIfNecessary:
      false)` for fresh headers on every request.
    - On a 401 it clears the token (`clearAuthorizationToken`) and retries
      once.
    - If there are no headers at all, it throws `authExpired` without
      touching the network. The engine never triggers a sign-in prompt.
13. **NEW — every request has a timeout:** 30 s, or 120 s for uploads and
    downloads. Without one, a hung TCP connection would wedge the scheduler's
    single-flight queue forever.
14. **Error mapping, at the target boundary only:**

| Drive / transport says | `BackupFailureKind` |
|---|---|
| no auth headers, or HTTP 401 after the retry | `authExpired` |
| 403 `rateLimitExceeded`, `userRateLimitExceeded`; 429 | `rateLimited` |
| 403 `storageQuotaExceeded` | `storageFull` |
| any other 403 | `permissionDenied` |
| 404 | `targetMissing` |
| 5xx | `transientServer` |
| `SocketException`, `ClientException`, `TimeoutException`, `HandshakeException` | `offline` |
| body checksum mismatch, unparseable metadata | `malformedRemote` |
| 400 and anything else | `unknown` (slow sweep only) |

## Before it can run for real: setup only the account owner can do

These are the lane's blocking dependencies. Code and tests proceed without
them.

1. **Google Cloud project:** enable the Google Drive API.
2. **OAuth consent screen:**
   - External, app name "Production Control", scope `.../auth/drive.file`.
   - **Publish it to "In production".** In "Testing" mode Google expires the
     grant after 7 days, so the Mac mini would silently lose backup every
     week. `drive.file` is a non-sensitive scope, so publishing needs no
     Google verification.
3. **OAuth client IDs:** one iOS-type client for the iOS bundle id and one for
   the macOS bundle id. Hand the client IDs over. They are not secrets; they
   ship inside every app binary.
4. **Builds:** pass `--dart-define=BACKUP_GOOGLE_ACCOUNT=<address>` on the
   Mac mini and iPad builds.

## Tasks

Each one names its test-policy class (`docs/learned/verification.md`). Tests
mock at the HTTP client and the platform channel only, never at a service this
app owns.

| # | Task | Class | Tests that exist when done |
|---|---|---|---|
| 1 | Dependencies: `google_sign_in` ^7.2.0, `googleapis` ^17.0.0, `extension_google_sign_in_as_googleapis_auth` ^3.0.0 | — | suite stays green |
| 2 | `FakeDrive`: an in-memory Drive v3 REST server behind `http/testing` `MockClient`. Supports files.create (metadata-only and multipart), files.list (only the exact `q` forms we send, and fails loudly on anything else), files.get (metadata and `alt=media`), files.update (`trashed`), server clock, `md5Checksum`, per-request fault injection, and a request log | 4 (test support) | — |
| 3 | Shared target contract suite, run against **both** `MockBackupTarget` and `DriveBackupTarget`, so the mock the engine was proven against provably behaves like Drive | 1 | `test/backup/backup_target_contract.dart`, `mock_backup_target_contract_test.dart`, `drive_backup_target_contract_test.dart` |
| 4 | `DriveBackupTarget`: folder identity, put/latest/list/fetch, checksum verification, prune to the trash, pagination, metadata truncation | 1 | `test/backup/drive_backup_target_test.dart` |
| 5 | Error mapping at the boundary | 1 | same file, one table-driven group |
| 6 | `AuthorizedDriveClient`: fresh headers per request, 401 → clear and retry once, no headers → `authExpired` without sending, body preserved on retry, timeouts | 1 | `test/backup/authorized_drive_client_test.dart` |
| 7 | `GoogleDriveAccount`: lightweight restore, interactive sign-in, expected-account enforcement, sign out, state notifier. Tested against a fake `GoogleSignInPlatform` (the plugin's own platform seam) | 1 | `test/backup/google_drive_account_test.dart` |
| 8 | Retention: the scheduler's sweep prunes with the policy at most once per 24 h; a prune fault is logged as `prune` and does not block push | 1 | `test/backup/backup_retention_test.dart` |
| 9 | Wiring: a pure `selectBackupTarget(mock, account, platform)` decision table; `forEnvironment` builds Drive when selected | 1 for the table, 2 for the wiring | `test/backup/backup_target_selection_test.dart` |
| 10 | Settings → Backup → "Google Drive" tile showing signed in as X / not signed in / wrong account, which signs in or out on tap and pulls after sign-in. `authExpired` copy points at it | 2 (one test) + 3 (screenshot) | one test in `test/settings_dialog_test.dart` |
| 11 | Apple config: `GIDClientID` plus `CFBundleURLTypes` (reversed client id) in both `Info.plist` files; `keychain-access-groups` = `$(AppIdentifierPrefix)com.google.GIDSignIn` in both macOS entitlements | — | blocked on the client IDs; verified only by the hand test |
| 12 | Hand test on the Mac mini and the iPad against the real account (checklist below) | — | receipts in `progress.md` |
| 13 | Sweep: analyze, full suite, integration tests, screenshots, and `progress.md` with `## Limitations` | — | — |

### Hand-test checklist (Task 12)

1. Fresh install, sign in with the shared account: the pill goes green and a
   `Production Control Backups` folder appears in Drive with one file.
2. Edit a position: about 30 s later a second file appears, and its
   `appProperties` show the parent id.
3. Sign in on the iPad: it adopts the Mac's revision (pristine) or asks
   (non-pristine).
4. Edit on both while one is offline: a conflict appears on the pill and the
   dialog resolves it.
5. Trash the folder in the Drive web UI: the next sweep reads `targetMissing`,
   and the following push repopulates a new folder.
6. Sign in with a different Google account: it is refused, with the expected
   account named.
7. Leave the Mac running for more than 1 h: still green, which proves the
   per-request token refresh.
8. Airplane mode: the pill reads `offline` and recovers on its own when the
   network returns.

## Deviations from the lane process, said out loud

- **No fresh spike against real Drive.** The process wants one before the
  spec. It needs the OAuth client IDs (above) and a Mac. This lane's code was
  written on Windows, where `google_sign_in` has no implementation. The
  Phase 0 spike covered resolution, native builds and token storage. The
  end-to-end Drive path is proven only by `FakeDrive` until Task 12 runs.
- **No cross-family review yet.** This outline goes to Daniel and John first;
  reviewers run on the committed plan if they want them.
- **This is an outline, not a real-Dart plan.** The user asked for outline,
  then tests, then implementation in one pass.
