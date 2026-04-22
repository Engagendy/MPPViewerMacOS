import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let navigateToItem = Notification.Name("navigateToItem")
}

struct NativePlanAnalysis {
    let project: ProjectModel
    let evm: EVMMetrics
    let validationIssues: [ProjectValidationIssue]
    let diagnosticItems: [ProjectDiagnosticItem]

    static func build(from plan: NativeProjectPlan) -> NativePlanAnalysis {
        let project = plan.asProjectModel()
        return NativePlanAnalysis(
            project: project,
            evm: EVMCalculator.projectMetrics(tasks: project.tasks, statusDate: plan.statusDate),
            validationIssues: ProjectValidator.validate(project: project),
            diagnosticItems: ProjectDiagnostics.analyze(project: project)
        )
    }
}

struct StableDecimalTextField: View {
    let title: String
    @Binding var text: String

    @State private var draftText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(
            title,
            text: Binding(
                get: { isFocused ? draftText : text },
                set: { newValue in
                    if isFocused {
                        draftText = newValue
                    } else {
                        text = newValue
                    }
                }
            )
        )
        .focused($isFocused)
        .onAppear {
            draftText = text
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                draftText = text
            } else {
                commitDraft()
            }
        }
        .onChange(of: text) { _, newValue in
            if !isFocused {
                draftText = newValue
            }
        }
        .onSubmit {
            commitDraft()
            isFocused = false
        }
    }

    private func commitDraft() {
        let committed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        draftText = committed
        text = committed
    }
}

struct AppFinanceTerm: Identifiable {
    let shortCode: String
    let fullName: String
    let meaning: String
    let guidance: String

    var id: String { shortCode }
}

struct AppFeatureGuide: Identifiable {
    let title: String
    let icon: String
    let availability: String
    let summary: String
    let details: [String]

    var id: String { title }
}

enum AppHelpCatalog {
    static let financeTerms: [AppFinanceTerm] = [
        AppFinanceTerm(shortCode: "BAC", fullName: "Budget at Completion", meaning: "The full planned budget for the work when finished.", guidance: "Higher than expected later EAC means the forecast is overrunning BAC."),
        AppFinanceTerm(shortCode: "PV", fullName: "Planned Value", meaning: "How much budgeted work should have been earned by the status date.", guidance: "Use it as the schedule baseline for earned value."),
        AppFinanceTerm(shortCode: "EV", fullName: "Earned Value", meaning: "The budgeted value of the work actually completed so far.", guidance: "If EV lags PV, the work is behind plan."),
        AppFinanceTerm(shortCode: "AC", fullName: "Actual Cost", meaning: "What the work has actually cost so far.", guidance: "If AC rises faster than EV, cost efficiency is dropping."),
        AppFinanceTerm(shortCode: "CPI", fullName: "Cost Performance Index", meaning: "EV divided by AC, showing cost efficiency.", guidance: "Above 1.00 is favorable, below 1.00 means over budget for the value earned."),
        AppFinanceTerm(shortCode: "SPI", fullName: "Schedule Performance Index", meaning: "EV divided by PV, showing schedule efficiency.", guidance: "Above 1.00 is ahead of plan, below 1.00 is behind plan."),
        AppFinanceTerm(shortCode: "EAC", fullName: "Estimate at Completion", meaning: "The current forecast of total cost at finish.", guidance: "Compare EAC to BAC to see the likely final overrun or underrun."),
        AppFinanceTerm(shortCode: "ETC", fullName: "Estimate to Complete", meaning: "The forecast remaining cost from now to finish.", guidance: "ETC helps answer what is still expected to be spent."),
        AppFinanceTerm(shortCode: "VAC", fullName: "Variance at Completion", meaning: "BAC minus EAC, showing forecast budget variance at finish.", guidance: "Negative VAC means the current forecast ends over budget."),
        AppFinanceTerm(shortCode: "CV", fullName: "Cost Variance", meaning: "EV minus AC, showing whether earned value is ahead of or behind actual cost.", guidance: "Negative CV means the work has cost more than the value earned."),
        AppFinanceTerm(shortCode: "SV", fullName: "Schedule Variance", meaning: "EV minus PV, showing whether earned value is ahead of or behind planned value.", guidance: "Negative SV means progress is lagging the plan."),
        AppFinanceTerm(shortCode: "TCPI", fullName: "To-Complete Performance Index", meaning: "The cost efficiency needed on remaining work to hit the target budget.", guidance: "Well above 1.00 means the remaining work must perform unusually efficiently to recover."),
        AppFinanceTerm(shortCode: "BCWS", fullName: "Budgeted Cost of Work Scheduled", meaning: "Older term for PV.", guidance: "In this app, BCWS maps to planned value."),
        AppFinanceTerm(shortCode: "BCWP", fullName: "Budgeted Cost of Work Performed", meaning: "Older term for EV.", guidance: "In this app, BCWP maps to earned value."),
        AppFinanceTerm(shortCode: "ACWP", fullName: "Actual Cost of Work Performed", meaning: "Older term for AC.", guidance: "In this app, ACWP maps to actual cost."),
        AppFinanceTerm(shortCode: "WBS", fullName: "Work Breakdown Structure", meaning: "The outline code that shows a task’s place in the hierarchy.", guidance: "WBS is useful for grouping and locating summary and child tasks.")
    ]

    static let featureSections: [(title: String, items: [AppFeatureGuide])] = [
        (
            "Core Screens",
            [
                AppFeatureGuide(title: "Dashboard", icon: NavigationItem.dashboard.icon, availability: "MPP + Native Plan", summary: "Audience-focused review dashboard for project managers, executives, schedulers, and resource managers.", details: [
                    "Shows KPI cards, baseline alerts, schedule health, resource summary, milestones, and open review signals.",
                    "Supports snapshots, review templates, reminder cadence, and export-oriented review flows.",
                    "Best used as the first stop for health review rather than detailed editing."
                ]),
                AppFeatureGuide(title: "Executive Mode", icon: NavigationItem.executive.icon, availability: "MPP + Native Plan", summary: "Condensed executive health view for sponsor and steering review.", details: [
                    "Highlights progress, schedule position, cost outlook, major milestones, and top risks.",
                    "Provides summary-oriented exports and narrative review text.",
                    "Useful when you need a high-level read without planner detail."
                ]),
                AppFeatureGuide(title: "Summary", icon: NavigationItem.summary.icon, availability: "MPP + Native Plan", summary: "Read-only project property and project structure summary.", details: [
                    "Shows project metadata, counts, date bounds, calendars, cost basics, and structural facts.",
                    "Useful for orientation when opening a new project or validating file content."
                ])
            ]
        ),
        (
            "Plan Creation & Editing",
            [
                AppFeatureGuide(title: "Plan Builder", icon: NavigationItem.planner.icon, availability: "Native Plan Only", summary: "Primary native planning editor with grid entry and detailed inspector editing.", details: [
                    "Create, delete, duplicate, reorder, indent, and outdent tasks.",
                    "Edit dates, duration, predecessors, constraints, baselines, financial values, assignments, and actuals.",
                    "Supports CSV/Excel-compatible imports for tasks, assignments, dependencies, constraints, baselines, plus starter templates and import reports."
                ]),
                AppFeatureGuide(title: "Gantt Chart", icon: NavigationItem.gantt.icon, availability: "MPP Review + Native Edit", summary: "Timeline chart for visual schedule review and native plan editing.", details: [
                    "View mode keeps the chart clean for review; Edit mode unlocks task creation and visual schedule changes.",
                    "Supports drag to move or resize tasks, control-click source linking, dependency editing, and hierarchy actions.",
                    "Has a docked inspector with Task, Links, Staffing, and Finance tabs for selected items."
                ]),
                AppFeatureGuide(title: "Tasks", icon: NavigationItem.tasks.icon, availability: "MPP + Native Plan", summary: "Task table for task-by-task inspection and export.", details: [
                    "Searches by task name, ID, WBS, notes, resources, and custom fields.",
                    "Useful for broad task review when a Gantt is too visual or dense.",
                    "Exports task lists and issue-oriented CSV outputs."
                ]),
                AppFeatureGuide(title: "Milestones", icon: NavigationItem.milestones.icon, availability: "MPP + Native Plan", summary: "Milestone-focused view for upcoming checkpoints and completion review.", details: [
                    "Filters the project down to milestone tasks for schedule checkpoint review.",
                    "Useful for reporting and gate-readiness validation."
                ]),
                AppFeatureGuide(title: "Timeline", icon: NavigationItem.timeline.icon, availability: "MPP + Native Plan", summary: "High-level visual timeline for broader date-range review.", details: [
                    "Best for coarse schedule communication and presentation.",
                    "Shows the plan on a simpler temporal strip than the full editable Gantt."
                ]),
                AppFeatureGuide(title: "Schedule", icon: NavigationItem.schedule.icon, availability: "MPP + Native Plan", summary: "Read-focused schedule layout for inspecting time-phased task placement.", details: [
                    "Keeps schedule review separate from the more interactive Gantt editing surface.",
                    "Useful for scanning durations, placements, and summary alignment."
                ])
            ]
        ),
        (
            "Resources, Calendars & Status",
            [
                AppFeatureGuide(title: "Resources", icon: NavigationItem.resources.icon, availability: "MPP Review + Native Edit", summary: "Resource sheet and native resource editor for staffing data.", details: [
                    "For native plans, create and edit resources, rates, cost-per-use, max units, group, email, and base calendar.",
                    "For imported MPP files, review imported resources and their assignments in the read-only sheet.",
                    "Supports resource CSV/Excel-compatible imports, templates, and review mode."
                ]),
                AppFeatureGuide(title: "Calendar", icon: NavigationItem.calendar.icon, availability: "MPP Review + Native Edit", summary: "Calendar review and native calendar authoring for working time rules.", details: [
                    "Edit working days, time ranges, exceptions, project default calendar, and leave/holiday exceptions for native plans.",
                    "Imported projects keep the original read-only calendar inspection view.",
                    "Supports calendar CSV/Excel-compatible import, templates, and review mode."
                ]),
                AppFeatureGuide(title: "Workload", icon: NavigationItem.workload.icon, availability: "MPP + Native Plan", summary: "Resource allocation and time-phased workload review.", details: [
                    "Shows resource loading over time using task assignments and calendars.",
                    "Useful for spotting overloads, underuse, and overtime pressure."
                ]),
                AppFeatureGuide(title: "Status Center", icon: NavigationItem.statusCenter.icon, availability: "Native Plan Only", summary: "Periodic project-controls screen for updating actuals and reviewing live variance.", details: [
                    "Set the project status date and then update actual start, actual finish, progress, actual cost, status notes, and assignment actual/remaining/overtime work.",
                    "Includes filters like Needs Attention, In Progress, Overdue, and Missing Actuals.",
                    "Surfaces CPI, SPI, EAC, VAC, top slippages, cost overruns, and overtime drivers."
                ])
            ]
        ),
        (
            "Analysis & Assurance",
            [
                AppFeatureGuide(title: "Validation", icon: NavigationItem.validation.icon, availability: "MPP + Native Plan", summary: "Project quality checks focused on structural and data-entry issues.", details: [
                    "Flags errors, warnings, and information-level validation items tied to specific tasks where possible.",
                    "Useful for catching finish-before-start, missing dates, weak baselines, and similar plan defects."
                ]),
                AppFeatureGuide(title: "Diagnostics", icon: NavigationItem.diagnostics.icon, availability: "MPP + Native Plan", summary: "Schedule signal analysis for dependency, constraint, and logic hotspots.", details: [
                    "Surfaces schedule-quality concerns beyond simple validation rules.",
                    "Good for explaining where the network is brittle or where planning assumptions need review."
                ]),
                AppFeatureGuide(title: "Dependency Explorer", icon: NavigationItem.dependencyExplorer.icon, availability: "MPP + Native Plan", summary: "Focused task-relationship analysis view.", details: [
                    "Lets you inspect predecessor and successor relationships more directly than the broader task table.",
                    "Useful for network review and impact tracing."
                ]),
                AppFeatureGuide(title: "Resource Risks", icon: NavigationItem.resourceRisks.icon, availability: "MPP + Native Plan", summary: "Risk-oriented resource analysis view.", details: [
                    "Highlights over-allocation and staffing hotspots from the current schedule and assignments.",
                    "Useful for triage before adjusting calendars, staffing, or sequencing."
                ]),
                AppFeatureGuide(title: "Critical Path", icon: NavigationItem.criticalPath.icon, availability: "MPP + Native Plan", summary: "Critical and near-critical schedule review.", details: [
                    "Shows work most likely to move finish dates or absorb float first.",
                    "Useful before baseline capture, forecast review, and status meetings."
                ]),
                AppFeatureGuide(title: "Compare", icon: NavigationItem.diff.icon, availability: "MPP + Native Plan", summary: "Baseline and file-to-file comparison view.", details: [
                    "Compares project versions, native plans, or baseline states to show change impact.",
                    "Useful for change review, forecast discussion, and auditability."
                ])
            ]
        ),
        (
            "Financial & Reporting",
            [
                AppFeatureGuide(title: "Earned Value", icon: NavigationItem.earnedValue.icon, availability: "MPP + Native Plan", summary: "Dedicated financial control and earned value screen.", details: [
                    "Shows project CPI, SPI, EAC, VAC, S-curve, and task-level EVM rows.",
                    "Useful after baselines, costs, and actuals are populated.",
                    "Includes an in-screen glossary because many financial labels are abbreviated."
                ]),
                AppFeatureGuide(title: "Guide & Help", icon: NavigationItem.helpCenter.icon, availability: "App-Wide", summary: "Built-in documentation, feature reference, workflow guide, glossary, and shortcuts.", details: [
                    "Available from the sidebar and the macOS Help menu.",
                    "Explains feature purpose, availability, and common workflow paths."
                ])
            ]
        )
    ]
}

