# Lane 3b — Backup Resolution Progress

Date: 2026-08-23
Branch: `lane/backup-resolution`
Plan: `docs/superpowers/plans/2026-08-21-status-surface.md`
Code HEAD at screenshot commit: `f6067b5`
Screenshot commit: `b08cccf` (agy), inventory corrected after the controller
looked at every PNG, then four files recaptured on a second pass.

Captured from the real macOS app (`Production Control`) with
`tools/mock_server/drive_macos_app.sh` against `--dart-define=BACKUP_MOCK=true`.
The conflict shots add `--dart-define=BACKUP_SCENARIO=conflict`; the two name
dialogs come from a second launch with prefs wiped and **no** scenario, so the
machine is genuinely unnamed. Live mode. Not connected. Agy tightened `pin()`
in the drive script (`AXRaise` + `frontmost`) so the window actually comes to
the front.

The Settings list scrolls past the window, and the Backup History / Name this
machine tiles sit below the fold. `cliclick` has no scroll command and the
Flutter list does not take keyboard focus, so the second pass drove a real
scroll-wheel event from a throwaway Swift helper in the scratchpad. Nothing in
the repo changed to make a screenshot easier.

## Screenshot evidence

Every claim below is from opening the PNG, not from a write-up.

| Planned | File | What it actually shows |
|---|---|---|
| Needs-review pill | `screenshots/conflict-pill.png` | **Pass.** Orange `Needs review`, help icon, Production Control, Live mode. |
| Popover with Review | `screenshots/conflict-popover-review.png` | **Pass.** Pinned amber row `Another machine saved a different configuration.` / `conflict`. Header action **Review**, not Retry now. (Header also says “This configuration has never been backed up.” — last-success line, not a failed capture.) |
| Conflict dialog + real diff | `screenshots/conflict-dialog-diff.png` | **Pass.** Title `Two machines have different settings`. `Daniel's iPad saved a copy 31 Dec, 7:00 PM.` Lines: `Positions: 1 more`, `Operator panels: 1 missing`, `Camera addresses: 1 changed`, `Switcher address: 1 changed`. Buttons Decide later / Use their copy / Keep mine. |
| Comparison-failed | *(omitted)* | In-memory mock serves the body; no scenario for a failed download. Not faked. |
| Backup history list | `screenshots/history-list.png` | **Pass (recaptured).** The dialog itself now: title `Backup history`, two revision rows — `Daniel's iPad` / `31 Dec, 7:00 PM` with **Re-apply**, and `This machine` / `31 Dec, 7:00 PM` with **Restore** — plus Close, over the dimmed Settings sheet. |
| Restore confirm | `screenshots/restore-confirm.png` | **Pass (recaptured, better case).** Re-apply on **Daniel's iPad** instead of this machine, so the confirm carries a real diff: `Saved by Daniel's iPad, 31 Dec, 7:00 PM.` / `Compared with this machine:` / `Positions: 1 more`, `Operator panels: 1 missing`, `Camera addresses: 1 changed`, `Switcher address: 1 changed`, then the “becomes the newest backup, nothing is deleted” line and Cancel / Restore. Replaces the old shot, which said `It matches what is on this machine already.` |
| Name dialog, good default | `screenshots/name-dialog-default.png` | **Pass (recaptured).** Dialog `Name this machine`, the “whatever you would actually say out loud” copy, Name field pre-filled with the host suggestion `Daniels-MacBook-Pro`, Cancel / Save. Pill reads `Not backed up`, correct for a fresh unnamed launch. |
| Name dialog, rejected | `screenshots/name-dialog-rejected.png` | **Partial pass (recaptured).** The snackbar is now in frame and legible: `That name is already in use, or is not specific enough. Try something that names this machine.` The dialog is **not** in the same frame — see below. |

### Why the rejected shot has no dialog in it

The spec asked for the name dialog *and* the snackbar together. That state does
not exist. `lib/widgets/backup/device_name_dialog.dart:27-38` pops the dialog
first (`showDialog` returns the typed text), sanitises the result, and only
then calls `showSnackBar`. By the time the message can appear the field is
already gone. Reopening the dialog on top of a live snackbar would produce the
requested picture but would misrepresent what Save actually does, so the honest
post-Save frame is what is committed. Changing the dialog to keep the field
open would be a product change, not a screenshot fix.

The snackbar sits under the Settings modal barrier, which dims it. That is the
real app appearance, not a capture artefact.

## Limitations

- No real backup target ships until Phase 4. Every green or conflict screenshot
  uses the in-memory mock, which evaporates on quit.
- “Decide later” is recorded but suppresses log rows, not a prompt that cannot
  fire (deviation D6). Not screenshotted.
- Device-name uniqueness only sees revisions the store returns, so two
  machines named offline can still collide until their first push.
- Comparison-failed dialog was not captured, and no engine code was added to
  fake one — the mock fetch always succeeds.
- Rejected-name shot cannot show the dialog and the snackbar together, because
  the dialog closes before the message fires. Documented above.
- Mock timestamps read `31 Dec, 7:00 PM` (mock clock), not wall time. Both
  history rows carry the same stamp, so “newest” is row order, not a visible
  time difference.
- The host suggestion in `name-dialog-default.png` is this Mac's hostname. On a
  machine whose hostname is on the worthless list in
  `lib/services/backup/device_label.dart` (`localhost`, `MacBook Pro`,
  `Mac mini`, …) the field would be blank instead. Only the suggesting branch
  is captured.

Do not push or merge until Daniel says so.
