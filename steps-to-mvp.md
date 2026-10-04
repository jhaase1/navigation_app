# Steps to MVP

What stands between this app and running a live Sunday service on it.
Refreshed 2026-10-04. Status words mean exactly one thing:

- **Merged** — on `main`.
- **In PR** — written and tested, waiting for review. "Stacked on #N" means
  the PR targets #N's branch and retargets to `main` once #N merges.
- **Blocked** — needs something only a person or a Mac can provide.
- **Open** — nobody has done it.

Specs and plans: `docs/superpowers/specs/2026-08-21-drive-backup-and-status-surface-design.md`,
`docs/superpowers/plans/`, and lane packets under `docs/superpowers/lanes/`.

---

## 1. Backup and status surface (spec phases 0–5)

| Phase | What | Status |
|---|---|---|
| 0 | Platform and auth spike | **Merged** (`docs/superpowers/spikes/`) |
| 1–2 | Foundations and engine against `MockBackupTarget` | **Merged** |
| 3a | Status pill, log popover, lifecycle | **Merged** (PR #19) |
| 3b | Conflict dialog, revision history, machine naming | **Merged** (PR #22) |
| 4 | Google Drive target, Google sign-in, retention | **In PR #27**, code-complete against a fake Drive. **Blocked** on the items below. |
| 5 | Switcher and camera faults on the pill | **In PR #34** (stacked on #31) |

### Phase 4 — what's left after PR #27 merges

1. **Google Cloud setup (account owner):**
   - Enable the Drive API.
   - Set the OAuth consent screen to `drive.file` and **publish it to
     "In production"**. Testing mode expires the grant every 7 days.
   - Create iOS-type OAuth client IDs for the iOS and macOS bundle IDs.
2. **Apple config (needs the client IDs and a Mac):**
   - `GIDClientID` and the reversed-client-id `CFBundleURLTypes` in both
     `Info.plist` files.
   - `keychain-access-groups` = `$(AppIdentifierPrefix)com.google.GIDSignIn`
     in both macOS entitlements.
3. **Build** the Mac mini and iPad with
   `--dart-define=BACKUP_GOOGLE_ACCOUNT=<shared account>`. Don't set it before
   step 2: sign-in fails without the Apple config.
4. **Hand test** — the 8 steps in `docs/superpowers/lanes/drive-target/plan.md`,
   including leaving the Mac running for over an hour.
5. **Decide retention.** Proposed: keep the newest 50, and keep anything
   younger than 90 days.

---

## 2. Operational landmines (from the August review)

| # | Landmine | Status |
|---|---|---|
| 1 | Swallowed hardware responses (`onResponse: (_) {}`) | **In PR #23**. Failures styled as failures in **#33** (stacked on #23). |
| 2 | Switcher disconnect left the UI reading Live | **In PR #23** (Offline badge). Auto-reconnect in **#29**, command path in **#30** (stacked). |
| 3 | "No devices connected" lockout blocked offline prep | **In PR #23** |
| 4 | No in-flight feedback on cues | **In PR #24** |
| 5 | Sunday lineup lost on tab switch or restart | **In PR #25** — kept for 20 minutes past the screen going off, then cleared (see §4) |
| 6 | Export/import path unreachable in the macOS sandbox | **In PR #26** |

### Found since, also in PR

| Problem | PR |
|---|---|
| A slow CUT was re-sent up to 3 more times, so the wrong shot could go to air | #30 |
| One lost switcher reply made every later command report failure (a re-tap double-fires) | #30 |
| One garbled switcher reply marked up to 3 waiting commands as done | #30 |
| Demo → Live brought cameras back "connected" on their demo stand-ins | #31 |
| A dropped switcher kept reconnecting after Demo, an IP change or a fresh Connect | #29 |
| A camera's red pill fault stuck after reconnecting it by hand | #34 |
| A lineup carried from one service into the next | #25 |
| One refused preset froze that camera's queue: every later recall waited forever | #36 |
| Letting go of the switcher mid-reconnect still logged a session in | #29 |
| A Demo switch, IP change or second Connect made while the switcher was still dialling was overridden (real switcher live under a Demo badge, or an orphaned session) | #23 |
| A switcher `ERR:n;` reply read as success | #30 |
| A camera probe that timed out left its socket open | #31 |
| A failed Connect cleared "Switcher offline" from the pill | #34 |
| Re-picking the service let an in-flight cue fire twice | #24 |
| Changing one reader on a lapsed lineup re-saved the stale ones | #25 |
| An offline or hung Google restore left backups signed out or stalled until restart | #27 |
| The Panel tab kept driving cameras that Settings had replaced | #37 |
| A camera down in Live came back on its real service after switching to Demo; a camera Connect mid-dial was installed under the Demo badge | #31 |
| A failed camera Connect cleared its pill fault; same-named cameras shared one fault | #34 |
| Leaving the Service tab and coming back let an in-flight cue fire twice | #24 |
| #26's lock pinned test packages below main's (resolved on an older Flutter) | #26 |
| A dropped switcher link could never be reconnected (closed response stream) | #29 |
| A camera that stopped answering stayed "connected" for the rest of the service | #31 |
| An unstamped Drive fault would never clear from the pill | #27 |
| Fault log showed the newer of two same-tick entries second (flaky test on Windows) | #32 |
| Single-instance OS-lock test could not run on Windows | #28 |

---

## 3. Merge order

The stacks have to land bottom-up:

```
main ← #23 ← #29 ← #30
          ← #31 ← #34
          ← #33 ← #36
main ← #24, #25, #26, #28, #32, #37   (independent)
main ← #27                       (after #23 and #26 — see below)
```

Conflicts to expect, all in the merge, none in the PRs themselves:
- `service_tab.dart`: #24, #25 and #33. Keep #24's per-step cue key and
  in-flight set, #25's lineup expiry listener and renew-before-assign, and
  #33's `_fail` calls. #24's dropdown `onChanged` clears `_cueStates` and
  bumps `_cueGeneration`; #25 replaces it with `onChanged: _selectService`.
  Move that clear and bump into `_selectService` (and its restore paths),
  or a late result stamps a check onto the newly picked service's cue.
- `multi_device_control_page.dart`, the switcher link watcher: #29 and #34.
  When both are in, #29's "link came back" path must also call
  `clearDeviceFault` for the switcher, or the pill stays red after an
  automatic reconnect. Start that fix from a failing test: connect live,
  drop the link (pill reads "Switcher offline"), restore it, expect the
  pill clear. Keep #34's `_releaseRoland(clearFault: false)` before a
  Connect, so a Connect that fails leaves the pill red.
- `multi_device_control_page.dart`: #27 adds the Google sign-in banner into
  the offline layout that #23 replaces. Re-add the banner to #23's layout —
  dropping it silently hides "sign in to resume backups". #27 also
  re-indents the whole TabBarView and still carries `onResponse: (_) {}`
  three times: taking its side of that block brings back landmine 1
  (swallowed device responses). Take #23's side, or rebase #27 onto #23
  first.
- `multi_device_control_page.dart`: #25 × #31 both add to `initState` and
  `dispose` — keep both `_lineupLease` and `_cameraHealth`. #33 × #29 meet
  in the same file and its test (the `_showFailure` line below). #29 and #33
  both edit `pinp_tab.dart`; it auto-merges, keep #29's `onError: (_) {}`.
- `test/panasonic_service_test.dart` and the page test: #36 × #31 — take
  both sides.
- #27 and #26 both touch `pubspec.yaml`/`pubspec.lock`, the plugin
  registrants and `settings_dialog_test.dart`: take both sides.
- Once #33 is in alongside #29 and #31, switch their "connection lost" and
  "not responding" messages from `_showResponse` to `_showFailure`, or they
  show in success grey.

---

## 4. Still open

**Needs the Mac and real hardware.** Code can't settle these.
- **Screenshots** of every UI change, against the mock rig, looked at:
  - Offline badge and banner
  - cue spinner/check/error
  - failure snackbar
  - red device pill
  - Drive tile, sign-in banner and popover button
- **`flutter test integration_test/`** on the merged result.
- **Hand tests:**
  - native export/import dialogs (#26) on the Mac mini and iPad. Export,
    then import that same file: the test fake can't prove the file was
    actually written
  - the switcher's error reply. The app now treats `NACK`, `ERROR` and
    `ERR:n;` as a refusal (#30). Send one bad command on the rig (for
    example `PGM:INPUT99;`) and confirm the reply is one of those
  - #26's lock file: run `flutter pub get` on the Mac and confirm it
    leaves `pubspec.lock` unchanged
  - auto-reconnect (#29) against a real V-160HD, by pulling the cable
- **A dress rehearsal on the actual rig** — Mac mini, V-160HD, PTZ cameras —
  running a full service's cues, with a pulled Ethernet cable, a powered-off
  camera and an app restart mid-service. **This is the MVP gate.** Everything
  above is proven only against mocks and fakes.

**The lineup lifetime (#25).** A saved lineup lives 20 minutes past its last
renewal. The app renews it every 5 minutes while it is on screen, and on
coming back. On the iPad, locking the screen or leaving the app stops the
renewals, so the lineup is gone 20 minutes later. A Mac window behind
another app still counts as on screen, so running slides elsewhere is safe.
**Gap:** Flutter cannot see the Mac's *display* sleeping, so a Mac mini left
on with the app open keeps its lineup indefinitely. Closing that needs a
small native hook (macOS screen-sleep notification), built and tested on
the Mac.

**Known limits, accepted for MVP unless the rehearsal says otherwise.**
- **Cue "done" means the camera accepted the preset**, not that it has stopped
  moving (#24). Tracking arrival needs a verified Panasonic status query.
- **A command whose ACK is genuinely lost fails, and the app reconnects to
  the switcher** (#30). It is never re-sent, to avoid running it twice. Any
  other command waiting at that moment fails too, and the badge briefly
  reads Offline. Replies carry no id, so after one goes missing nothing
  later can be matched to its command; a fresh link is the only safe reset.
- **Command failures stay as failure snackbars**, not standing pill conditions
  (#34).