struct FinancialTermsLegendView: View {
    var terms: [AppFinanceTerm] = AppHelpCatalog.financeTerms

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Financial & EVM Terms")
                .font(.headline)
            Text("Short labels used in financial, status, and earned value views.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(terms) { term in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(term.shortCode)
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text(term.fullName)
                                .font(.subheadline.weight(.semibold))
                        }
                        Text(term.meaning)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Text(term.guidance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

struct FinancialTermsButton: View {
    var title = "Financial Terms"
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label(title, systemImage: "text.book.closed")
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ScrollView {
                FinancialTermsLegendView()
                    .padding(16)
                    .frame(width: 520, alignment: .topLeading)
            }
        }
        .help("Open a glossary for financial and earned value abbreviations used in the app.")
    }
}

struct AppGuideView: View {
    let isEditablePlan: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Guide & Help")
                        .font(.largeTitle.weight(.semibold))
                    Text("A quick reference for building plans, updating status, and reading financial and earned value signals.")
                        .foregroundStyle(.secondary)
                }

                guideSection(
                    title: "What This App Covers",
                    icon: "square.text.square",
                    lines: [
                        "Open imported `.mpp` schedules for review and analysis.",
                        isEditablePlan ? "Create and edit native `.mppplan` schedules directly in the app." : "Create a new `.mppplan` document from File > New to edit plans directly in the app.",
                        "Review schedule, workload, resources, calendars, status, financials, and earned value from the same project model."
                    ]
                )

                guideSection(
                    title: "Build a Plan",
                    icon: "square.and.pencil",
                    lines: [
                        "Use `Plan Builder` for fast grid entry and detailed task editing.",
                        "Use `Gantt Chart` in `Edit` mode for visual move, resize, link, indent, and subtask changes.",
                        "Use `Resources` and `Calendar` to define staffing, base calendars, and leave exceptions."
                    ]
                )

                guideSection(
                    title: "Import & Templates",
                    icon: "square.and.arrow.down",
                    lines: [
                        "Task, resource, calendar, assignment, dependency, constraint, and baseline imports support CSV and Excel-compatible `.xls` files.",
                        "Template exports provide starter sheets for bulk loading and recurring updates.",
                        "Import reports can reopen mapping, export warnings, and jump to affected items."
                    ]
                )

                guideSection(
                    title: "Status & Control",
                    icon: "checklist",
                    lines: [
                        "Use `Status Center` to set status date, actual dates, progress, actual cost, and assignment actual/remaining/overtime work.",
                        "Use `Earned Value` for CPI, SPI, EAC, VAC, S-curve, and task-level EVM.",
                        "Use `Dashboard`, `Validation`, and `Diagnostics` to spot schedule-quality and resource-risk issues."
                    ]
                )

                guideSection(
                    title: "Useful Shortcuts",
                    icon: "command",
                    lines: [
                        "Command-1 through Command-9 open the first sidebar views directly.",
                        "In the planner grid, Tab and Shift-Tab move between cells, Enter moves down, and Command-Return adds a row.",
                        "In Gantt edit mode, Control-click a task bar starts dependency linking."
                    ]
                )

                guideSection(
                    title: "Document Types",
                    icon: "doc.on.doc",
                    lines: [
                        "Imported `.mpp` files are review-first documents. They feed analysis, dashboards, schedule views, and read-only inspection screens.",
                        isEditablePlan ? "This document is a native `.mppplan`, so plan creation, statusing, finance entry, resource editing, and calendar editing are available." : "Create a native `.mppplan` from `File > New` when you want in-app editing, imports, status updates, and native save/open later.",
                        "Many screens work for both document types, but native plans unlock editing workflows."
                    ]
                )

                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Feature Reference")
                            .font(.headline)
                        Text("Each major screen in the app, what it is for, and what you can do there.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(Array(AppHelpCatalog.featureSections.enumerated()), id: \.offset) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(section.element.title)
                                    .font(.title3.weight(.semibold))

                                ForEach(section.element.items) { feature in
                                    featureCard(feature)
                                }
                            }

                            if section.offset != AppHelpCatalog.featureSections.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(8)
                } label: {
                    Label("Detailed Feature Guide", systemImage: "books.vertical")
                }

                GroupBox {
                    FinancialTermsLegendView()
                        .padding(8)
                } label: {
                    Label("Financial Glossary", systemImage: "chart.line.uptrend.xyaxis")
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func guideSection(title: String, icon: String, lines: [String]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(lines.enumerated()), id: \.offset) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                        Text(item.element)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(8)
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private func featureCard(_ feature: AppFeatureGuide) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(feature.title, systemImage: feature.icon)
                    .font(.headline)
                Text(feature.availability)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            }

            Text(feature.summary)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(feature.details.enumerated()), id: \.offset) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                        Text(item.element)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

enum NavigationItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case planner = "Plan Builder"
    case statusCenter = "Status Center"
    case executive = "Executive Mode"
    case summary = "Summary"
    case validation = "Validation"
    case diagnostics = "Diagnostics"
    case dependencyExplorer = "Dependency Explorer"
    case resourceRisks = "Resource Risks"
    case criticalPath = "Critical Path"
    case tasks = "Tasks"
    case gantt = "Gantt Chart"
    case schedule = "Schedule"
    case milestones = "Milestones"
    case resources = "Resources"
    case earnedValue = "Earned Value"
    case workload = "Workload"
    case calendar = "Calendar"
    case timeline = "Timeline"
    case diff = "Compare"
    case helpCenter = "Guide & Help"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .planner: return "square.and.pencil"
        case .statusCenter: return "checklist"
        case .executive: return "display"
        case .summary: return "doc.text"
        case .validation: return "checklist.unchecked"
        case .diagnostics: return "stethoscope"
        case .dependencyExplorer: return "network"
        case .resourceRisks: return "person.crop.circle.badge.exclamationmark"
        case .criticalPath: return "point.topleft.down.curvedto.point.bottomright.up"
        case .tasks: return "list.bullet.indent"
        case .gantt: return "chart.bar.xaxis"
        case .schedule: return "rectangle.split.2x1"
        case .milestones: return "diamond.fill"
        case .resources: return "person.2"
        case .earnedValue: return "chart.line.uptrend.xyaxis"
        case .workload: return "person.badge.clock"
        case .calendar: return "calendar"
        case .timeline: return "rectangle.split.3x1"
        case .diff: return "arrow.triangle.2.circlepath"
        case .helpCenter: return "questionmark.circle"
        }
    }
}

