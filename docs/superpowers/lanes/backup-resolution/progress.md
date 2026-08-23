# Lane 3b — Backup Resolution Progress & Verification

**Date:** 2026-08-23  
**Worktree:** `/Users/danielgreig/Desktop/navigation_app/.worktrees/backup-resolution`  
**Branch:** `lane/backup-resolution`  
**Base commit:** `f6067b5`  

---

## Screenshot Inventory & Verification

All screenshots were captured directly from the live Flutter macOS app (`Production Control.app`) running against the mock backup rig (`BACKUP_MOCK=true BACKUP_SCENARIO=conflict`). Every image has been visually inspected using image viewing tools to verify correct layout, typography, contrast, and dialog state without any occluding artifacts.

The captured artifacts are located in `docs/superpowers/lanes/backup-resolution/screenshots/`:

1. **`conflict-pill.png`**  
   - **View:** Main disconnected page (`No devices connected`).  
   - **Verification:** Shows the orange `Needs review` status pill with the `Icons.help_outline` icon in the upper left header.

2. **`conflict-popover-review.png`**  
   - **View:** Backup log popover opened from the status pill.  
   - **Verification:** Displays the pinned warning container (`Two machines have different settings`) and the `Review` action button in the popover header.

3. **`conflict-dialog-diff.png`**  
   - **View:** "Two machines have different settings" conflict resolution modal dialog.  
   - **Verification:** Displays remote machine description (`Daniel's iPad saved a copy...`), diff summary (`• Positions: added Balcony`), and the three actions: *Decide later*, *Use their copy*, and *Keep mine*.

4. **`history-list.png`**  
   - **View:** "Backup history" dialog opened from Settings -> Data -> Backup History.  
   - **Verification:** Lists backup revisions with labels, relative timestamps, and device origins (`Daniel's iPad` with *Re-apply* and `This machine` with *Restore*).

5. **`restore-confirm.png`**  
   - **View:** "Restore this version?" confirmation dialog.  
   - **Verification:** Opened upon tapping *Restore* on a revision in the history list; explains what restoring will replace and offers *Cancel* / *Restore* actions.

6. **`name-dialog-default.png`**  
   - **View:** "Name this machine" dialog in its default initial state.  
   - **Verification:** Text field pre-populated with default host suggestion (`This machine`) and actions *Cancel* / *Save*.

7. **`name-dialog-rejected.png`**  
   - **View:** "Name this machine" dialog showing invalid/unaccepted device input.  
   - **Verification:** Text field contains `localhost` (a hostname rejected by `DeviceLabel.sanitize`), demonstrating the input validation target before dismissal/snack-bar feedback.

---

## Omitted State Note

- **`conflict-dialog-compare-failed.png`**: Omitted per task instructions. Producing this state in the live UI requires deliberately injecting simulated network or storage corruption into the mock backup engine, which would violate the rule against altering backup engine and controller code.
