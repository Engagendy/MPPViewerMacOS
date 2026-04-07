<p align="center">
  <img src="MPPViewer/MPPViewer/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="MPP Viewer Icon">
</p>

<h1 align="center">MPP Viewer</h1>

<p align="center">
  <strong>A free, native macOS app for viewing Microsoft Project (.mpp) files</strong><br>
  No Windows. No MS Project license. No subscriptions.<br>
  Built with SwiftUI &bull; Powered by MPXJ
</p>

<p align="center">
  <a href="https://github.com/Engagendy/MPPViewerMacOS/releases"><img src="https://img.shields.io/github/v/release/Engagendy/MPPViewerMacOS?style=flat-square&label=download" alt="Release"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9-orange?style=flat-square" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License">
  <img src="https://img.shields.io/badge/price-free-brightgreen?style=flat-square" alt="Free">
</p>

---

## Screenshots

<p align="center">
  <img src="docs/screenshots/dashboard.png" width="800" alt="Dashboard — project health at a glance">
  <br><em>Dashboard — project health overview with KPIs, milestones, and schedule status</em>
</p>

<p align="center">
  <img src="docs/screenshots/tasks.png" width="800" alt="Task Table — hierarchical WBS with progress tracking">
  <br><em>Task Table — hierarchical WBS with duration, dates, progress bars, and predecessors</em>
</p>

<p align="center">
  <img src="docs/screenshots/gantt-chart.png" width="800" alt="Gantt Chart — interactive timeline with critical path">
  <br><em>Gantt Chart — zoomable timeline with critical path, baselines, milestones, and dependency arrows</em>
</p>

<p align="center">
  <img src="docs/screenshots/schedule.png" width="800" alt="Schedule View — split task list and Gantt">
  <br><em>Schedule View — MS Project-style split view with task list and Gantt side by side</em>
</p>

<p align="center">
  <img src="docs/screenshots/earned-value.png" width="800" alt="Earned Value Analysis — CPI, SPI, S-Curve">
  <br><em>Earned Value Analysis — CPI, SPI, EAC, VAC with S-Curve chart and task-level EVM table</em>
</p>

<p align="center">
  <img src="docs/screenshots/workload.png" width="800" alt="Resource Workload — allocation heatmap">
  <br><em>Resource Workload — weekly allocation view with over-allocation highlighting</em>
</p>

---

## Installation

### Homebrew (recommended)

```bash
brew tap Engagendy/tap
brew install --cask mpp-viewer
```

### Direct Download

