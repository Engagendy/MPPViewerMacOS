# Planroom — Manual QA Checklist

Fast pass to verify every feature/view. Start by creating a fresh plan:
**File → New**, then in **Plan Builder** add a couple of phases with tasks
(or open `docs/sample-plans/aurora-commerce-launch.mppplan`).

Legend: ☐ = to test.

## Core views load (click each sidebar item)
- ☐ Portfolio, Dashboard, Executive Mode, Summary
- ☐ Plan Builder, Agile Board, Status Center
- ☐ Tasks, Milestones, Gantt Chart, Schedule, Timeline, Resources, Calendar
- ☐ Validation, Diagnostics, Dependency Explorer, Resource Risks, Critical Path, Earned Value, Workload, Compare, Guide & Help
  *Expected:* each view renders with the plan's data, no blank pane.

## Command palette & modes
- ☐ **⌘K** → type a view name (e.g. "gantt") → Enter jumps there
- ☐ **⌘K** → type a task name/WBS/ID → Enter opens Tasks and scrolls to it
- ☐ **⇧⌘F** → Presentation Mode (sidebar hides, fullscreen); Exit pill or ⇧⌘F returns
- ☐ Focus-mode toolbar button hides/shows the sidebar

## Tasks view
- ☐ **Columns** button → toggle Notes / Actual Start / Costs / Priority / Resources / custom fields
- ☐ Drag a column header to reorder; arrangement persists after relaunch
- ☐ Hover a long name → full name tooltip; select a task → detail pane (no overflow, right margin present)
- ☐ Double-click the inspector divider → resets width
- ☐ Filters (Critical, Milestones, Flagged, date range in "More"), Group by, Preset

## Plan Builder
- ☐ Add task/subtask; Indent/Outdent; **Move Up/Down across phase boundaries**
- ☐ Grid **Columns** picker: hide built-ins; show Notes/Priority/Fixed Cost + custom fields; edit inline
- ☐ Inspector **Custom Fields**: add a field (applies to all tasks), fill values, remove (confirm dialog)
- ☐ Inspector **Gantt Bar Color** picker + Reset; date fields (type + calendar popover, month/year menus)
- ☐ Double-click the details divider → resets width

## Gantt (Edit mode)
- ☐ Drag a bar horizontally → moves dates (haptic tick on day snaps); resize edges
- ☐ Drag a bar vertically → reorders; drag a **phase** bar → moves subtree
- ☐ Right-click bar/phase → **Bar Color** (Timeline reflects it), **Focus on This Phase**
- ☐ **Levels** menu → phases-only / down to level N
- ☐ ⌘-click several bars → arrow keys move all; right-click → Mark Complete/Not Started, Assign/Unassign Resource, bulk color
- ☐ Single-click only selects (no details modal); double-click opens details
- ☐ Export menu → **PDF** and **SVG** (open the SVG in a browser); **Print** (opens panel, non-blank pages)
- ☐ Month labels at the timeline start don't overlap

## Import / Export
- ☐ Import the CSV (`MD_Tasks_Import.csv`, CRLF) → all rows import
- ☐ Export **Excel** (.xlsx) from Tasks → opens cleanly in Excel/Numbers, no format warning
- ☐ Export a template (.xlsx), edit, re-import → round-trips
- ☐ Export **PDF** from Tasks → long names wrap, not truncated

## Persistence
- ☐ Set bar colors / custom fields / column layout → save, reopen → all retained
- ☐ Cmd+Z reverts moves, colors, batch ops, field add/remove
