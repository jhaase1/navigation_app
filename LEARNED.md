# Learned

Verified facts about this repo: stack, run commands, architecture, and the
behaviours that have already burned someone. Read this first.

**Admission bar:** something had to be *verified* — a command that ran, a file
read, a failure observed. Not a plan, not a preference, not a rule invented
after one incident. **Cap: 300 lines.** Over it, the least load-bearing entry
comes out the same sitting.

## Where the facts live

| Doc | Holds |
|---|---|
| `HANDOFF.md` | The network setup and the Roland telnet protocol as verified in Aug 2026. Still the record for wiring, IPs, and the ACK/STX findings. Not maintained here — this file does not duplicate it. |
| `docs/learned/verification.md` | The test policy. Which surfaces get tests, which get screenshots, which get neither. |
| `docs/superpowers/runbooks/lane-process.md` | How work gets done: tiers, worktrees, the merge gate. |
| `docs/superpowers/specs/` | Dated design docs. Receipts, not owner docs — they never override live code. |
| `.github/copilot-instructions.md` | Maintained for the collaborator's tooling. Shared file; leave it alone unless Daniel says otherwise. |

## Stack

- **Flutter 3.47.0 stable**, Dart SDK `>=3.0.0 <4.0.0`. Verified 2026-08-21.
- Runtime deps are deliberately thin: `http` (`^1.5.0` — `AbortableRequest`),
  `shared_preferences`, `logging`, `crypto`, `cupertino_icons`, plus three
  added 2026-10-08 on Daniel's go-ahead to merge it all: `file_picker` (native export/import,
  #26), `google_sign_in` and `googleapis` (Drive backup, #27). Dev adds
  `flutter_test`, `integration_test`, `mocktail`, `flutter_lints`,
  `flutter_launcher_icons` and the platform-interface fakes.
- **macOS and iOS build with Swift Package Manager. CocoaPods was dropped**
  (`5608d36`) after the Flutter 3.47 migration. Don't re-add a Podfile.
- macOS needs the `network.client` entitlement in both `DebugProfile` and
  `Release.entitlements` or every outgoing socket fails with
  "Operation not permitted".
- `analysis_options.yaml` excludes `build/` and the platform dirs (`4cb37d9`).

## Commands

```bash
flutter run -d macos                  # the real app
flutter analyze                       # must be clean
flutter test                          # full suite, fast
flutter test test/<name>_test.dart    # the one file you're iterating on
flutter test integration_test/        # layout + device-control flow
```

## The mock rig — test without hardware

`tools/mock_server/` runs a fake V-160HD and three fake AW-series PTZ cameras
that the **unmodified app** connects to and drives, plus a browser inspector
showing what each command actually did.

```bash
sudo python3 tools/mock_server/run.py          # switcher + 3 cameras
python3 tools/mock_server/run.py --no-cameras  # switcher only, no root
```

Then **Settings → Connections**: Roland `127.0.0.1`, cameras `127.0.0.2`,
`.3`, `.4`. Inspector at <http://127.0.0.1:8080>. Standard library only.

- **Leave the app in Live mode.** Demo mode swaps in `MockRolandService` /
  `MockPanasonicService` and never touches the network, so it bypasses the rig
  entirely and every test against it is vacuous.
- **Root is only for the cameras.** `PanasonicService.ipRegex`
  (`panasonic_service.dart:346`) takes a bare dotted quad with no port, so each
  mock camera must answer on its own address at port 80 — which needs an `lo0`
  alias and a privileged port.
- `127.0.0.2-4` are used instead of the real `10.0.1.10-12` on purpose: aliasing
  the church's actual camera addresses onto this Mac would shadow the real
  cameras if an alias were ever left in place before a service.

## Screenshots of the real app

`tools/mock_server/drive_macos_app.sh` drives the built macOS app
deterministically — `shot`, `click`, `type`, `key`, `bounds`. It pins the window
to a fixed frame before every action, because the terminal steals focus back
after each command and stale coordinates put the click on whatever is in front.

Needs `cliclick` (`brew install cliclick`) plus Accessibility and Screen
Recording permission for the controlling terminal. **Screenshots come out at
the display's backing scale** — a 1200×820 window gives a 2400×1640 image, so
halve image coordinates before feeding them back to the script.

## Architecture

- **Eight `SharedPreferences`-backed stores** — device config, people, positions,
  services, height ranges, operator profiles, preset names, visibility. Each
  owns its own keys and its own `toJson`/`fromJson`.
- **`ConfigBundle`** (`lib/services/config_bundle.dart`) gathers all of them
  into one JSON document and can read it back. Wired to manual export/import in
  `settings_dialog.dart:176` onward. This is the whole backup story today.
- **`RolandService`** speaks telnet over TCP; **`PanasonicService`** speaks
  HTTP. Both have an `abstract/` interface and a `mock/` implementation used by
  demo mode.
- **`preset_resolver.resolvePreset`** decides which camera preset points at a
  person: explicit per-person override first, then a `HeightRange` match on
  height, then null. Getting this silently wrong aims a camera at nobody.

## Known silent failures

These are the reason the test policy draws Class 1 where it does. Found
2026-08-21; status as of the 2026-10-08 integration of #23–#37, each line
backed by a test that failed first.

1. **A dead switcher reading Live.** Fixed for a link that errors or closes:
   every device response reaches the operator (#23), failures are red and
   not wiped by the next success (#33), the badge follows the switcher alone,
   the link reconnects itself (#29) and the pill says "Switcher offline"
   until it does (#34). **Still live for an idle half-open link**: no
   heartbeat or TCP keepalive, so a switcher that loses power with no FIN/RST
   reads Live until the next cue waits out the 5 s ACK timeout. Proven by a
   review repro; the fix is a protocol change that needs the real V-160HD.
2. **Permanent ACK desync.** Fixed (#30): each command is sent once, a lost
   ACK resets the link instead of letting the next ACK complete the wrong
   command, and one garbled reply completes one waiter.
3. **A wedged camera.** The queue can no longer wedge (#36); a refused
   command fails its caller and the next one goes out. An unreachable camera
   is noticed by the liveness probe (#31) — the probe bypasses the queue, so
   it never detected a queue wedge; #36 is the fix for that. Commands queued
   behind a camera that never answers now fail instead of firing late, and a
   released camera service is disposed so it sends nothing more.

The backup status surface (pill, popover, log, `BackupController`) carries
device faults since #34. Google Drive (#27) is compiled in but inert unless
built with `--dart-define=BACKUP_GOOGLE_ACCOUNT=...`, and must not be until
the Apple config in `steps-to-mvp.md` lands.

## Agent setup

The superpowers skills live in `.claude/skills/`, vendored into the repo so they
travel with a clone. The upstream plugin is **disabled for this project**
(`.claude/settings.json`) — it injects a "you have superpowers" preamble into
every single turn, which is noise, and its copies here have Daniel's test policy
folded in. Provenance is stamped at the top of each `SKILL.md`; diff against
`superpowers@6.3.0` (`e4a2375`) before pulling upstream changes.
