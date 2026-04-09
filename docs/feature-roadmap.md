# MPP Viewer Feature Roadmap

## Goal

Turn the app from a capable `.mpp` viewer into a more trustworthy planning and review tool for project managers, delivery leads, and stakeholders.

## Guiding Principles

- Prefer features that increase trust in imported project data.
- Make planning problems obvious before adding heavy editing workflows.
- Keep the app useful for both detailed planners and executive reviewers.
- Avoid inventing project semantics when the source file does not explicitly support them.

## Quick Wins

### 1. Task Source-Data Inspector

Status: started

Purpose:
- Show the raw MS Project / MPXJ flags behind each task.
- Explain why the app classifies a task as milestone, summary, overdue, or normal.

Value:
- Reduces confusion when imported data contains inconsistent flags.
- Helps users trust or challenge what the app is showing.

Next steps:
- Add more raw fields such as raw start/finish strings, duration seconds, parent ID, and outline number.
- Add a one-line “why this is shown” summary in milestone and timeline views.

### 2. Project Validation Report

Purpose:
- Detect suspicious data and planning issues early.

Status: started

Checks:
- Summary task also marked as milestone
- Milestone with non-zero duration
- Missing dates
- Tasks with finish before start
- Dependency targets not found
- Progress inconsistencies
- Inactive tasks with assignments

Value:
- Gives immediate practical feedback after import.
- Makes the app more useful as a quality gate.

Current implementation:
- Sidebar validation view
- Severity filters
- Click-through navigation from an issue to the related task
- CSV export

### 3. Saved Filters and Saved Views

Purpose:
- Let users preserve working contexts across sessions.

Status: started

Examples:
- Critical overdue tasks
- Upcoming milestones
- Tasks for a specific resource
- Custom column layouts

Value:
- Strong usability upgrade for repeated analysis work.

Current implementation:
- Persisted task view preset selection
- Quick presets for overdue critical, upcoming milestones, in-progress, flagged review, and completed work

## Medium Features

### 4. Executive Health Report

Purpose:
- Generate a concise summary of project health.

Status: started

Output ideas:
- Upcoming milestones
- Delayed critical tasks
- Resource hotspots
- Variance against baseline
- High-risk workstreams

Formats:
- On-screen summary
- PDF export
- Markdown report

Current implementation:
- Markdown executive summary export from dashboard
- Includes headline KPIs, validation snapshot, and upcoming milestones
- Dedicated Executive Mode screen for presentation-oriented review
- Baseline analysis summary for tracked tasks, slips, and largest variance
- Sidebar reordered into grouped overview, planning, and analysis sections
- Executive view now surfaces a live baseline variance alert (green/red badges) and quick actions for both summary and review-pack exports.

### 5. Dependency and Constraint Diagnostics

Purpose:
- Expose schedule risks more clearly than a standard task table.

Status: started

Examples:
- Dangling dependencies
- Excessive lag
- Constraint-heavy tasks
- Critical path bottlenecks
- Late predecessor chains

Current implementation:
- Dedicated diagnostics view
- Explicit constraint detection
- Constraint date drift and missing-date checks
- Long lag/lead dependency detection
- FS predecessor overlap detection
- Dependency-heavy task detection
- Successor fan-out and critical-chain hub signals
- Isolated critical task and blocked-start signals
- Task inspector relationship analysis showing blockers, downstream impact, and network position
- Compact dependency map for the selected task
- Clickable predecessor and successor nodes that refocus the inspector
- Breadcrumb trail for dependency navigation history
- Depth selector for expanding the dependency map to multi-hop relationships
Next steps:
- Anchor the dependency explorer on a vertical spine with tighter spacing and safe margins so deep chains stay readable.
- Highlight the inspected node, expose the zoom/reset controls, and document the breadcrumb trail for focused navigation.
- Surface the dependency explorer as the entry point for the presentation/executive mode refresh and baseline variance alerts.
### 6. Task Relationship Inspector (Enhanced)