1. Download the latest `.dmg` from [GitHub Releases](https://github.com/Engagendy/MPPViewerMacOS/releases)
2. Open the DMG and drag **MPP Viewer** to your Applications folder
3. On first launch, right-click the app → **Open** → **Open** (required for unsigned apps)

> The app bundles its own Java runtime and converter — no prerequisites needed.

### Gatekeeper Bypass

Since the app is not signed with an Apple Developer certificate, macOS will show an "unidentified developer" warning. To bypass this:

**Option A — Right-click Open (recommended):**
Right-click (or Control-click) the app → **Open** → click **Open** in the dialog.

**Option B — Remove quarantine attribute:**
```bash
xattr -cr /Applications/MPP\ Viewer.app
```

**Option C — System Settings:**
Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the MPP Viewer message.

---

## Features

### Dashboard
Instant overview of project health with KPI cards for average task progress, completed-task ratio, on-track status, critical tasks, total cost, CPI, and SPI. Includes task status breakdown, upcoming milestones, resource summary, schedule timeline with days remaining, baseline analysis, executive summary export, and review pack export.

### Executive Mode
Presentation-focused management view with headline health messaging, top risks, major milestones, and concise summary cards separated from the more operational dashboard.
It now surfaces the live baseline variance alert so slipped tasks pop in red, and the executive header includes both summary and review-pack exports so stakeholders can capture the latest insights with one click.

### Gantt Chart
Interactive timeline visualization with:
- Zoom controls — Fit All, Week, Month presets, and manual px/day adjustment
- Critical path toggle and baseline comparison overlay
- Today marker, dependency arrows (FS, SS, FF, SF), and weekend shading
- Color-coded task bars with progress fill
- Pinch-to-zoom gesture support
- PDF export — multi-page landscape output
- Baseline variance markers always visible plus a toggle for the full baseline overlay to compare plan vs actual at a glance
- Slipped tasks now display delta badges beside their bars so variance is visible without extra drilling.

### Schedule View
Microsoft Project-style split view with a task list on the left and Gantt timeline on the right. Both panes share collapse/expand state and scroll together.

### Task Table
Hierarchical task table with expand/collapse, sortable columns (ID, WBS, Name, Duration, Start, Finish, % Complete, Cost, Predecessors), detail inspector panel, resizable inspector sidebar, flag/bookmark tasks, and custom field columns. Filter by critical, milestones, flagged, baseline slip, linked tasks, status, resources, and richer text matching across IDs, notes, resources, and custom fields. Export to CSV or PDF.

The task inspector includes:
- source-data inspection for raw task flags and classification
- baseline details and variance
- relationship inspector for predecessors/successors and blockers
- Relationship badges now surface predecessor, successor, blocking, and driving counts that jump straight to the next task in the chain
- dependency map
- local persistent review notes
- baseline delta badges show finish/start slips (F+3d/S-1d) directly in the task list
- interactive dependency navigation with clickable predecessor/successor nodes, breadcrumb history, and depth control

### Milestones
Dedicated view for explicit project milestones with status badges, baseline variance, predecessor-aware health reasoning, and sortable columns.

### Validation
Project validation screen for suspicious source data and planning issues such as summary tasks marked as milestones, invalid dates, missing links, progress inconsistencies, and inactive tasks with assignments. Includes severity filters, CSV export, and task drill-down.

### Diagnostics
Dependency and constraint diagnostics for schedule-structure review, including explicit constraints, date drift, long lag/lead links, dependency-heavy tasks, successor fan-out, blocked-start signals, and critical-chain hubs.

- **Dependency Explorer** — immersive pan/zoom graph that stacks linked tasks vertically with consistent spacing, plus highlight/zoom controls, clickable nodes, a breadcrumb trail, and synced inspector detail.

### Resource Risks
Resource-focused diagnostics for over-allocation, assignment units above max capacity, overload windows, sustained overload periods, and overlapping task hotspots.

- Each row now renders a severity alert badge so errors, warnings, and info signals are instantly visible without opening a detail view.

### Earned Value Analysis
Full EVM dashboard with CPI, SPI, EAC, VAC indicators, an S-Curve chart plotting PV/EV/AC over time, and a task-level EVM breakdown table.

### Resources
Resource sheet showing all work, material, and cost resources with standard rates, max units, email, group, and assignment counts.

### Resource Drill-down
Resizable resource inspector with overview stats, daily load timeline highlighting overload days, assignment list, and clickable links that jump back to the task table for quick analysis.

- Weekly overload calendar shows each day’s allocation and highlights the assignments behind peak loads.

### Resource Workload
Calendar-aware weekly workload view per resource. Green bars for normal allocation, red for over-allocation. Uses project calendar working days and exception dates.

### Calendar
Visual calendar display with working/non-working day highlighting, exception days (holidays), and month navigation. Supports calendar inheritance (parent calendar chains).

### Timeline View
Executive-level summary showing only summary tasks and milestones as horizontal ribbons and diamond markers, with optional baseline overlays.
- Baseline slips also draw inline delta badges and planned-range outlines when the baseline toggle is enabled so timeline deviations are easy to scan.

### Critical Path
Dedicated critical-path and near-critical review screen showing driving tasks, float/slack where available from the source data, and direct navigation back into the task view.
- Baseline variance badges now accompany critical-path entries to surface the worst slips while reviewing dependencies.

### Compare (Diff Two Versions)
Open a second `.mpp` file to compare against the current project. Shows added, removed, and modified tasks with field-level change details.

### Additional
- **Project Summary** — metadata, schedule info, statistics, and file information
- **Search** — filter and navigate tasks by name, ID, WBS, notes, resources, and custom fields across all views
- **Saved Presets** — reusable task presets such as overdue critical, in progress, upcoming milestones, flagged review, and completed
- **Review Notes** — persistent local notes per task for internal review workflows
- **Review Pack Export** — consolidated Markdown export with executive summary, validation, diagnostics, resource risks, milestone outlook, and review notes
- **Keyboard Navigation** — Cmd+1 through Cmd+9 for sidebar navigation
- **Dark Mode** — optimized contrast for all views
- **Print** — native macOS print dialog for tasks and Gantt views
- **Document-based** — double-click any `.mpp` file to open it directly

---

## Building from Source

### Requirements

| Requirement | Version |
|-------------|---------|
| macOS | 14.0 (Sonoma) or later |
| Xcode | 15.0+ |
| Java | OpenJDK 21 |
| Maven | 3.8+ |

### Development Setup

```bash
# Clone the repository
git clone https://github.com/Engagendy/MPPViewerMacOS.git
cd MPPViewerMacOS

# Build the Java converter
cd MPPConverter && mvn clean package && cd ..

# Open in Xcode
open MPPViewer/MPPViewer.xcodeproj
```

Select the **MPPViewer** scheme, choose **My Mac** as the destination, and hit **Run** (Cmd+R).

### Building a DMG for Distribution

```bash
./scripts/package.sh
```

This script builds the JAR, builds the app, bundles the Eclipse Temurin JRE and converter JAR into the app, and creates a `.dmg` ready for distribution.

Options: `--skip-jar`, `--skip-app`, `--arch arm64|x86_64`, `--version X.Y.Z`

---

## Architecture

```
MPPViewerMacOS/
├── MPPViewer/                          # macOS app (Swift/SwiftUI)
│   ├── App/                            # Entry point, routing, document handling
│   ├── Models/                         # Data models (tasks, resources, calendars)
│   ├── Services/                       # MPP conversion, JSON parsing, workload calculator
│   ├── Views/
│   │   ├── Dashboard/                  # KPI cards, status breakdown, schedule health
│   │   ├── Gantt/                      # Interactive Gantt chart with Canvas rendering
│   │   ├── Schedule/                   # Split-view task list + Gantt
│   │   ├── Tasks/                      # Task table, detail inspector, CSV export
│   │   ├── Milestones/                 # Milestone tracking and health analysis
│   │   ├── Resources/                  # Resource sheet
│   │   ├── EarnedValue/               # EVM dashboard with S-Curve
│   │   ├── Workload/                   # Resource workload heatmap
│   │   ├── Calendar/                   # Calendar visualization
│   │   ├── Timeline/                   # Executive timeline view
│   │   ├── Critical/                   # Critical-path and float review
│   │   ├── Diff/                       # Two-version comparison
│   │   ├── Summary/                    # Project metadata
│   │   └── Components/                 # Shared UI (filter bar, zoom controls)
│   └── Utilities/                      # PDF/CSV export, print, date formatting
├── MPPConverterXPC/                    # XPC service target (sandboxed builds)
├── MPPConverter/                       # Java converter (Maven project)
│   └── src/main/java/.../MppToJson.java
└── scripts/
    └── package.sh                      # Build & package script
```

### How it works

```
.mpp file → MPPConverterService (Swift)
                 ↓
         Java Process / XPC Service
                 ↓
         MPXJ (Java) → JSON
                 ↓
         JSONProjectParser (Swift)
                 ↓
         ProjectModel → SwiftUI Views
```

1. The app receives an `.mpp` file through the macOS document system
2. `MPPConverterService` invokes a Java process running the MPXJ-based converter JAR
3. MPXJ reads the binary `.mpp` format and outputs structured JSON
4. `JSONProjectParser` decodes the JSON into Swift model objects
5. SwiftUI views render the project data across all tabs

---

## Tech Stack

- **UI Framework:** SwiftUI with Canvas for Gantt and workload rendering
- **Platform APIs:** AppKit (PDF generation, printing, file dialogs)
- **Project Parsing:** [MPXJ 13.4.0](https://www.mpxj.org/) — the industry-standard library for reading Microsoft Project files
- **Build Tools:** Xcode (Swift), Maven (Java)
- **CI/CD:** GitHub Actions — automated build, release, and Homebrew cask update on tag push
- **Minimum Target:** macOS 14.0 Sonoma

---

## Contributing

Contributions are welcome. Please open an issue to discuss proposed changes before submitting a pull request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>Built with SwiftUI for macOS &bull; Powered by <a href="https://www.mpxj.org/">MPXJ</a></sub>
</p>
