# Steps to MVP

What stands between this app and running a live Sunday service on it.
Refreshed 2026-10-08, after #23–#37 landed together. Status words mean exactly
one thing:

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
| 4 | Google Drive target, Google sign-in, retention | **Merged** (#27), code-complete against a fake Drive and inert until built with `BACKUP_GOOGLE_ACCOUNT`. **Blocked** on the items below. |
| 5 | Switcher and camera faults on the pill | **Merged** (#34) |

### Phase 4 — what's left

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
   including leaving the Mac running for over an hour. **Add a ninth:** back
   up from the Mac, then list from the iPad. The scope is `drive.file`, and
   the iOS and macOS builds use separate OAuth client IDs; whether one
   client can see the other's files is unverified (the fake Drive shows
   everything to everyone). If it can't, the scope or client setup has to
   change before two machines can share backups.
5. **Decide retention.** Proposed: keep the newest 50, and keep anything
   younger than 90 days.

---

## 2. Operational landmines (from the August review)

| # | Landmine | Status |
|---|---|---|
| 1 | Swallowed hardware responses (`onResponse: (_) {}`) | **Merged** (#23). Failures styled as failures (#33), and a success no longer wipes one off the screen. |
| 2 | Switcher disconnect left the UI reading Live | **Merged** (#23, #29, #30). The badge now follows the switcher alone. Still open for an idle half-open link — see §4. |
| 3 | "No devices connected" lockout blocked offline prep | **Merged** (#23) |
| 4 | No in-flight feedback on cues | **Merged** (#24) |
| 5 | Sunday lineup lost on tab switch or restart | **Merged** (#25) — kept 20 minutes past the screen going off, and never past 4 AM (see §4) |
| 6 | Export/import path unreachable in the macOS sandbox | **Merged** (#26) |

### Found since, all merged

| Problem | PR |
|---|---|
| A slow CUT was re-sent up to 3 more times, so the wrong shot could go to air | #30 |
| One lost switcher reply made every later command report failure (a re-tap double-fires) | #30 |
| One garbled switcher reply marked up to 3 waiting commands as done | #30 |
| Demo → Live brought cameras back "connected" on their demo stand-ins | #31 |
| A dropped switcher kept reconnecting after Demo, an IP change or a fresh Connect | #29 |
| A camera's red pill fault stuck after reconnecting it by hand | #34 |
| A lineup carried from one service into the next | #25, plus the 4 AM cutoff |
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
| After a failed camera Connect or a mode switch, the Panel tab "recalled" presets on a Demo stand-in while the real camera was dead | #31 |
| Switching Live/Demo left the badge reading Live and the Connect banner hidden | #23 |
| #26's lock pinned test packages below main's (resolved on an older Flutter) | #26 |
| A dropped switcher link could never be reconnected (closed response stream) | #29 |
| A camera that stopped answering stayed "connected" for the rest of the service | #31 |
| An unstamped Drive fault would never clear from the pill | #27 |
| Fault log showed the newer of two same-tick entries second (flaky test on Windows) | #32 |
| Single-instance OS-lock test could not run on Windows | #28 |

---

## 3. How it landed

On 2026-10-08, #28, #32 and #37 merged directly. The rest were merged in
stack order (#23, #29, #30, #33, #36, #31, #34, #24, #25, #26, #27, #35) on
one integration branch, conflicts resolved as this section used to describe,
then fixed for what two independent reviews (Claude Opus 5.5 and Grok 4.7)
found. Every fix started from a failing test:

| Review finding | Fix |
|---|---|
| #29 + #34: the pill stayed "Switcher offline" after an automatic reconnect | Reconnect clears the fault |
| #33: the next cue's success wiped a red failure off the screen | A failure is only replaced by a newer failed command, or by its own link coming back |
| #30: "Roland reconnected" was the last word after a cue whose reply was lost, inviting a second CUT | Link messages never hide a failed cue, and a lost reply now says the command may have run |
| #23: the badge read Live with a dead switcher while any camera was up | The badge follows the switcher alone |
| #36: recalls queued behind a dead camera fired ~20 s late, after it came back | They fail instead |
| #36/#31: a released camera service kept sending stale recalls | Released services are disposed |
| Camera "busy" (`ER2:R04`) was never retried | Matched by prefix |
| #25: a lapsed lineup still fired its reader cue after the Mac woke | Firing renews first; a lapsed lineup fails with "No one assigned" |
| #25: a Mac mini with its display asleep kept the lineup forever | A lineup never outlives 4 AM (late enough for Midnight Mass) |
| #25: a corrupt saved lineup threw on every pick | Loads as empty and is cleared |
| #27: two marked Drive folders split backups; a fresh install read the empty one | Backups pause with "Duplicate backup folders" until merged by hand |
| #27: a Google sign-in SDK error stuck on the pill until restart | Mapped to faults that clear; every fault names its operation |
| #27: offline at launch read as "sign in again" | Reads as offline |
| #27: a refused Drive grant left Settings saying "Backing up" | Signed in only after the grant |
| #36: unused import; #26: lock drifted on `pub get` | Fixed |
| #23 broke `integration_test/` (Settings moved to the AppBar) | Helpers updated |

## 4. Still open

**Needs the Mac and real hardware.** Code can't settle these.
- **Screenshots** of every UI change, against the mock rig, looked at:
  - Offline badge and banner
  - cue spinner/check/error
  - failure snackbar
  - red device pill (including a long camera name on the iPad in portrait: the label
    should shorten with an ellipsis, not overflow)
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
A Mac mini left on with its display asleep keeps renewing, so a lineup also
never outlives the 4 AM after it was saved: a Mass crossing midnight keeps
its readers, and Saturday's are gone before Sunday's first Mass.

**Follow-ups from the 2026-10-08 review, not fixed:**
- **Idle switcher heartbeat.** With no traffic and no FIN/RST (power loss, a
  cable pulled at the far end) the link reads Live until the next cue waits
  out the 5 s ACK timeout. Needs a periodic query or TCP keepalive, tested
  on the real V-160HD — a wrong reply format would drop the link every time.
- **Dead-camera failures arrive late.** Queued recalls now fail instead of
  firing late, but the first failure takes ~16.5 s (5 s timeout × 3 tries
  plus backoff). Shorter recall timeouts are a retry-policy call.
- **The pill shows one fault at a time**, the newest. With the switcher and a
  camera both down it names only one, and once Drive is live a device fault
  hides "Sign in", "Review" and "Name this machine" until the device is back.
- **A Drive status-refresh fault** (`operation: 'status'`) is never cleared
  once raised — the same stuck-until-restart shape the scheduler had.
- **Offline Drive restore** leaves Settings reading "Checking Google
  sign-in…" for as long as the machine is offline.
- A Service tab rebuilt while a cue was out stops the spinner but never
  shows that cue's result.
- `docs/superpowers/lanes/drive-target/plan.md` decision 7 still describes
  "oldest folder wins"; the code now pauses on two folders.

**Known limits, accepted for MVP unless the rehearsal says otherwise.**
- **Cue "done" means the camera accepted the preset**, not that it has stopped
  moving (#24). Tracking arrival needs a verified Panasonic status query.
- **A command whose ACK is genuinely lost fails, and the app reconnects to
  the switcher** (#30). It is never re-sent, to avoid running it twice. Any
  other command waiting at that moment fails too, and the badge briefly
  reads Offline. Replies carry no id, so after one goes missing nothing
  later can be matched to its command; a fresh link is the only safe reset.
- **A camera Connect that fails stops the automatic check on that camera**
  (#31). Pressing Connect lets go of the camera first; if the Connect then
  fails, a camera that powers back on later is not picked up by itself. The
  pill stays red and the error shows, so press Connect again. Worth trying
  in the rehearsal.
- **Command failures stay as failure snackbars**, not standing pill conditions
  (#34).
