# MPP Viewer 2.4.0 — App Store "What's New"

## Suggested App Store Connect text

More columns in the task list, a better date picker everywhere, and smoother Gantt editing.

NEW
• Task list columns: show Notes, Resources, Actual Start/Finish, Cost, Baseline Cost, Actual Cost, and Priority — plus your custom fields
• Drag column headers to reorder task list columns; your arrangement is remembered
• New date control across the app: type a date in many formats, or pick from a month calendar with direct month and year menus and a Today shortcut
• Live day-delta badge while moving or resizing Gantt bars (e.g. "+3d", "Finish +5d")

IMPROVED
• Gantt bars follow the cursor smoothly while dragging and snap to whole days on release
• In Gantt edit mode a click just selects — task details open with double-click, so the details card never blocks dragging or resizing
• Task CSV and Excel exports now include Notes
• Tab moves from a date field straight to the next input; Up/Down arrows step the date by a day

FIXED
• CSV task import no longer fails on files saved by Excel or Windows tools (CRLF line endings imported zero tasks)
• Exported task CSV columns were misaligned after "Actual Cost" (missing Critical value)
• The task filter date range no longer shows placeholder years 1 and 4001

## Notes

- Minimum system version is now macOS 14.4 (was 14.0), required for the new
  reorderable and optional table columns.
