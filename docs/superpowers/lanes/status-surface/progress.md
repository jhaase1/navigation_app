# Status Surface Lane 3a Progress

Date: 2026-08-22  
Branch: `lane/status-surface`  
Plan: `docs/superpowers/plans/2026-08-21-status-surface.md` at
`ed36f076fe62f53d6e36247c9eaeaa27f47b25c8`

## Status

Tasks 1-9 are committed. Task 10 reached Daniel's merge gate with two open
acceptance findings: the mandated aggregate integration command did not pass,
and the staged conflict state did not reproduce in the plan's sequential
mock-run workflow. No commit, merge, or push was made by the Task 10 executor.

Lane 3a otherwise ships the always-clickable five-state backup pill, the
popover, the bounded persisted log, and `BackupController` with its serialized
event fold and lifecycle wiring. Production remains deliberately disabled
until a real target exists.

## Verification

| Command | Exit | Result |
|---|---:|---|
| `flutter analyze` | 0 | `No issues found!` |
| `flutter test` | 0 | `+617: All tests passed!` |
| `flutter test integration_test/` | 1 | No tests ran: Flutter found macOS, Chrome, an iPad, and an iPhone and required an explicit `-d`. |
| `flutter test integration_test/ -d macos` | 1 | `app_test.dart` passed 3 and skipped 2 live mock-rig cases; then `ipad_layout_test.dart` failed to launch because the debug log reader stopped. |
| `flutter test integration_test/ipad_layout_test.dart -d macos` | 0 | `+56: All tests passed!` when run by itself. |

The mock rig was not running during the supplemental macOS integration run, so
the two live switcher/camera cases in `app_test.dart` were skipped. The exact
aggregate command remains a failed sweep gate despite the standalone layout
file passing.

## Screenshot evidence

All files below were captured from the built macOS app with
`tools/mock_server/drive_macos_app.sh` and visually inspected after capture.

| Planned state | Pill | Popover | Observed result |
|---|---|---|---|
| Grey | `screenshots/grey-pill.png` | `screenshots/grey-popover.png` | Captured as specified: `Not backed up`. |
| Amber pending | `screenshots/amber-pending-pill.png` | `screenshots/amber-pending-popover.png` | Captured as specified: `1 change pending`. An empty mock target first needed one completed backup; editing that backed-up position then produced the pending state. |
| Green | `screenshots/green-pill.png` | `screenshots/green-popover.png` | Captured as specified: `Backed up just now`. |
| Red | `screenshots/red-auth-expired-pill.png` | `screenshots/red-auth-expired-popover.png` | Captured as specified: `Sign-in expired`; the pinned active row has no dismiss control. |
| Amber needs-review | Not captured | Not captured | The sequential conflict launch threw `AppFault(backup/targetMissing)` while staging because the new in-memory target did not contain the revision persisted by the earlier mock run. It rendered `Changes pending`, not `Needs review`. The actual wrong pill and popover are preserved as `screenshots/conflict-scenario-actual-pill.png` and `screenshots/conflict-scenario-actual-popover.png`. |

## Authorized deviations

- Tasks 5 and 6 were merged because the plan's seam between them could not
  compile or pass `flutter analyze` independently.
- Task 7 dropped the popover's `Deferred` badge. It depends on
  `controller.deferralApplies`, which Task 14 produces; Lane 3b must restore
  it.
- Task 9 fixed a `BackupController.start()` / `dispose()` race that the plan
  did not anticipate.
- Three plan-authored tests were corrected where their assertions failed
  against the correct implementation.

## Limitations

- No real backup target ships in Lane 3a. Google Drive lands in Phase 4; every
  successful backup screenshot in this packet uses the in-memory mock target.
- Conflict and adoption conditions are surfaced but are not resolvable until
  Lane 3b.
- The active condition is not persisted across restart (deviation D1). Task
  9's startup resume re-proves a pending failure, but does not remove that
  persistence gap.
- Controller startup has an unguarded status-refresh failure path.
  `BackupController._start()` calls `_refreshFacts()` directly before it
  installs event and mutation subscriptions or starts the scheduler, while the
  page calls `unawaited(_backup.start())`. A corrupt persisted
  `preset_names_*` value makes `ConfigBundle.fromStores()` throw a
  `FormatException`; startup then stops and the pill remains grey `Not backed
  up` while the controller and scheduler are dead. Impact in Phase 3 is low
  because production uses `BackupController.disabled()` and grey is truthful.
  Impact in Phase 4 with a real Drive target is high: this becomes the silent
  failure the surface exists to expose. The known fix shape is to route the
  startup fact refresh through the same guard used by the serialized fold, or
  catch the startup error and raise a status fault. No fix is implemented in
  this lane; Daniel decides at the merge gate whether to fix it before merge or
  carry it to Lane 3b.
- Lane 3b must restore the omitted `Deferred` badge.
- The mandated aggregate integration command is not green. Its exact invocation
  fails on device ambiguity, and the macOS-targeted aggregate also fails while
  launching the second file even though that file passes 56/56 alone.
- The live mock-rig integration cases were not exercised because the rig was
  not running; two `app_test.dart` cases were skipped in the supplemental run.
- The planned `Needs review` screenshots were not captured. In the plan's
  sequential mock-run workflow, persisted provenance points at a revision that
  evaporated with the previous in-memory target, so conflict staging throws
  `targetMissing` and the app shows `Changes pending` instead.
