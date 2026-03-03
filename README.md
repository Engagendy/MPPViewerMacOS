<p align="center">
  <img src="MPPViewer/MPPViewer/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="MPP Viewer Icon">
</p>

<h1 align="center">MPP Viewer</h1>

<p align="center">
  <strong>A native macOS app for viewing Microsoft Project (.mpp) files</strong><br>
  Built with SwiftUI &bull; Powered by MPXJ
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9-orange?style=flat-square" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License">
  <img src="https://img.shields.io/badge/category-Business-purple?style=flat-square" alt="Category">
</p>

---

MPP Viewer is a lightweight, native macOS application that opens Microsoft Project `.mpp` files without requiring Microsoft Project. It converts project data via the [MPXJ](https://www.mpxj.org/) library and presents it through a modern SwiftUI interface with interactive Gantt charts, dashboards, task management, and PDF export.

---

## Features

### Dashboard
Get an instant overview of project health with KPI cards showing overall progress, on-track status, critical tasks, and total cost. Includes a task status breakdown bar, upcoming milestones, resource summary, and schedule timeline with days remaining.

### Gantt Chart
Interactive timeline visualization with:
- **Zoom controls** — Fit All, Week, Month presets, and manual +/- adjustment (2–100 px/day)
- **Critical path toggle** — Highlight critical tasks and dim non-critical ones
- **Today marker** — Red dashed line at the current date
- **Dependency arrows** — FS, SS, FF, SF relation types with routed connectors
- **Task bars** — Color-coded by type (normal, critical, milestone, summary) with progress fill
- **Row shading** — Alternating backgrounds and weekend highlighting
- **PDF export** — Multi-page landscape output

### Schedule View
Microsoft Project-style split view with a task list on the left and Gantt timeline on the right. Both panes share collapse/expand state and scroll together.

### Task List
Hierarchical task table with expand/collapse, sortable columns (ID, WBS, Name, Duration, Start, Finish, % Complete, Predecessors), and a detail inspector panel. Click any task to view full details including schedule, cost, assigned resources, predecessors/successors, and notes.

### Milestones & Deliverables
Dedicated view for milestones and summary deliverables with filtering (All / Milestones / Deliverables), status badges (Completed, Upcoming, Overdue), and sortable columns.

### Resources
Resource sheet showing all work and material resources with standard rates, max units, email, group, and assignment counts.

### Calendar
Visual calendar display with working/non-working day highlighting, exception days (holidays, special dates), and month navigation.

### PDF Export
- **Task List** — Vector PDF table with proper typography, hierarchy indentation, milestone markers, critical task highlighting, alternate row shading, pagination, and export timestamps
- **Gantt Chart** — Full-resolution bitmap capture across multiple landscape pages

### Additional
- **Project Summary** — Metadata, schedule info, statistics, and file information
- **Search** — Filter tasks by name across all views
- **Document-based** — Double-click any `.mpp` file to open it directly

---

## Screenshots

> _Open an `.mpp` file to see the Dashboard, Gantt Chart, Schedule, Task List, Milestones, Resources, and Calendar views._

---

## Installation

### Direct Download

1. Download the latest `.dmg` from [GitHub Releases](https://github.com/Engagendy/MPPViewerMacOS/releases)
2. Open the DMG and drag **MPP Viewer** to your Applications folder
3. On first launch, right-click the app → **Open** → **Open** (required for unsigned apps)

> The app bundles its own Java runtime and converter — no prerequisites needed.

### Homebrew

```bash
brew install --cask mpp-viewer
```

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

This script builds the JAR, builds the app, bundles the Eclipse Temurin JRE and converter JAR into the app, and creates a `.dmg` ready for distribution. See `scripts/package.sh --help` for options.

### 5. Open a `.mpp` file

Use **File > Open** or drag-and-drop any `.mpp` file onto the app.

---

## Architecture

```
MPPViewerMacOS/
├── MPPViewer/                          # macOS app (Swift/SwiftUI)
│   ├── App/                            # Entry point, routing, document handling
│   ├── Models/                         # Data models (tasks, resources, calendars)
│   ├── Services/                       # MPP conversion, JSON parsing, XPC protocol
│   ├── Views/
│   │   ├── Dashboard/                  # KPI cards, status breakdown, schedule health
│   │   ├── Gantt/                      # Interactive Gantt chart with Canvas rendering
│   │   ├── Schedule/                   # Split-view task list + Gantt
│   │   ├── Tasks/                      # Task table, detail inspector panel
│   │   ├── Milestones/                 # Milestone & deliverable tracking
│   │   ├── Resources/                  # Resource sheet
│   │   ├── Calendar/                   # Calendar visualization
│   │   ├── Summary/                    # Project metadata
│   │   └── Sidebar/                    # Navigation
│   └── Utilities/                      # PDF export, date/duration formatting
├── MPPConverterXPC/                    # XPC service target (App Store sandboxing)
└── MPPConverter/                       # Java converter (Maven project)
    └── src/main/java/.../MppToJson.java
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

## Data Model

| Model | Description |
|-------|-------------|
| `ProjectModel` | Root container with properties, tasks, resources, assignments, calendars |
| `ProjectTask` | Task with schedule, progress, cost, dependencies, hierarchy (parent/children) |
| `ProjectResource` | Work or material resource with rates and contact info |
| `ResourceAssignment` | Links tasks to resources with work and cost tracking |
| `ProjectCalendar` | Working hours per weekday, exception days (holidays) |
| `TaskRelation` | Predecessor/successor with relation type (FS, SS, FF, SF) and lag |

---

## Tech Stack

- **UI Framework:** SwiftUI with Canvas for Gantt rendering
- **Platform APIs:** AppKit (PDF generation, file dialogs, cursor management)
- **Project Parsing:** [MPXJ 13.4.0](https://www.mpxj.org/) — the industry-standard library for reading Microsoft Project files
- **Build Tools:** Xcode (Swift), Maven (Java)
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
