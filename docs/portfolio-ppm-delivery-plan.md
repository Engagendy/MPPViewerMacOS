# Portfolio PPM Delivery Plan

## Objective

Turn the current single-project editor plus portfolio registry into a real portfolio and program management product without regressing the current SwiftData-backed editing flow.

## Delivery Rules

- Keep `NativeProjectPlan` as import/export/archive format, not the primary UI read model.
- Prefer direct SwiftData-backed portfolio entities for portfolio, board, status, and Gantt experiences.
- Add new persisted portfolio fields as migration-safe optional properties unless there is a clear backfill path.
- Every phase must leave the app buildable, open existing stores safely, and preserve `.mppplan` round-tripping.

## Baseline

Status: done

Already completed in the codebase:
- SwiftData portfolio store with recovery and workspace promotion flow.
- Portfolio registry screen with import, archive, delete, and open-in-workspace actions.
- Direct persisted entities for plans, tasks, resources, assignments, calendars, sprints, workflows, and status snapshots.
- Read/write-capable Plan Builder, Agile Board, and Status Center path on top of the portfolio store foundation.

## Phase Tracker

### Phase 1: Portfolio Foundation v2

Status: done

Scope:
- Add real portfolio metadata to each plan: workspace, program, sponsor, stage, health, priority, objective, review date.
- Preserve that metadata in both SwiftData and `.mppplan`.
- Upgrade the portfolio workspace to filter, search, group, and edit these fields directly.
- Add portfolio rollups for program count, workspace count, and at-risk project count.

Acceptance criteria:
- Imported and blank plans can be assigned to a workspace and program.
- Portfolio metadata can be edited from the portfolio screen and persists after relaunch.
- Search and filters include the new portfolio metadata.
- `.mppplan` export/import preserves the new portfolio metadata.

### Phase 2: Executive Portfolio Dashboard

Status: done

Scope:
- Portfolio health summary with red/amber/green counts, budget and actual rollups, overdue project counts, and milestone slippage.
- Executive ranking of projects by cost variance, schedule pressure, and workload pressure.
- Attention feed for projects that need review this week.

Acceptance criteria:
- Executives can identify at-risk projects without opening each plan.
- Health signals derive from persisted project metrics rather than ad-hoc per-view scans.

### Phase 3: Cross-Project Resource Capacity

Status: done

Scope:
- Build a portfolio-wide resource directory.
- Show weekly capacity vs demand across all active projects.
- Surface over-allocation conflicts, double-booking, and overloaded teams.

Acceptance criteria:
- One resource can be seen across multiple projects with total demand rollup.
- Portfolio screen can answer who is overloaded, when, and by which plans.

### Phase 4: Governance and Intake

Status: done

Scope:
- Add strategic alignment, risk score, sponsor, approval state, lifecycle stage, and priority model.
- Add portfolio scoring and gating so projects can be proposed, approved, on hold, or cancelled.
- Add archive policy and review cadence metadata.

Acceptance criteria:
- PMO users can distinguish active delivery work from candidate or paused initiatives.
- Portfolio list can sort and filter by governance state and score.

### Phase 5: Program Roadmap and Cross-Project Dependencies

Status: done

Scope:
- Add program-level milestone roadmap.
- Add cross-project dependencies and dependency-risk surfacing.
- Add grouped timeline views for program and portfolio reviews.

Acceptance criteria:
- Projects can be grouped into programs and reviewed on one timeline.
- Cross-project blockers are visible from the portfolio layer.

### Phase 6: Portfolio Reviews and Reporting

Status: done

Scope:
- Portfolio snapshots by review date.
- Executive review pack export.
- Delta reporting between reviews.
- Saved portfolio views and recurring review presets.

Acceptance criteria:
- A PMO lead can reopen a previous portfolio review and compare it with the current one.
- Portfolio-level reports are exportable without manual screen stitching.

## Active Implementation Track

Current phase: Completed through Phase 6

Current checklist:
- [x] Audit the existing SwiftData portfolio foundation.
- [x] Write a tracked PPM delivery plan in the repo.
- [x] Extend the persisted plan schema with portfolio metadata.
- [x] Surface portfolio metadata in the portfolio dashboard.
- [x] Add portfolio grouping and risk rollups.
- [x] Add regression coverage for metadata persistence and grouping.
- [x] Build and verify the phase.
- [x] Define executive portfolio health ranking rules.
- [x] Add executive portfolio dashboard cards and attention feed.
- [x] Add cross-project milestone and variance rollups.
- [x] Build portfolio-wide resource rollups.
- [x] Add cross-project capacity vs demand views.
- [x] Surface double-booking and overload alerts.
- [x] Add governance scoring and approval-state model.
- [x] Add intake and lifecycle controls to the portfolio workspace.
- [x] Add archive/review cadence workflow and verification.
- [x] Add program-level roadmap rollups.
- [x] Add cross-project dependency registry and risk surfacing.
- [x] Add grouped program review timeline views and verification.
- [x] Add portfolio snapshots by review date.
- [x] Add executive review pack export.
- [x] Add delta reporting between portfolio reviews.
- [x] Add saved portfolio views and recurring review presets.

## Notes

- Do not build a second portfolio model beside SwiftData entities.
- Do not add mandatory persisted fields without a migration path.
- The initial PPM delivery roadmap is complete through Phase 6; next work should expand portfolio automation, approvals, and enterprise integrations rather than redoing the foundation.
