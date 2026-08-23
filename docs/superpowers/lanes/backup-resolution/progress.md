# Lane 3b — Backup Resolution Progress

Date: 2026-08-23
Branch: `lane/backup-resolution`
Plan: `docs/superpowers/plans/2026-08-21-status-surface.md`
Code HEAD at screenshot commit: `f6067b5`
Screenshot commit: `b08cccf` (agy), inventory corrected after controller looked at every PNG.

Captured from the real macOS app (`Production Control`) with
`tools/mock_server/drive_macos_app.sh` against
`--dart-define=BACKUP_MOCK=true --dart-define=BACKUP_SCENARIO=conflict`.
Live mode. Not connected. Agy also tightened `pin()` in the drive script
(`AXRaise` + `frontmost`) so the window actually comes to the front.

## Screenshot evidence

Controller opened every file. Claims below are from the pixels, not from agy's write-up.

| Planned | File | What it actually shows |
|---|---|---|
| Needs-review pill | `screenshots/conflict-pill.png` | **Pass.** Orange `Needs review`, help icon, Production Control, Live mode. |
| Popover with Review | `screenshots/conflict-popover-review.png` | **Pass.** Pinned amber row `Another machine saved a different configuration.` / `conflict`. Header action **Review**, not Retry now. (Header also says “This configuration has never been backed up.” — last-success line, not a failed capture.) |
| Conflict dialog + real diff | `screenshots/conflict-dialog-diff.png` | **Pass.** Title `Two machines have different settings`. `Daniel's iPad saved a copy 31 Dec, 7:00 PM.` Lines: `Positions: 1 more`, `Operator panels: 1 missing`, `Camera addresses: 1 changed`, `Switcher address: 1 changed`. Buttons Decide later / Use their copy / Keep mine. |
| Comparison-failed | *(omitted)* | In-memory mock serves the body; no scenario for a failed download. Not faked. |
| Backup history list | `screenshots/history-list.png` | **Wrong file.** This is **Settings**, not the history dialog. Useful as a wiring shot: Configure → Name this machine, Data → Backup History. The actual history rows are only visible *behind* `restore-confirm.png`. |
| Restore confirm | `screenshots/restore-confirm.png` | **Pass on the dialog, weak on the case.** Title `Restore this version?`, Cancel / Restore, copy that it becomes the newest backup. Opened on **This machine** — `It matches what is on this machine already.` Not an older differing revision. Background shows Backup history with `Daniel's iPad` / Re-apply. |
| Name dialog, good default | `screenshots/name-dialog-default.png` | **Fail.** Disconnected main screen, no dialog. Duplicate of the pill page. |
| Name dialog, rejected | `screenshots/name-dialog-rejected.png` | **Partial.** Dialog open, field is `localhost`, Cancel / Save. Spec asked for the snackbar *after* Save (`That name is already in use, or is not specific enough.`). No snackbar in the frame. |

Agy’s original inventory said `history-list.png` listed revisions and
`name-dialog-default.png` showed a pre-filled `This machine`. Those sentences
do not match the files.

## Limitations

- No real backup target ships until Phase 4. Every green or conflict screenshot
  uses the in-memory mock, which evaporates on quit.
- “Decide later” is recorded but suppresses log rows, not a prompt that cannot
  fire (deviation D6). Not screenshotted.
- Device-name uniqueness only sees revisions the store returns, so two
  machines named offline can still collide until their first push.
- Comparison-failed dialog was not captured (mock fetch succeeds).
- `name-dialog-default.png` does not show the name dialog. Recapture needed.
- `history-list.png` is Settings, not the history list. Recapture needed, or
  treat `restore-confirm.png` as the only history evidence.
- Rejected-name snackbar was not captured (shot is pre-Save).
- Mock timestamps read `31 Dec, 7:00 PM` (mock clock), not wall time.

## Remaining capture (if Daniel wants a second pass)

1. `history-list.png` — the Backup history dialog itself (two rows, Restore on the older).
2. `name-dialog-default.png` — Name this machine with the host suggestion or a blank field. Second launch *without* `BACKUP_SCENARIO=conflict`, prefs wiped.
3. `name-dialog-rejected.png` *after* Save, with the snackbar visible.
4. Optional: restore confirm on a revision that actually differs.

Do not push or merge until Daniel says so.
