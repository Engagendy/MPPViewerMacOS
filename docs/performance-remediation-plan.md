# Performance Remediation Plan

## Goal

Bring the app closer to native macOS responsiveness by following Apple guidance across:

- SwiftUI update cost
- update frequency
- main-thread discipline
- launch and I/O hygiene
- measurable regression prevention

## Current Gap Summary

### Architecture

- Large stateful SwiftUI surfaces still exist:
  - `ContentView.swift`
  - `DashboardView.swift`
  - `PlanEditorView.swift`
  - `GanttChartView.swift`
- Broad `@Binding` and root-level derived properties cause wider invalidation than needed.

### Interaction smoothness

- Selection and focus changes still trigger more work than the user expects on editing-heavy screens.
- Drag, resize, and board interactions need tighter update scope and profiling.

### Measurement discipline

- Profiling has been done, but not yet as a stable per-feature workflow.
- There is no standing repo guide or repeatable remediation checklist.

### Regression prevention

- There is no explicit performance test or benchmark pack guarding future changes.

## Compliance Matrix

| Area | Apple expectation | Current status | Target |
|---|---|---|---|
| SwiftUI body cost | Keep bodies fast | Partial | High |
| Update frequency | Reduce unnecessary updates | Partial | High |
| Narrow dependencies | Observe only what matters | Low-Partial | High |
| Main-thread discipline | Keep non-UI work off main thread | Partial | High |
| Layout coupling | Scope layout readers carefully | Partial | High |
| Interaction profiling | Measure real hot interactions | Partial | High |
| Launch discipline | Measure and reduce launch cost | Partial | Medium-High |
| Disk write awareness | Measure and avoid excess writes | Low | Medium |
| Regression prevention | Keep repeatable perf checks | Low | High |

## Remediation Phases

### Phase 1: Standards and first hot-path cleanup

Status: completed

- Add the repo-local performance guide.
- Cache heavy derived data in `Status Center`.
- Cache and narrow Agile Board derivations.
- Reduce selection-only recomputation on hot surfaces.
- Keep build verification green.

### Phase 2: Structural SwiftUI isolation

Status: completed

- Split `AgileBoardView` into smaller subviews with narrower inputs.
- Split `StatusCenterView` into smaller subviews with cached models.
- Move `DashboardView` persisted decoding and sorting out of hot view properties.
- Reduce broad state invalidation in `PlanEditorView`.

### Phase 3: Measurement and traceability

Status: completed

- Add signpost-based instrumentation for:
  - planner row selection
  - planner field focus
  - agile card selection
  - agile drag/drop
  - gantt selection
  - gantt resize / move
- status center task selection
- Document the profiling playbook in the repo.

### Phase 4: Regression protection

Status: completed

- Add targeted performance checks or repeatable measurement scripts.
- Add feature-level profiling notes for the heavy screens.
- Keep a before/after measurement habit for risky UI changes.

## Completed Implementation

1. `Status Center`
   - cached derived task sets, metrics, assignment maps, radar summaries, and snapshots
   - selection and status-update handlers now use lightweight instrumentation markers

2. `Agile Board`
   - cached board columns, lane grouping, sprint name lookups, and health counts
   - drag/drop, selection, and lane changes now emit interaction markers
   - board interactions no longer rebuild lane groupings from scratch on selection-only changes

3. `Dashboard`
   - persisted decode/sort work moved out of hot computed properties
   - repeated currency formatter creation removed from summary formatting

4. `Plan Builder`
   - analysis refresh remains debounced
   - reschedule and import-issue selection now emit interaction markers for tracing

5. `Gantt`
   - derived task/range caches remain in place
   - selection, linking, dependency removal, move, and resize now emit interaction markers

## Verification Standard

For each phase:

- verify local build with `xcodebuild`
- compare before/after interaction behavior
- update this document if a new hotspot is identified

Repo artifacts supporting this workflow:

- `docs/performance-guide.md`
- `docs/profiling-playbook.md`
- `scripts/profile_mppviewer.sh`

## Done Criteria

This plan is only complete when:

- the heaviest editing screens feel immediate during normal use
- major selection/focus interactions no longer feel delayed
- performance review becomes part of normal feature work
- changes are backed by measurement, not guesswork

## Remaining Future Work

This remediation set establishes the standard and closes the major code-level gaps. Future performance work should now be evidence-driven and scenario-specific, not broad architectural guessing.
