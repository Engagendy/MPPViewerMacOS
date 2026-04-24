# Performance Guide

## Purpose

This repository uses Apple performance guidance as an engineering standard, not as optional cleanup work.

Every feature change should preserve:

- responsive discrete interactions
- smooth continuous interactions
- narrow SwiftUI update scopes
- measurable before/after verification

This guide is the standing rulebook for new work in this repo.

## Apple Sources

Core Apple references this guide is based on:

- [Improving Your App's Performance](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance)
- [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)
- [Performance analysis](https://developer.apple.com/documentation/swiftui/performance-analysis)
- [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
- [Understanding user interface responsiveness](https://developer.apple.com/documentation/xcode/understanding-user-interface-responsiveness)
- [Understanding hitches in your app](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app)
- [Diagnosing performance issues early](https://developer.apple.com/documentation/xcode/diagnosing-performance-issues-early)
- [Improving your app's rendering efficiency](https://developer.apple.com/documentation/xcode/improving-your-app-s-rendering-efficiency)
- [Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time)
- [Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)
- [Reducing terminations in your app](https://developer.apple.com/documentation/xcode/reduce-terminations-in-your-app)
- [MetricKit](https://developer.apple.com/documentation/metrickit/)
- [Logging](https://developer.apple.com/documentation/os/logging/)
- [XCTest](https://developer.apple.com/documentation/xctest/)

## App Standards

### Responsiveness targets

- Keep synchronous main-thread work for discrete interactions well under `100 ms`.
- Treat continuous interactions like drag, scroll, resize, and timeline movement as frame-budget work.
- Prefer staying below `5 ms` of app-side main-thread work during continuous interactions where possible.

### SwiftUI standards

- Keep view bodies cheap.
- Do not perform heavy filtering, sorting, decoding, formatting, or aggregation directly in `body`-adjacent computed properties unless the result is cached and refreshed only when real inputs change.
- Prefer narrow state propagation over broad root-view invalidation.
- Split large screens into smaller subviews when a local interaction should not refresh the whole feature surface.
- Scope `GeometryReader` and similar layout readers to the smallest area that truly needs layout feedback.
- Avoid unnecessary implicit animation in editing-heavy screens.

### Data and background work

- Move preparation work off the main thread unless it is strictly UI-only.
- Avoid synchronous file, network, and serialization work on the main thread.
- Batch persistence work where possible instead of writing repeatedly.

### Rendering and updates

- Do not redraw large surfaces because of selection-only state when the content itself is unchanged.
- Avoid repeated layout and drawing work for hidden or non-visible content.
- Prefer stable cached derived data for task lists, lane groupings, timeline ranges, and report summaries.

## Change Checklist

Every meaningful UI change should pass this checklist before merge:

1. Define the hot interaction.
   Example: planner cell focus, agile drag/drop, gantt resize, status task selection.

2. Identify the expected performance class.
   - discrete interaction
   - continuous interaction
   - background work
   - launch
   - persistence / I/O

3. Check update scope.
   - Which `@State`, `@Binding`, or observable values change?
   - Which views recompute because of that change?
   - Can the dependency be narrowed?

4. Check derived work.
   - Any `filter`, `sorted`, `reduce`, grouping, decoding, or formatter creation on the view path?
   - Can it be cached or precomputed?

5. Check layout coupling.
   - Does `GeometryReader`, `ScrollViewReader`, or custom layout code observe more than necessary?

6. Check persistence and background work.
   - Any file writes, JSON/plist writes, or long calculations on the main thread?

7. Measure before and after.
   - SwiftUI instrument for view update cost/frequency
   - Time Profiler or Animation Hitches as needed
   - Build or test verification for regressions

## Required Profiling Passes

Use the right tool for the suspected problem:

- SwiftUI update cost/frequency:
  - SwiftUI instrument
- main-thread hangs:
  - Time Profiler
  - Hangs or responsiveness tools where applicable
- motion issues:
  - Animation Hitches
- launch:
  - App Launch template
- disk writes:
  - File Activity
- energy:
  - Energy instruments / Organizer metrics

## Repo-Specific Hot Paths

Treat these screens as first-class performance surfaces:

- `Plan Builder`
- `Agile Board`
- `Gantt Chart`
- `Status Center`
- `Dashboard`
- `Workload`
- `Schedule`

These surfaces must not regress due to unrelated changes.

## Code Review Rules

Flag a change for performance review if it introduces any of the following:

- new root-level computed collections on large models
- `filter` or `sorted` chains inside views that run on every local state change
- repeated formatter creation on hot paths
- selection or focus state living too high in the tree
- heavy `onChange` work with broad triggers
- broad `@Binding` invalidation on large editors without cached derivations
- extra animation around dense editing workflows

## Regression Prevention

When a performance issue is fixed:

- document the hot interaction in the remediation plan
- keep the derived-data or state-isolation improvement in place
- add measurement notes or tests where practical
- do not remove instrumentation or caching without replacement evidence

## Working Rule

No feature is complete if it makes the app feel less native, less immediate, or less stable under interaction.