Purpose:
- Summarize how a selected task joins the broader network so reviewers can immediately spot blockers, drivers, and isolated risks.

Status: started

Next steps:
- Show interactive badges that expose predecessor/successor counts, blocking predecessors, and driving successors, letting the reviewer jump into the next task with one tap.
- Highlight the task relationship section beside the dependency map so the inspector stays focused on the currently selected node.
- Keep the breadcrumb/history trail and auto-depth toggles in sync with the relationship summary so deeper analyses stay tidy.

### 7. Resource Allocation Diagnostics

Purpose:
- Upgrade workload from visualization to diagnosis.

Status: started

Examples:
- Exact over-allocation periods
- Which assignments cause overload
- Which tasks can be moved to reduce pressure

Current implementation:
- Dedicated resource risks view
- Assignment-vs-max-units checks
- Peak overlap detection by day
- Peak overlapping task summary
- Sustained overload window detection
- Date-range details on overloaded assignments
- Resource drill-down inspector with per-resource assignment list
- Daily load timeline with visible overload bars
- Direct navigation from a resource assignment back to the related task
- Severity-aware badges highlight which signals are errors versus warnings.
- Weekly overload snapshots surface the peak days and the assignments driving the bad load.

### 8. Baseline Variance Intelligence

Purpose:
- Help reviewers see plan vs actual throughout every timeline and inspector.

Status: started

Current implementation:
- Dashboard baseline alerts, KPI cards, and summary contexts make slipped tasks very visible.
- Gantt and timeline views now draw baseline overlays, markers, and delta badges beside slipped bars and ribbons.
- The task table and relationship inspector include inline delta badges so reviewers can read plan variance without leaving the inspector.

Next steps:
- Surface live alerts (badges and tooltip) when tasks exceed slack/variance thresholds, both in dashboard cards and in the critical path / float inspections.
- Tie baseline variance into the dependency explorer so chains light up as soon as a predecessor slips.
- Surface baseline variance context inside the resource drill-down so overloaded assignments can be compared with plan ranges.

## Larger Features

### 9. Portfolio Mode

Purpose:
- Open multiple projects and compare them together.

Examples:
- Shared resources across plans
- Milestones across releases
- Cross-project risk summary

### 10. Snapshot and Review Mode

Purpose:
- Save a point-in-time analytical snapshot of a project.

Examples:
- Save flagged tasks
- Save notes and comments
- Reopen previous review sessions

### 11. Collaboration Export

Purpose:
- Make findings easy to share outside the app.

Examples:
- “Review pack” PDF
- CSV of issues
- Markdown summary for email or Teams

### 12. Scenario Analysis

Purpose:
- Let reviewers test planning changes before editing the source file.

Status: started

Examples:
- “What happens if this task slips 5 days?”
- “What changes if I add one more engineer?”
- “Which downstream milestones move if this activity starts late?”

Current implementation:
- Task inspector now includes a first-pass scenario analysis panel for single-task slips.
- Reviewers can simulate a delay in days and see projected source dates, downstream task impacts, milestone/critical counts, and project-finish movement.
- The current simulation uses recorded successor links and calendar-day shifts only, giving a fast dependency-based estimate without editing the source file.
- Resource inspector now includes a capacity scenario panel that models added team members as extra weekly capacity and shows peak-allocation relief, overloaded-week reduction, and recovered excess hours.

Phases:
- Phase 1: task slip simulator using dependency propagation and baseline comparison
- Phase 2: resource capacity what-if overlays for overloaded teams
- Phase 3: compare scenarios side by side and export impact summaries

### 13. Saved Reporting Dashboards

Purpose:
- Give each audience a fast path to the views and metrics they care about.

Status: started

Audiences:
- PM
- Executive
- Scheduler
- Resource manager