struct ContentView: View {
    @Binding var document: PlanningDocument
    @StateObject private var store = ProjectStore()
    @State private var editableAnalysis: NativePlanAnalysis?
    @State private var selectedNav: NavigationItem?
    @State private var searchText = ""
    @State private var navigateToTaskID: Int?
    @AppStorage("flaggedTaskIDs") private var flaggedTaskIDsData: Data = Data()

    init(document: Binding<PlanningDocument>) {
        self._document = document
        self._editableAnalysis = State(initialValue: document.wrappedValue.nativePlan.map(NativePlanAnalysis.build(from:)))
    }

    private var flaggedTaskIDs: Binding<Set<Int>> {
        Binding(
            get: {
                (try? JSONDecoder().decode(Set<Int>.self, from: flaggedTaskIDsData)) ?? []
            },
            set: { newValue in
                flaggedTaskIDsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            }
        )
    }

    private var searchSuggestionTasks: [ProjectTask] {
        guard let project = currentProject, !searchText.isEmpty else { return [] }
        let search = searchText.lowercased()
        return project.tasks.filter { task in
            let directMatch =
                task.name?.lowercased().contains(search) == true ||
                task.wbs?.lowercased().contains(search) == true ||
                task.notes?.lowercased().contains(search) == true ||
                task.id.map(String.init)?.contains(search) == true ||
                task.customFields?.values.contains(where: { $0.displayString.lowercased().contains(search) }) == true
            let resourceMatch = project.assignments
                .filter { $0.taskUniqueID == task.uniqueID }
                .contains { assignment in
                    guard let resourceID = assignment.resourceUniqueID else { return false }
                    return project.resources.first(where: { $0.uniqueID == resourceID })?.name?.lowercased().contains(search) == true
                }
            return directMatch || resourceMatch
        }
        .prefix(10)
        .map { $0 }
    }

    private var currentProject: ProjectModel? {
        if document.isEditablePlan {
            return editableAnalysis?.project
        }
        return store.project
    }

