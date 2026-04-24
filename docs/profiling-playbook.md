# Profiling Playbook

## Purpose

Use this playbook whenever a change touches a heavy interaction surface:

- Plan Builder
- Agile Board
- Gantt Chart
- Status Center
- Dashboard

This is the operational companion to [performance-guide.md](performance-guide.md).

## Standard Trace Set

### 1. Launch

Use:

- App Launch template

### 2. SwiftUI update analysis

Use:

- SwiftUI instrument

Focus:

- Long View Body Updates
- Update Groups
- cause-and-effect graph

### 3. Continuous interaction hitch analysis

Use:

- Animation Hitches
- Time Profiler where needed

Focus:

- Agile Board drag/drop
- Gantt move/resize/link
- scrolling and resize-heavy workflows

### 4. Main-thread discipline

Use:

- Thread Performance Checker
- Time Profiler

## Feature Scenarios

### Agile Board

- select a card repeatedly
- drag a card across buckets
- reorder buckets
- show/hide inspector

### Plan Builder

- move between grid cells
- select rows
- add/delete/indent/outdent tasks
- edit date and numeric fields

### Gantt

- select tasks
- drag bars
- resize bars
- create and remove links
- switch view/edit mode

### Status Center

- switch filters
- search tasks
- select tasks repeatedly
- edit actual cost and dates

### Dashboard

- open screen
- switch filters and snapshots
- expand customization sections

## Before/After Rule

For any meaningful performance fix:

1. record the slow behavior
2. make the change
3. record the same interaction again
4. compare:
   - update counts
   - long view body updates
   - hitch count
   - main-thread duration

## Repo Instrumentation

This repo uses `PerformanceMonitor` for lightweight signpost-style interaction markers.

Prefer adding markers to:

- selection handlers
- drag/drop commit points
- costly editor refresh paths
- reschedule / recompute entry points