Current implementation:
- Dashboard now supports a persisted audience preset for Project Manager, Executive, Scheduler, and Resource Manager.
- Each preset swaps in curated KPI cards, explains its review focus, recommends the right exports, and provides one-click navigation to the most relevant analysis views.
- Each audience preset now also keeps its own saved dashboard configuration, including widget visibility, task-focus filter, and milestone count.
- The current audience dashboard can now be exported as a shareable markdown snapshot so recurring reviews can carry the preset, layout, KPIs, and visible sections outside the app.
- Saved audience dashboards can now also be captured as local in-app snapshots, reopened later, reapplied to the live dashboard, exported again, or deleted.

Phases:
- Phase 1: built-in dashboard presets with curated KPIs and exports
- Phase 2: saved user dashboards with persisted widget layout and filters
- Phase 3: shareable dashboard exports for recurring reviews

### 14. Issue Annotation Workflow

Purpose:
- Turn ad-hoc review notes into a real issue-tracking layer for project reviews.

Status: started

Current implementation:
- Task inspector now supports local issue annotations with review status, follow-up flag, note body, and update timestamp.
- Review-pack export now summarizes issue annotations instead of plain note blobs.
- Dashboard and executive flows can export unresolved items as a focused open-issues report.
- Task table now shows annotation badges inline and supports filters for annotated work, open issues, and follow-up items.
- Open issues can now be exported to CSV for spreadsheet-based review and distribution.

Next steps:
- Add owner, due date, and severity so the review workflow can be triaged.

### 15. Smarter Diffing

Purpose:
- Show the impact of project changes, not only field-level edits.

Status: started

Examples:
- Finish-date movement summary
- Critical-path entry and exit changes
- Net cost delta and highest-impact cost changes
- Added or removed dependency chains

Current implementation:
- Compare view now surfaces impact summary cards for project finish movement, total cost delta, critical-task churn, and the largest task finish slip.
- Existing table-level field diffing remains available below the summary so reviewers can move from impact to detail without switching modes.
- Diff rows now expose task-level finish delta, cost delta, and criticality-entry/exit signals as dedicated impact columns.

Phases:
- Phase 1: impact summary cards above the diff table
- Phase 2: schedule, cost, and criticality deltas per task
- Phase 3: change clustering by workstream, resource, or milestone impact

## Recommended Build Order

1. Expand the task source-data inspector
2. Add a validation report view
3. Add saved filters and saved column presets
4. Add executive summary export
5. Add dependency diagnostics
6. Add deeper resource diagnostics
7. Expand issue annotations into task-table filters and triage
8. Add smarter diff impact summaries
9. Add scenario analysis for task slippage
10. Add saved dashboards by audience

## Recently Implemented

- Baseline analysis summary in Dashboard
- Relationship inspector in the task detail panel
- Milestone health reasoning with baseline and predecessor-aware risk signals
- Compact dependency visualization for the selected task
- Interactive dependency navigation with breadcrumbs and depth control
- Resource drill-down with assignment and load timeline inspection
- Grouped sidebar ordering
- Gantt/timeline/critical-path views now surface baseline slip badges and overlays so the worst deltas are obvious without opening inspectors.
- Dependency explorer now renders vertically with highlight/zoom controls, breadcrumbs, and synced inspection.
- BaselineVariance helpers expose finish/start deltas so the task table can render delta badges.

## Immediate roadmap

1. Presentation/executive mode polish (focus messaging, live baseline alerts, review-pack export)
2. Baseline visuals across the Gantt/timeline plus float/critical-path signaling
3. Task relationship inspector completion (resource/constraint drill-down, dependency-focus navigation)
4. Issue annotation workflow completion (task-table badges, triage filters, unresolved CSV export)
5. Smarter diffing v1 (impact summary cards for finish, cost, and critical-path changes)
6. Scenario analysis v1 (single-task slip simulation with downstream impact summary)
7. Saved reporting dashboards v1 (PM, executive, scheduler, resource manager presets)

## Notes on Deliverables

- Microsoft Project has a built-in milestone concept, but not a reliable built-in deliverable type.
- The app should avoid inferring deliverables unless the source file explicitly marks them through custom fields or a deliberate project convention.
- For now, milestone handling should stay strict and transparent.