    private var nativePlanBinding: Binding<NativeProjectPlan>? {
        guard document.isEditablePlan else { return nil }
        return Binding(
            get: { document.nativePlan ?? .empty() },
            set: {
                document.nativePlan = $0
                editableAnalysis = NativePlanAnalysis.build(from: $0)
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedNav, showsPlanner: document.isEditablePlan)
        } detail: {
            Group {
                if !document.isEditablePlan && store.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Converting MPP file...")
                            .foregroundStyle(.secondary)
                    }
                } else if !document.isEditablePlan, let error = store.error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)
                        Text("Failed to load project")
                            .font(.headline)
                        Text(error)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                    }
                } else if let project = currentProject {
                    detailView(for: selectedNav, project: project, nativePlan: nativePlanBinding)
                } else {
                    Text("No project loaded")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $searchText, prompt: "Search tasks, IDs, WBS, resources, notes, or custom fields")
        .searchSuggestions {
            ForEach(searchSuggestionTasks) { task in
                Button {
                    selectedNav = .tasks
                    navigateToTaskID = task.uniqueID
                    searchText = ""
                } label: {
                    HStack {
                        if task.milestone == true {
                            Image(systemName: "diamond.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else if task.summary == true {
                            Image(systemName: "folder.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        VStack(alignment: .leading) {
                            Text(task.displayName)
                                .font(.caption)
                            if let wbs = task.wbs {
                                Text(wbs)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(currentProject?.properties.projectTitle ?? "MPP Viewer")
        .task(id: document.isEditablePlan) {
            if document.isEditablePlan {
                store.reset()
                refreshEditableAnalysis()
                if selectedNav == nil || selectedNav == .dashboard {
                    selectedNav = .planner
                }
            } else {
                editableAnalysis = nil
                if selectedNav == nil || selectedNav == .planner {
                    selectedNav = .dashboard
                }
                await store.loadFromDocument(document)
            }
        }
        .onChange(of: document.nativePlan) { _, _ in
            refreshEditableAnalysis()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToItem)) { notification in
            if let item = notification.object as? NavigationItem {
                selectedNav = item
            }
        }
    }

    @ViewBuilder
    private func detailView(
        for item: NavigationItem?,
        project: ProjectModel,
        nativePlan: Binding<NativeProjectPlan>?
    ) -> some View {
        switch item {
        case .dashboard:
            DashboardView(project: project)
        case .planner:
            if let nativePlan {
                PlanEditorView(plan: nativePlan)
            } else {
                ContentUnavailableView(
                    "Read-Only Import",
                    systemImage: "lock",
                    description: Text("Open or create a native plan document to edit tasks in the app.")
                )
            }
        case .statusCenter:
            if let nativePlan {
                StatusCenterView(plan: nativePlan, project: project)
            } else {
                ContentUnavailableView(
                    "Read-Only Import",
                    systemImage: "lock",
                    description: Text("Open or create a native plan document to apply status updates in the app.")
                )
            }
        case .executive:
            ExecutiveModeView(project: project)
        case .summary:
            ProjectSummaryView(project: project)
        case .validation:
            ProjectValidationView(
                project: project,
                navigateToTaskID: $navigateToTaskID,
                selectedNav: $selectedNav
            )
        case .diagnostics:
            ProjectDiagnosticsView(
                project: project,
                navigateToTaskID: $navigateToTaskID,
                selectedNav: $selectedNav
            )
        case .dependencyExplorer:
            DependencyGraphExplorerView(
                project: project,
                navigateToTaskID: $navigateToTaskID,
                selectedNav: $selectedNav
            )
        case .resourceRisks:
            ResourceDiagnosticsView(
                project: project,
                navigateToTaskID: $navigateToTaskID,
                selectedNav: $selectedNav
            )
        case .criticalPath:
            CriticalPathView(
                project: project,
                navigateToTaskID: $navigateToTaskID,
                selectedNav: $selectedNav
            )
        case .tasks:
            TaskTableView(
                tasks: project.rootTasks,
                allTasks: project.tasksByID,
                searchText: searchText,
                resources: project.resources,
                assignments: project.assignments,
                flaggedTaskIDs: flaggedTaskIDs,
                navigateToTaskID: $navigateToTaskID
            )
        case .gantt:
            GanttChartView(project: project, searchText: searchText, nativePlan: nativePlan)
        case .schedule:
            ScheduleView(project: project, searchText: searchText)
        case .milestones:
            MilestonesView(tasks: project.tasks, allTasks: project.tasksByID, searchText: searchText)
        case .resources:
            if let nativePlan {
                NativeResourcesEditorView(
                    plan: nativePlan,
                    navigateToTaskID: $navigateToTaskID,
                    selectedNav: $selectedNav
                )
            } else {
                ResourceSheetView(
                    resources: project.resources,
                    assignments: project.assignments,
                    calendars: project.calendars,
                    defaultCalendarID: project.properties.defaultCalendarUniqueId,
                    allTasks: project.tasksByID,
                    navigateToTaskID: $navigateToTaskID,
                    selectedNav: $selectedNav
                )
            }
        case .earnedValue:
            EarnedValueView(project: project)
        case .workload:
            WorkloadView(project: project)
        case .calendar:
            if let nativePlan {
                NativeCalendarEditorView(plan: nativePlan)
            } else {
                CalendarView(calendars: project.calendars)
            }
        case .timeline:
            TimelineView(project: project)
        case .diff:
            DiffView(project: project)
        case .helpCenter:
            AppGuideView(isEditablePlan: nativePlan != nil)
        case .none:
            Text("Select a view from the sidebar")
                .foregroundStyle(.secondary)
        }
    }

    private func refreshEditableAnalysis() {
        editableAnalysis = document.nativePlan.map(NativePlanAnalysis.build(from:))
    }
}

struct ResourceDiagnosticsView: View {
    let project: ProjectModel
    @Binding var navigateToTaskID: Int?
    @Binding var selectedNav: NavigationItem?

    private var items: [ResourceDiagnosticItem] {
        ResourceDiagnostics.analyze(project: project)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Resource Risks")
                    .font(.headline)
                Text("(\(items.count) issues)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 12) {
                    riskChip(count: items.filter { $0.severity == .error }.count, label: "Errors", color: .red)
                    riskChip(count: items.filter { $0.severity == .warning }.count, label: "Warnings", color: .orange)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if items.isEmpty {
                ContentUnavailableView(
                    "No Resource Risks",
                    systemImage: "person.crop.circle.badge.checkmark",
                    description: Text("No resource over-allocation risks were detected by the current diagnostics.")
                )
            } else {
                Table(items) {
                    TableColumn("Alert") { item in
                        SeverityBadge(severity: item.severity)
                    }
                    .width(min: 90, ideal: 110, max: 130)

                    TableColumn("Resource") { item in
                        Text(item.resourceName)
                    }
                    .width(min: 180, ideal: 220)

                    TableColumn("Issue") { item in
                        Text(item.title)
                    }
                    .width(min: 150, ideal: 190)

                    TableColumn("Task") { item in
                        if let taskName = item.taskName, let taskUniqueID = item.taskUniqueID {
                            Button {
                                openTask(taskUniqueID)
                            } label: {
                                Text(taskName).lineLimit(2)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(item.taskName ?? "")
                        }
                    }
                    .width(min: 180, ideal: 260)

                    TableColumn("Details") { item in
                        Text(item.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .width(min: 300, ideal: 520)
                }
            }
        }
    }

    private func openTask(_ uniqueID: Int) {
        selectedNav = .tasks
        navigateToTaskID = uniqueID
    }

    private func riskChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count)").fontWeight(.medium)
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct ProjectDiagnosticsView: View {
    let project: ProjectModel
    @Binding var navigateToTaskID: Int?
    @Binding var selectedNav: NavigationItem?

    private var items: [ProjectDiagnosticItem] {
        ProjectDiagnostics.analyze(project: project)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Diagnostics")
                    .font(.headline)
                Text("(\(items.count) signals)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 12) {
                    diagnosticChip(count: items.filter { $0.category == .constraints }.count, label: "Constraints", color: .orange)
                    diagnosticChip(count: items.filter { $0.category == .dependencies }.count, label: "Dependencies", color: .blue)
                    diagnosticChip(count: items.filter { $0.category == .flow }.count, label: "Flow", color: .purple)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if items.isEmpty {
                ContentUnavailableView(
                    "No Diagnostics",
                    systemImage: "stethoscope",
                    description: Text("No dependency or constraint hotspots were detected by the current diagnostics.")
                )
            } else {
                Table(items) {
                    TableColumn("Category") { item in
                        Label(item.category.label, systemImage: item.category.icon)
                            .foregroundStyle(item.category.color)
                    }
                    .width(min: 100, ideal: 120, max: 140)

                    TableColumn("Signal") { item in
                        Text(item.title)
                    }
                    .width(min: 170, ideal: 220)

                    TableColumn("Task ID") { item in
                        if let taskID = item.taskID, let taskUniqueID = item.taskUniqueID {
                            Button {
                                openTask(taskUniqueID)
                            } label: {
                                Text(taskID).monospacedDigit()
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("")
                        }
                    }
                    .width(min: 50, ideal: 70, max: 90)

                    TableColumn("Task") { item in
                        if let taskName = item.taskName, let taskUniqueID = item.taskUniqueID {
                            Button {
                                openTask(taskUniqueID)
                            } label: {
                                Text(taskName).lineLimit(2)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(item.taskName ?? "Project")
                        }
                    }
                    .width(min: 180, ideal: 260)

                    TableColumn("Details") { item in
                        Text(item.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .width(min: 320, ideal: 520)
                }
            }
        }
    }

    private func openTask(_ uniqueID: Int) {
        selectedNav = .tasks
        navigateToTaskID = uniqueID
    }

    private func diagnosticChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count)").fontWeight(.medium)
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct ProjectValidationView: View {
    let project: ProjectModel
    @Binding var navigateToTaskID: Int?
    @Binding var selectedNav: NavigationItem?

    @State private var selectedSeverity: ValidationSeverityFilter = .all
    @State private var sortOrder = [KeyPathComparator(\ProjectValidationIssue.sortSeverityRank, order: .reverse)]

    private var issues: [ProjectValidationIssue] {
        let allIssues = ProjectValidator.validate(project: project)
        let filtered: [ProjectValidationIssue]
        switch selectedSeverity {
        case .all:
            filtered = allIssues
        case .errors:
            filtered = allIssues.filter { $0.severity == .error }
        case .warnings:
            filtered = allIssues.filter { $0.severity == .warning }
        case .info:
            filtered = allIssues.filter { $0.severity == .info }
        }
        return filtered.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Validation Report")
                    .font(.headline)
                Text("(\(issues.count) issues)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 12) {
                    validationChip(count: issues.filter { $0.severity == .error }.count, label: "Errors", color: .red)
                    validationChip(count: issues.filter { $0.severity == .warning }.count, label: "Warnings", color: .orange)
                    validationChip(count: issues.filter { $0.severity == .info }.count, label: "Info", color: .blue)
                }

                Divider().frame(height: 16)

                Button {
                    exportValidationReport()
                } label: {
                    Label("Export CSV", systemImage: "tablecells")
                }
                .buttonStyle(.borderless)

                Divider().frame(height: 16)

                Picker("Severity", selection: $selectedSeverity) {
                    ForEach(ValidationSeverityFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if issues.isEmpty {
                ContentUnavailableView(
                    "No Validation Issues",
                    systemImage: "checkmark.shield",
                    description: Text("The imported project passed the current validation checks.")
                )
            } else {
                Table(issues, sortOrder: $sortOrder) {
                    TableColumn("Severity", value: \.sortSeverityRank) { issue in
                        Label(issue.severity.label, systemImage: issue.severity.icon)
                            .foregroundStyle(issue.severity.color)
                    }
                    .width(min: 90, ideal: 110, max: 130)

                    TableColumn("Rule", value: \.rule) { issue in
                        Text(issue.rule)
                    }
                    .width(min: 140, ideal: 180)

                    TableColumn("Task ID") { issue in
                        if let taskUniqueID = issue.taskUniqueID, let taskID = issue.taskID {
                            Button {
                                openTask(taskUniqueID)
                            } label: {
                                Text(taskID)
                                    .monospacedDigit()
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(issue.taskID ?? "")
                                .monospacedDigit()
                        }
                    }
                    .width(min: 50, ideal: 70, max: 90)

                    TableColumn("Task") { issue in
                        if let taskUniqueID = issue.taskUniqueID, let taskName = issue.taskName {
                            Button {
                                openTask(taskUniqueID)
                            } label: {
                                Text(taskName)
                                    .lineLimit(2)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(issue.taskName ?? "Project")
                                .lineLimit(2)
                        }
                    }
                    .width(min: 180, ideal: 260)

                    TableColumn("Details") { issue in
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .width(min: 300, ideal: 520)
                }
            }
        }
    }

    private func validationChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count)").fontWeight(.medium)
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func openTask(_ uniqueID: Int) {
        selectedNav = .tasks
        navigateToTaskID = uniqueID
    }

    private func exportValidationReport() {
        let formatter = ISO8601DateFormatter()
        let fileName = "Validation Report \(PDFExporter.fileNameTimestamp).csv"
        let header = ["severity", "rule", "task_id", "task_name", "message", "created_at"].joined(separator: ",")
        let rows = issues.map { issue in
            [
                csv(issue.severity.label),
                csv(issue.rule),
                csv(issue.taskID ?? ""),
                csv(issue.taskName ?? "Project"),
                csv(issue.message),
                csv(formatter.string(from: Date()))
            ].joined(separator: ",")
        }
        let csvData = ([header] + rows).joined(separator: "\n")

        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? csvData.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func csv(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

enum ValidationSeverity: Int, Comparable {
    case info = 1
    case warning = 2
    case error = 3

    static func < (lhs: ValidationSeverity, rhs: ValidationSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }

    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

enum ValidationSeverityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case errors = "Errors"
    case warnings = "Warnings"
    case info = "Info"

    var id: String { rawValue }
}

struct ProjectValidationIssue: Identifiable {
    let id = UUID()
    let severity: ValidationSeverity
    let rule: String
    let taskUniqueID: Int?
    let taskID: String?
    let taskName: String?
    let message: String

    var sortSeverityRank: Int {
        severity.rawValue
    }
}

enum ProjectValidator {
    static func validate(project: ProjectModel) -> [ProjectValidationIssue] {
        var issues: [ProjectValidationIssue] = []
        let taskAssignments = Dictionary(grouping: project.assignments, by: { $0.taskUniqueID ?? -1 })

        for task in project.tasks {
            if task.summary == true && task.milestone == true {
                issues.append(issue(
                    .warning,
                    rule: "Summary Marked As Milestone",
                    task: task,
                    "Task is flagged as both summary and milestone in the source data."
                ))
            }

            if task.milestone == true && !task.isDisplayMilestone {
                issues.append(issue(
                    .warning,
                    rule: "Suspicious Milestone",
                    task: task,
                    "Task has a raw milestone flag but behaves like a duration task instead of a zero-duration checkpoint."
                ))
            }

            if let start = task.startDate, let finish = task.finishDate, finish < start {
                issues.append(issue(
                    .error,
                    rule: "Finish Before Start",
                    task: task,
                    "Finish date is earlier than start date."
                ))
            }

            if task.summary != true && (task.startDate == nil || task.finishDate == nil) {
                issues.append(issue(
                    .warning,
                    rule: "Missing Schedule Dates",
                    task: task,
                    "Non-summary task is missing a start date, finish date, or both."
                ))
            }

            if let percent = task.percentComplete, percent > 0, task.actualStart == nil {
                issues.append(issue(
                    .info,
                    rule: "Progress Without Actual Start",
                    task: task,
                    "Task has progress recorded but no actual start date."
                ))
            }

            if let percent = task.percentComplete, percent >= 100, task.actualFinish == nil {
                issues.append(issue(
                    .info,
                    rule: "Completed Without Actual Finish",
                    task: task,
                    "Task is marked complete but no actual finish date is present."
                ))
            }

            if task.active == false, (taskAssignments[task.uniqueID]?.isEmpty == false) {
                issues.append(issue(
                    .warning,
                    rule: "Inactive Task With Assignments",
                    task: task,
                    "Task is inactive but still has assigned resources."
                ))
            }

            for relation in task.predecessors ?? [] {
                if project.tasksByID[relation.targetTaskUniqueID] == nil {
                    issues.append(issue(
                        .error,
                        rule: "Missing Predecessor Target",
                        task: task,
                        "Predecessor references missing task unique ID \(relation.targetTaskUniqueID)."
                    ))
                }
            }

            for relation in task.successors ?? [] {
                if project.tasksByID[relation.targetTaskUniqueID] == nil {
                    issues.append(issue(
                        .error,
                        rule: "Missing Successor Target",
                        task: task,
                        "Successor references missing task unique ID \(relation.targetTaskUniqueID)."
                    ))
                }
            }
        }

        if project.tasks.isEmpty {
            issues.append(ProjectValidationIssue(
                severity: .error,
                rule: "Empty Project",
                taskUniqueID: nil,
                taskID: nil,
                taskName: nil,
                message: "The parsed project contains no tasks."
            ))
        }

        return issues
    }

    private static func issue(
        _ severity: ValidationSeverity,
        rule: String,
        task: ProjectTask,
        _ message: String
    ) -> ProjectValidationIssue {
        ProjectValidationIssue(
            severity: severity,
            rule: rule,
            taskUniqueID: task.uniqueID,
            taskID: task.id.map(String.init) ?? task.outlineNumber,
            taskName: task.displayName,
            message: message
        )
    }
}

enum DiagnosticCategory {
    case constraints
    case dependencies
    case flow

    var label: String {
        switch self {
        case .constraints: return "Constraint"
        case .dependencies: return "Dependency"
        case .flow: return "Flow"
        }
    }

    var icon: String {
        switch self {
        case .constraints: return "lock.fill"
        case .dependencies: return "link"
        case .flow: return "arrow.triangle.branch"
        }
    }

    var color: Color {
        switch self {
        case .constraints: return .orange
        case .dependencies: return .blue
        case .flow: return .purple
        }
    }
}

struct ProjectDiagnosticItem: Identifiable {
    let id = UUID()
    let category: DiagnosticCategory
    let title: String
    let taskUniqueID: Int?
    let taskID: String?
    let taskName: String?
    let message: String
}

enum ProjectDiagnostics {
    static func analyze(project: ProjectModel) -> [ProjectDiagnosticItem] {
        var items: [ProjectDiagnosticItem] = []
        let calendar = Calendar.current

        for task in project.tasks {
            if let constraint = normalizedConstraint(task.constraintType) {
                items.append(item(
                    category: .constraints,
                    title: "Explicit Constraint",
                    task: task,
                        message: "Task uses constraint `\(constraint)` which can reduce scheduling flexibility."
                    ))

                if let constraintDate = task.constraintDate.flatMap(DateFormatting.parseMPXJDate) {
                    let comparisonDate: Date? = {
                        let lowered = constraint.lowercased()
                        if lowered.contains("start") { return task.startDate }
                        if lowered.contains("finish") { return task.finishDate }
                        return task.startDate ?? task.finishDate
                    }()

                    if let comparisonDate {
                        let drift = abs(calendar.dateComponents([.day], from: comparisonDate, to: constraintDate).day ?? 0)
                        if drift >= 2 {
                            items.append(item(
                                category: .constraints,
                                title: "Constraint Date Drift",
                                task: task,
                                message: "Constraint date \(DateFormatting.shortDate(constraintDate)) differs from scheduled date \(DateFormatting.shortDate(comparisonDate)) by \(drift) days."
                            ))
                        }
                    }
                } else {
                    items.append(item(
                        category: .constraints,
                        title: "Constraint Missing Date",
                        task: task,
                        message: "Task has explicit constraint `\(constraint)` but no constraint date is present."
                    ))
                }
            }

            let predecessorCount = task.predecessors?.count ?? 0
            let successorCount = task.successors?.count ?? 0
            let totalLinks = predecessorCount + successorCount
            if totalLinks >= 6 {
                items.append(item(
                    category: .dependencies,
                    title: "Dependency-Heavy Task",
                    task: task,
                    message: "Task has \(predecessorCount) predecessors and \(successorCount) successors."
                ))
            }

            if successorCount >= 5 {
                items.append(item(
                    category: .dependencies,
                    title: "Successor Fan-Out",
                    task: task,
                    message: "Task drives \(successorCount) successor links and may act as a delivery bottleneck."
                ))
            }

            for relation in task.predecessors ?? [] {
                let lag = relation.lag ?? 0
                if abs(lag) >= 16 * 3600 {
                    items.append(item(
                        category: .dependencies,
                        title: lag > 0 ? "Long Lag Dependency" : "Lead Dependency",
                        task: task,
                        message: "Predecessor link \(relation.type ?? "FS") uses \(DurationFormatting.formatSeconds(abs(lag))) \(lag > 0 ? "lag" : "lead")."
                    ))
                }

                if let predecessor = project.tasksByID[relation.targetTaskUniqueID],
                   let predecessorFinish = predecessor.finishDate,
                   let taskStart = task.startDate,
                   predecessorFinish > taskStart,
                   relation.type == nil || relation.type == "FS" {
                    let overlapDays = calendar.dateComponents([.day], from: taskStart, to: predecessorFinish).day ?? 0
                    if overlapDays >= 1 {
                        items.append(item(
                            category: .dependencies,
                            title: "Predecessor Finish After Start",
                            task: task,
                            message: "FS predecessor `\(predecessor.displayName)` finishes \(overlapDays) days after this task starts."
                        ))
                    }
                }
            }

            if task.critical == true,
               (task.predecessors?.isEmpty != false),
               (task.successors?.isEmpty != false),
               task.summary != true {
                items.append(item(
                    category: .flow,
                    title: "Isolated Critical Task",
                    task: task,
                    message: "Critical task has no linked predecessors or successors."
                ))
            }

            if task.summary != true,
               let percent = task.percentComplete,
               percent == 0,
               let predecessorCount = task.predecessors?.count,
               predecessorCount >= 3 {
                items.append(item(
                    category: .flow,
                    title: "Blocked Start Risk",
                    task: task,
                    message: "Not-started task depends on \(predecessorCount) predecessors."
                ))
            }

            if task.critical == true, predecessorCount >= 2, successorCount >= 2 {
                items.append(item(
                    category: .flow,
                    title: "Critical Chain Hub",
                    task: task,
                    message: "Critical task sits in a dense chain with \(predecessorCount) predecessors and \(successorCount) successors."
                ))
            }
        }

        return items
    }

    private static func normalizedConstraint(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = normalized.lowercased()
        if lowered == "as soon as possible" || lowered == "as late as possible" || lowered == "asap" || lowered == "alap" {
            return nil
        }
        return normalized
    }

    private static func item(
        category: DiagnosticCategory,
        title: String,
        task: ProjectTask,
        message: String
    ) -> ProjectDiagnosticItem {
        ProjectDiagnosticItem(
            category: category,
            title: title,
            taskUniqueID: task.uniqueID,
            taskID: task.id.map(String.init) ?? task.outlineNumber,
            taskName: task.displayName,
            message: message
        )
    }
}

struct ResourceDiagnosticItem: Identifiable {
    let id = UUID()
    let severity: ValidationSeverity
    let resourceName: String
    let title: String
    let taskUniqueID: Int?
    let taskName: String?
    let message: String
}

enum ResourceDiagnostics {
    static func analyze(project: ProjectModel) -> [ResourceDiagnosticItem] {
        let calendar = Calendar.current
        var items: [ResourceDiagnosticItem] = []
        let resources = project.resources.filter { $0.type?.lowercased() == "work" || $0.type == nil }

        for resource in resources {
            guard let resourceID = resource.uniqueID else { continue }
            let resourceAssignments = project.assignments.filter { $0.resourceUniqueID == resourceID }
            let maxUnits = resource.maxUnits ?? 100

            for assignment in resourceAssignments {
                if let units = assignment.assignmentUnits, units > maxUnits + 0.1 {
                    let start = assignmentDate(assignment.start) ?? project.tasksByID[assignment.taskUniqueID ?? -1]?.startDate
                    let finish = assignmentDate(assignment.finish) ?? project.tasksByID[assignment.taskUniqueID ?? -1]?.finishDate
                    let rangeText = dateRangeText(start: start, finish: finish)
                    items.append(item(
                        severity: .warning,
                        resource: resource,
                        title: "Assignment Exceeds Max Units",
                        task: project.tasksByID[assignment.taskUniqueID ?? -1],
                        message: "Assignment uses \(Int(units))% against resource max units of \(Int(maxUnits))%\(rangeText.isEmpty ? "" : " during \(rangeText)")."
                    ))
                }
            }

            let intervals = resourceAssignments.compactMap { assignment -> ResourceInterval? in
                guard let start = assignmentDate(assignment.start) ?? project.tasksByID[assignment.taskUniqueID ?? -1]?.startDate,
                      let finish = assignmentDate(assignment.finish) ?? project.tasksByID[assignment.taskUniqueID ?? -1]?.finishDate
                else { return nil }
                let startDay = calendar.startOfDay(for: start)
                let finishDay = calendar.startOfDay(for: finish)
                return ResourceInterval(
                    taskUniqueID: assignment.taskUniqueID,
                    start: min(startDay, finishDay),
                    finish: max(startDay, finishDay),
                    units: assignment.assignmentUnits ?? 100
                )
            }

            guard !intervals.isEmpty else { continue }

            var peakUnits: Double = 0
            var peakDay: Date?
            var overallocatedDays: [Date: Double] = [:]
            for interval in intervals {
                var day = interval.start
                while day <= interval.finish {
                    let totalUnits = intervals
                        .filter { $0.start <= day && $0.finish >= day }
                        .reduce(0.0) { $0 + $1.units }
                    if totalUnits > maxUnits + 0.1 {
                        overallocatedDays[day] = totalUnits
                    }
                    if totalUnits > peakUnits {
                        peakUnits = totalUnits
                        peakDay = day
                    }
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                }
            }

            if peakUnits > maxUnits + 0.1, let peakDay {
                let peakAssignments = intervals
                    .filter { $0.start <= peakDay && $0.finish >= peakDay }
                    .compactMap { interval in project.tasksByID[interval.taskUniqueID ?? -1]?.displayName }
                    .prefix(3)
                    .joined(separator: ", ")
                let overloadRange = contiguousRange(from: overallocatedDays.keys.sorted())
                let overloadRangeText = overloadRange.map { "\(DateFormatting.shortDate($0.start)) to \(DateFormatting.shortDate($0.finish))" } ?? DateFormatting.shortDate(peakDay)

                items.append(item(
                    severity: peakUnits >= maxUnits * 1.5 ? .error : .warning,
                    resource: resource,
                    title: "Overallocated Resource",
                    task: nil,
                    message: "Peak allocation reaches \(Int(peakUnits))% within overload window \(overloadRangeText). Top overlapping tasks near the peak: \(peakAssignments)."
                ))

                if let overloadRange {
                    let durationDays = calendar.dateComponents([.day], from: overloadRange.start, to: overloadRange.finish).day ?? 0
                    if durationDays >= 4 {
                        items.append(item(
                            severity: .warning,
                            resource: resource,
                            title: "Sustained Overload Window",
                            task: nil,
                            message: "Resource stays overallocated for \(durationDays + 1) consecutive days from \(DateFormatting.shortDate(overloadRange.start)) to \(DateFormatting.shortDate(overloadRange.finish))."
                        ))
                    }
                }
            }
        }

        return items
    }

    private static func assignmentDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return DateFormatting.parseMPXJDate(value)
    }

    private static func dateRangeText(start: Date?, finish: Date?) -> String {
        guard let start, let finish else { return "" }
        return "\(DateFormatting.shortDate(start)) to \(DateFormatting.shortDate(finish))"
    }

    private static func contiguousRange(from days: [Date]) -> (start: Date, finish: Date)? {
        guard let first = days.first else { return nil }
        let calendar = Calendar.current
        var bestStart = first
        var bestFinish = first
        var currentStart = first
        var currentFinish = first

        for day in days.dropFirst() {
            let delta = calendar.dateComponents([.day], from: currentFinish, to: day).day ?? 0
            if delta == 1 {
                currentFinish = day
            } else {
                if spanDays(calendar, currentStart, currentFinish) > spanDays(calendar, bestStart, bestFinish) {
                    bestStart = currentStart
                    bestFinish = currentFinish
                }
                currentStart = day
                currentFinish = day
            }
        }

        if spanDays(calendar, currentStart, currentFinish) > spanDays(calendar, bestStart, bestFinish) {
            bestStart = currentStart
            bestFinish = currentFinish
        }

        return (bestStart, bestFinish)
    }

    private static func spanDays(_ calendar: Calendar, _ start: Date, _ finish: Date) -> Int {
        calendar.dateComponents([.day], from: start, to: finish).day ?? 0
    }

    private static func item(
        severity: ValidationSeverity,
        resource: ProjectResource,
        title: String,
        task: ProjectTask?,
        message: String
    ) -> ResourceDiagnosticItem {
        ResourceDiagnosticItem(
            severity: severity,
            resourceName: resource.name ?? "Resource \(resource.uniqueID ?? 0)",
            title: title,
            taskUniqueID: task?.uniqueID,
            taskName: task?.displayName,
            message: message
        )
    }
}

private struct SeverityBadge: View {
    let severity: ValidationSeverity

    var body: some View {
        Label(severity.label, systemImage: severity.icon)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(severity.color.opacity(0.18))
            )
            .foregroundStyle(severity.color)
    }
}

private struct ResourceInterval {
    let taskUniqueID: Int?
    let start: Date
    let finish: Date
    let units: Double
}

struct CriticalPathView: View {
    let project: ProjectModel
    @Binding var navigateToTaskID: Int?
    @Binding var selectedNav: NavigationItem?

    private var criticalTasks: [ProjectTask] {
        project.tasks
            .filter { $0.summary != true && $0.critical == true }
            .sorted {
                ($0.startDate ?? .distantFuture, $0.id ?? .max) < ($1.startDate ?? .distantFuture, $1.id ?? .max)
            }
    }

    private var nearCriticalTasks: [ProjectTask] {
        project.tasks
            .filter {
                $0.summary != true &&
                $0.critical != true &&
                (($0.totalSlack ?? $0.freeSlack ?? Int.max) <= 16 * 3600)
            }
            .sorted { ($0.totalSlack ?? $0.freeSlack ?? Int.max) < ($1.totalSlack ?? $1.freeSlack ?? Int.max) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Critical Path")
                    .font(.headline)
                Spacer()
                summaryChip("\(criticalTasks.count) critical", color: .red)
                if !nearCriticalTasks.isEmpty {
                    summaryChip("\(nearCriticalTasks.count) near-critical", color: .orange)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Driving Tasks") {
                        if criticalTasks.isEmpty {
                            Text("No critical tasks were flagged in the imported data.")
                                .foregroundStyle(.secondary)
                                .padding(4)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(criticalTasks) { task in
                                    criticalRow(task, highlight: .red)
                                    if task.uniqueID != criticalTasks.last?.uniqueID {
                                        Divider()
                                    }
                                }
                            }
                            .padding(4)
                        }
                    }

                    GroupBox("Near-Critical / Float Watch") {
                        if nearCriticalTasks.isEmpty {
                            Text("No near-critical tasks with low float/slack were found in the imported data.")
                                .foregroundStyle(.secondary)
                                .padding(4)
                        } else {
                            let nearCriticalList = Array(nearCriticalTasks.prefix(25))
                            LazyVStack(spacing: 8) {
                                ForEach(nearCriticalList) { task in
                                    criticalRow(task, highlight: .orange)
                                    if task.uniqueID != nearCriticalList.last?.uniqueID {
                                        Divider()
                                    }
                                }
                            }
                            .padding(4)
                        }
                    }
                }
                .padding()
            }
        }
    }

    private func criticalRow(_ task: ProjectTask, highlight: Color) -> some View {
        Button {
            selectedNav = .tasks
            navigateToTaskID = task.uniqueID
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(highlight)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(task.id.map(String.init) ?? "\(task.uniqueID)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(task.displayName)
                            .foregroundStyle(.primary)
                    }

                    HStack(spacing: 12) {
                        meta("Start", DateFormatting.shortDate(task.start))
                        meta("Finish", DateFormatting.shortDate(task.finish))
                        meta("Total Float", task.totalSlackDisplay ?? "N/A")
                        meta("Free Float", task.freeSlackDisplay ?? "N/A")
                        meta("Progress", task.percentCompleteDisplay)
                    }

                    if let preds = task.predecessors, !preds.isEmpty {
                        Text("Predecessors: \(preds.compactMap { project.tasksByID[$0.targetTaskUniqueID]?.id.map(String.init) ?? "\($0.targetTaskUniqueID)" }.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func meta(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "N/A" : value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

private func summaryChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct StatusCenterView: View {
    @Binding var plan: NativeProjectPlan
    let project: ProjectModel

    @State private var selectedTaskID: Int?
    @State private var filter: StatusTaskFilter = .attention
    @State private var searchText = ""

    private var workTasks: [ProjectTask] {
        project.tasks.filter { $0.summary != true }
    }

    private var statusMetrics: EVMMetrics {
        EVMCalculator.projectMetrics(tasks: workTasks, statusDate: plan.statusDate)
    }

    private var overdueCount: Int {
        workTasks.filter { !$0.isCompleted && ($0.finishDate ?? .distantFuture) < plan.statusDate }.count
    }

    private var inProgressCount: Int {
        workTasks.filter(\.isInProgress).count
    }

    private var missingActualCount: Int {
        workTasks.filter { task in
            let shouldHaveActualStart = (task.percentComplete ?? 0) > 0
            let shouldHaveActualFinish = task.isCompleted
            let missingStart = shouldHaveActualStart && task.actualStart == nil
            let missingFinish = shouldHaveActualFinish && task.actualFinish == nil
            return missingStart || missingFinish
        }.count
    }

    private var filteredTasks: [ProjectTask] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return workTasks.filter { task in
            let matchesFilter = switch filter {
            case .all:
                true
            case .attention:
                taskStatusNeedsAttention(task)
            case .inProgress:
                task.isInProgress
            case .overdue:
                !task.isCompleted && ((task.finishDate ?? .distantFuture) < plan.statusDate)
            case .missingActuals:
                ((task.percentComplete ?? 0) > 0 && task.actualStart == nil) || (task.isCompleted && task.actualFinish == nil)
            }

            guard matchesFilter else { return false }
            guard !trimmedSearch.isEmpty else { return true }
            return task.displayName.lowercased().contains(trimmedSearch)
                || (task.wbs?.lowercased().contains(trimmedSearch) == true)
                || (task.id.map(String.init)?.contains(trimmedSearch) == true)
        }
    }

    private var selectedProjectTask: ProjectTask? {
        guard let selectedTaskID else { return nil }
        return project.tasksByID[selectedTaskID]
    }

    private var selectedAssignments: [NativePlanAssignment] {
        guard let selectedTaskID else { return [] }
        return plan.assignments.filter { $0.taskID == selectedTaskID }
    }

    private var topScheduleSlips: [ProjectTask] {
        let slippedTasks = workTasks.filter { ($0.finishVarianceDays ?? 0) > 0 }
        let sortedTasks = slippedTasks.sorted { lhs, rhs in
            (lhs.finishVarianceDays ?? 0) > (rhs.finishVarianceDays ?? 0)
        }
        return Array(sortedTasks.prefix(5))
    }

    private var topCostOverruns: [ProjectTask] {
        let overrunningTasks = workTasks.filter { task in
            let baseline = task.baselineCost ?? task.cost ?? 0
            let actual = task.actualCost ?? 0
            return baseline > 0 && actual > baseline
        }

        let sortedTasks = overrunningTasks.sorted { lhs, rhs in
            let lhsBaseline = lhs.baselineCost ?? lhs.cost ?? 0
            let rhsBaseline = rhs.baselineCost ?? rhs.cost ?? 0
            let lhsOverrun = (lhs.actualCost ?? 0) - lhsBaseline
            let rhsOverrun = (rhs.actualCost ?? 0) - rhsBaseline
            return lhsOverrun > rhsOverrun
        }

        return Array(sortedTasks.prefix(5))
    }

    private var topOvertimeDrivers: [(assignment: NativePlanAssignment, resource: NativePlanResource?)] {
        plan.assignments
            .filter { ($0.overtimeWorkSeconds ?? 0) > 0 }
            .sorted { ($0.overtimeWorkSeconds ?? 0) > ($1.overtimeWorkSeconds ?? 0) }
            .prefix(5)
            .map { assignment in
                (assignment, plan.resources.first(where: { $0.id == assignment.resourceID }))
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
            Divider()
            metricsStrip
            Divider()

            HStack(spacing: 0) {
                taskListPane
                    .frame(minWidth: 420, idealWidth: 540, maxWidth: 680)

                Divider()

                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear {
            if selectedTaskID == nil {
                selectedTaskID = filteredTasks.first?.uniqueID ?? workTasks.first?.uniqueID
            }
        }
        .onChange(of: plan.tasks.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                selectedTaskID = nil
                return
            }

            if let selectedTaskID, ids.contains(selectedTaskID) {
                return
            }

            selectedTaskID = ids.first
        }
        .onChange(of: filter) { _, _ in
            if let selectedTaskID, filteredTasks.contains(where: { $0.uniqueID == selectedTaskID }) {
                return
            }
            selectedTaskID = filteredTasks.first?.uniqueID
        }
    }

    private var statusHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Status Center")
                    .font(.title2.weight(.semibold))
                Text("Update actuals, variance, and earned value as of the current status date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Filter", selection: $filter) {
                ForEach(StatusTaskFilter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 440)

            TextField("Search Tasks", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            DatePicker("Status Date", selection: statusDateBinding, displayedComponents: .date)
                .labelsHidden()
                .help("Sets the control date used by earned value and variance calculations.")

            Button("Today") {
                statusDateBinding.wrappedValue = Calendar.current.startOfDay(for: Date())
            }
            .help("Move the status date to today.")

            Button("Apply Status Defaults") {
                applyStatusDefaults()
            }
            .help("Fill missing actual dates for tasks that have already started or finished by the current status date.")

            FinancialTermsButton()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var metricsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                statusMetricCard(title: "In Progress", value: "\(inProgressCount)", tone: .blue)
                statusMetricCard(title: "Overdue", value: "\(overdueCount)", tone: overdueCount > 0 ? .red : .secondary)
                statusMetricCard(title: "Missing Actuals", value: "\(missingActualCount)", tone: missingActualCount > 0 ? .orange : .secondary)
                statusMetricCard(title: "BAC", value: currencyText(statusMetrics.bac), tone: .primary)
                statusMetricCard(title: "AC", value: currencyText(statusMetrics.ac), tone: .primary)
                statusMetricCard(title: "CPI", value: ratioText(statusMetrics.cpi), tone: statusMetrics.cpi >= 1 ? .green : .orange)
                statusMetricCard(title: "SPI", value: ratioText(statusMetrics.spi), tone: statusMetrics.spi >= 1 ? .green : .orange)
                statusMetricCard(title: "EAC", value: currencyText(statusMetrics.eac), tone: .primary)
                statusMetricCard(title: "VAC", value: currencyText(statusMetrics.vac), tone: statusMetrics.vac >= 0 ? .green : .red)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var taskListPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Task Status")
                    .font(.headline)
                Text("(\(filteredTasks.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            HStack(spacing: 0) {
                listHeader("Task", width: 220, alignment: .leading)
                listHeader("%", width: 48)
                listHeader("Actual Start", width: 94)
                listHeader("Actual Finish", width: 94)
                listHeader("Cost Δ", width: 82)
                listHeader("Slip", width: 62)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.thinMaterial)

            Divider()

            List(selection: $selectedTaskID) {
                ForEach(filteredTasks, id: \.uniqueID) { task in
                    Button {
                        selectedTaskID = task.uniqueID
                    } label: {
                        HStack(spacing: 0) {
                            taskCell(task: task)
                            numericCell(task.percentComplete.map { "\(Int($0))%" } ?? "0%", width: 48)
                            numericCell(task.actualStart.map(DateFormatting.shortDate) ?? "Missing", width: 94, tint: task.actualStart == nil && (task.percentComplete ?? 0) > 0 ? .orange : .secondary)
                            numericCell(task.actualFinish.map(DateFormatting.shortDate) ?? "Missing", width: 94, tint: task.actualFinish == nil && task.isCompleted ? .orange : .secondary)
                            numericCell(costVarianceText(for: task), width: 82, tint: costVarianceColor(for: task))
                            numericCell(slipText(for: task), width: 62, tint: slipColor(for: task))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tag(task.uniqueID)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            }
            .listStyle(.plain)
        }
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let task = selectedProjectTask {
                    taskStatusEditor(task: task)
                    assignmentStatusEditor(task: task)
                } else {
                    Text("Select a task from the left to update status, actuals, and progress.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top)
                }

                varianceDashboard
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func taskStatusEditor(task: ProjectTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.displayName)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 8) {
                        if let wbs = task.wbs {
                            Text(wbs)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }

                        statusBadge(for: task)
                    }
                }

                Spacer()
            }

            GroupBox("Task Update") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Actual Start")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            DatePicker("", selection: actualStartBinding(for: task.uniqueID), displayedComponents: .date)
                                .labelsHidden()
                            HStack(spacing: 8) {
                                Button("Use Scheduled") {
                                    setActualStart(for: task.uniqueID, to: task.startDate ?? plan.statusDate)
                                }
                                Button("Clear") {
                                    setActualStart(for: task.uniqueID, to: nil)
                                }
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Actual Finish")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            DatePicker("", selection: actualFinishBinding(for: task.uniqueID), displayedComponents: .date)
                                .labelsHidden()
                            HStack(spacing: 8) {
                                Button("Use Scheduled") {
                                    setActualFinish(for: task.uniqueID, to: task.finishDate ?? plan.statusDate)
                                }
                                Button("Clear") {
                                    setActualFinish(for: task.uniqueID, to: nil)
                                }
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("% Complete")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("0", text: percentCompleteBinding(for: task.uniqueID))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 84)
                            Text("Statused progress")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Actual Cost")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            StableDecimalTextField(title: "0", text: actualCostBinding(for: task.uniqueID))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                            Text("Override only if needed")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Status Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: notesBinding(for: task.uniqueID))
                            .font(.body)
                            .frame(minHeight: 72)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                            )
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("Variance Snapshot") {
                VStack(alignment: .leading, spacing: 8) {
                    statusFactRow(label: "Baseline", value: baselineRangeText(for: task))
                    statusFactRow(label: "Current", value: currentRangeText(for: task))
                    statusFactRow(label: "Planned Value", value: currencyText(task.bcws ?? EVMCalculator.compute(for: task, statusDate: plan.statusDate).pv))
                    statusFactRow(label: "Earned Value", value: currencyText(task.bcwp ?? EVMCalculator.compute(for: task, statusDate: plan.statusDate).ev))
                    statusFactRow(label: "Actual Cost", value: currencyText(task.acwp ?? EVMCalculator.compute(for: task, statusDate: plan.statusDate).ac))
                    statusFactRow(label: "Cost Variance", value: costVarianceText(for: task), tint: costVarianceColor(for: task))
                    statusFactRow(label: "Schedule Variance", value: currencyText(EVMCalculator.compute(for: task, statusDate: plan.statusDate).sv), tint: EVMCalculator.compute(for: task, statusDate: plan.statusDate).sv >= 0 ? .green : .red)
                }
                .padding(.top, 4)
            }
        }
    }

    private func assignmentStatusEditor(task: ProjectTask) -> some View {
        GroupBox("Assignment Updates") {
            VStack(alignment: .leading, spacing: 10) {
                if selectedAssignments.isEmpty {
                    Text("No assignments on this task yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectedAssignments) { assignment in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(resourceName(for: assignment))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("Units \(Int(assignment.units))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 12) {
                                assignmentField(title: "Actual (h)", text: assignmentHoursBinding(for: assignment.id, keyPath: \.actualWorkSeconds))
                                assignmentField(title: "Remaining (h)", text: assignmentHoursBinding(for: assignment.id, keyPath: \.remainingWorkSeconds))
                                assignmentField(title: "OT (h)", text: assignmentHoursBinding(for: assignment.id, keyPath: \.overtimeWorkSeconds))
                                Spacer()
                                Text(assignmentCostSummary(for: assignment))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.primary.opacity(0.03))
                        )
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var varianceDashboard: some View {
        GroupBox("Control Radar") {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Top Schedule Slips")
                        .font(.headline)
                    if topScheduleSlips.isEmpty {
                        Text("No slipped tasks against the current baseline.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(topScheduleSlips, id: \.uniqueID) { task in
                            radarRow(
                                title: task.displayName,
                                detail: slipText(for: task),
                                tint: .red,
                                action: { selectedTaskID = task.uniqueID }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Top Cost Overruns")
                        .font(.headline)
                    if topCostOverruns.isEmpty {
                        Text("No tasks are exceeding baseline cost.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(topCostOverruns, id: \.uniqueID) { task in
                            radarRow(
                                title: task.displayName,
                                detail: costVarianceText(for: task),
                                tint: .orange,
                                action: { selectedTaskID = task.uniqueID }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Overtime Drivers")
                        .font(.headline)
                    if topOvertimeDrivers.isEmpty {
                        Text("No explicit overtime has been statused yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(topOvertimeDrivers.enumerated()), id: \.offset) { _, item in
                            radarRow(
                                title: resourceName(for: item.assignment),
                                detail: hoursText(item.assignment.overtimeWorkSeconds),
                                tint: .purple,
                                action: { selectedTaskID = item.assignment.taskID }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.top, 4)
        }
    }

    private func radarRow(title: String, detail: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(tint)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    private func listHeader(_ title: String, width: CGFloat, alignment: Alignment = .center) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
    }

    private func taskCell(task: ProjectTask) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(taskStatusColor(for: task))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.displayName)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if let wbs = task.wbs {
                        Text(wbs)
                    }
                    Text(statusText(for: task))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .frame(width: 220, alignment: .leading)
    }

    private func numericCell(_ value: String, width: CGFloat, tint: Color = .secondary) -> some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(tint)
            .frame(width: width)
    }

    private func statusMetricCard(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(tone)
        }
        .frame(width: 108, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func statusBadge(for task: ProjectTask) -> some View {
        Text(statusText(for: task))
            .font(.caption.weight(.semibold))
            .foregroundStyle(taskStatusColor(for: task))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(taskStatusColor(for: task).opacity(0.14))
            )
    }

    private func statusFactRow(label: String, value: String, tint: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(tint)
        }
        .font(.callout)
    }

    private func assignmentField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("0", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 88)
        }
    }

    private var statusDateBinding: Binding<Date> {
        Binding(
            get: { plan.statusDate },
            set: { plan.statusDate = Calendar.current.startOfDay(for: $0) }
        )
    }

    private func percentCompleteBinding(for taskID: Int) -> Binding<String> {
        Binding(
            get: {
                guard let index = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return "" }
                return "\(Int(plan.tasks[index].percentComplete.rounded()))"
            },
            set: { newValue in
                guard let index = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return }
                let parsed = Double(newValue.filter { $0.isNumber || $0 == "." }) ?? 0
                plan.tasks[index].percentComplete = min(max(parsed, 0), 100)

                if plan.tasks[index].percentComplete > 0, plan.tasks[index].actualStartDate == nil {
                    plan.tasks[index].actualStartDate = min(plan.tasks[index].startDate, plan.statusDate)
                }
                if plan.tasks[index].percentComplete >= 100, plan.tasks[index].actualFinishDate == nil {
                    plan.tasks[index].actualFinishDate = min(plan.tasks[index].finishDate, plan.statusDate)
                }
            }
        )
    }

    private func actualCostBinding(for taskID: Int) -> Binding<String> {
        Binding(
            get: {
                guard let index = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return "" }
                return plan.tasks[index].actualCost.map(decimalText) ?? ""
            },
            set: { newValue in
                guard let index = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return }
                plan.tasks[index].actualCost = parseDecimalInput(newValue)
            }
        )
    }

    private func notesBinding(for taskID: Int) -> Binding<String> {
        Binding(
            get: {
                guard let index = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return "" }
                return plan.tasks[index].notes
            },
            set: { newValue in
                guard let index = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return }
                plan.tasks[index].notes = newValue
            }
        )
    }

    private func actualStartBinding(for taskID: Int) -> Binding<Date> {
        Binding(
            get: {
                guard let index = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return plan.statusDate }
                return plan.tasks[index].actualStartDate ?? plan.tasks[index].startDate
            },
            set: { newValue in
                setActualStart(for: taskID, to: newValue)
            }
        )
    }

    private func actualFinishBinding(for taskID: Int) -> Binding<Date> {
        Binding(
            get: {
                guard let index = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return plan.statusDate }
                return plan.tasks[index].actualFinishDate ?? plan.tasks[index].finishDate
            },
            set: { newValue in
                setActualFinish(for: taskID, to: newValue)
            }
        )
    }

    private func assignmentHoursBinding(for assignmentID: Int, keyPath: WritableKeyPath<NativePlanAssignment, Int?>) -> Binding<String> {
        Binding(
            get: {
                guard let index = plan.assignments.firstIndex(where: { $0.id == assignmentID }) else { return "" }
                return hoursText(plan.assignments[index][keyPath: keyPath])
            },
            set: { newValue in
                guard let index = plan.assignments.firstIndex(where: { $0.id == assignmentID }) else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    plan.assignments[index][keyPath: keyPath] = nil
                } else if let value = Double(trimmed) {
                    plan.assignments[index][keyPath: keyPath] = max(0, Int(value * 3600))
                }
            }
        )
    }

    private func setActualStart(for taskID: Int, to date: Date?) {
        guard let index = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let normalized = date.map { Calendar.current.startOfDay(for: $0) }
        plan.tasks[index].actualStartDate = normalized
        if let normalized, let finish = plan.tasks[index].actualFinishDate, finish < normalized {
            plan.tasks[index].actualFinishDate = normalized
        }
    }

    private func setActualFinish(for taskID: Int, to date: Date?) {
        guard let index = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let normalized = date.map { Calendar.current.startOfDay(for: $0) }
        if let normalized, let start = plan.tasks[index].actualStartDate, normalized < start {
            plan.tasks[index].actualFinishDate = start
        } else {
            plan.tasks[index].actualFinishDate = normalized
        }

        if plan.tasks[index].actualFinishDate != nil, plan.tasks[index].percentComplete < 100 {
            plan.tasks[index].percentComplete = 100
        }
    }

    private func applyStatusDefaults() {
        let statusDate = Calendar.current.startOfDay(for: plan.statusDate)
        for index in plan.tasks.indices {
            if plan.tasks[index].percentComplete > 0, plan.tasks[index].actualStartDate == nil {
                plan.tasks[index].actualStartDate = min(plan.tasks[index].startDate, statusDate)
            }

            if plan.tasks[index].percentComplete >= 100, plan.tasks[index].actualFinishDate == nil {
                plan.tasks[index].actualFinishDate = min(plan.tasks[index].finishDate, statusDate)
            }

            if let actualStart = plan.tasks[index].actualStartDate, actualStart > statusDate {
                plan.tasks[index].actualStartDate = statusDate
            }

            if let actualFinish = plan.tasks[index].actualFinishDate, actualFinish > statusDate {
                plan.tasks[index].actualFinishDate = statusDate
            }
        }
    }

    private func taskStatusNeedsAttention(_ task: ProjectTask) -> Bool {
        isOverdue(task)
            || task.finishVarianceDays ?? 0 > 0
            || costVarianceValue(for: task) > 0
            || ((task.percentComplete ?? 0) > 0 && task.actualStart == nil)
            || (task.isCompleted && task.actualFinish == nil)
    }

    private func costVarianceValue(for task: ProjectTask) -> Double {
        (task.actualCost ?? 0) - (task.baselineCost ?? task.cost ?? 0)
    }

    private func costVarianceText(for task: ProjectTask) -> String {
        let variance = costVarianceValue(for: task)
        guard variance != 0 else { return "On plan" }
        return currencyText(variance)
    }

    private func costVarianceColor(for task: ProjectTask) -> Color {
        let variance = costVarianceValue(for: task)
        if variance > 0 { return .red }
        if variance < 0 { return .green }
        return .secondary
    }

    private func slipText(for task: ProjectTask) -> String {
        let days = task.finishVarianceDays ?? task.startVarianceDays ?? 0
        if days == 0 { return "On time" }
        return "\(days > 0 ? "+" : "")\(days)d"
    }

    private func slipColor(for task: ProjectTask) -> Color {
        let days = task.finishVarianceDays ?? task.startVarianceDays ?? 0
        if days > 0 { return .red }
        if days < 0 { return .green }
        return .secondary
    }

    private func baselineRangeText(for task: ProjectTask) -> String {
        let start = task.baselineStartDate.map(DateFormatting.simpleDate) ?? "?"
        let finish = task.baselineFinishDate.map(DateFormatting.simpleDate) ?? "?"
        return "\(start) -> \(finish)"
    }

    private func currentRangeText(for task: ProjectTask) -> String {
        let start = task.startDate.map(DateFormatting.simpleDate) ?? "?"
        let finish = task.finishDate.map(DateFormatting.simpleDate) ?? "?"
        return "\(start) -> \(finish)"
    }

    private func statusText(for task: ProjectTask) -> String {
        if task.isCompleted { return "Complete" }
        if isOverdue(task) { return "Overdue" }
        if task.isInProgress { return "In Progress" }
        return "Not Started"
    }

    private func taskStatusColor(for task: ProjectTask) -> Color {
        if task.isCompleted { return .green }
        if isOverdue(task) { return .red }
        if task.isInProgress { return .blue }
        return .secondary
    }

    private func isOverdue(_ task: ProjectTask) -> Bool {
        guard !task.isCompleted, let finishDate = task.finishDate else { return false }
        return finishDate < plan.statusDate
    }

    private func resourceName(for assignment: NativePlanAssignment) -> String {
        if let resourceID = assignment.resourceID {
            if let name = plan.resources.first(where: { $0.id == resourceID })?.name,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
        }
        return "Unassigned"
    }

    private func assignmentCostSummary(for assignment: NativePlanAssignment) -> String {
        guard let projectAssignment = project.assignments.first(where: { $0.uniqueID == assignment.id }) else {
            return "No rolled cost"
        }
        return projectAssignment.cost.map(currencyText) ?? "No rolled cost"
    }

    private func hoursText(_ seconds: Int?) -> String {
        guard let seconds else { return "" }
        let hours = Double(seconds) / 3600
        return abs(hours.rounded() - hours) < 0.01 ? "\(Int(hours.rounded()))" : String(format: "%.1f", hours)
    }

    private func decimalText(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private func parseDecimalInput(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: ",", with: "")
            .filter { $0.isNumber || $0 == "." }
        return Double(normalized)
    }

    private func currencyText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = project.properties.currencyCode ?? "USD"
        formatter.currencySymbol = project.properties.currencySymbol ?? "$"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }

    private func ratioText(_ value: Double) -> String {
        value == 0 ? "0.00" : String(format: "%.2f", value)
    }
}

private enum StatusTaskFilter: String, CaseIterable, Identifiable {
    case attention = "Needs Attention"
    case all = "All"
    case inProgress = "In Progress"
    case overdue = "Overdue"
    case missingActuals = "Missing Actuals"

    var id: String { rawValue }
}
