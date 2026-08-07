import SwiftUI
import SwiftData
import AppKit

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

struct AppWorkflowGuide: Identifiable {
    let title: String
    let icon: String
    let summary: String
    let steps: [String]

    var id: String { title }
}

struct AppDocumentModeGuide: Identifiable {
    let typeName: String
    let bestFor: String
    let editing: String
    let notes: [String]

    var id: String { typeName }
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
                AppFeatureGuide(title: "Portfolio", icon: NavigationItem.portfolio.icon, availability: "MPP + Native Plan Registry", summary: "Multi-project workspace for registering plans, opening a live workspace, and reviewing PMO-level signals across the portfolio.", details: [
                    "Registers imported `.mpp` and native `.mppplan` plans in one portfolio workspace.",
                    "Tracks workspace, program, sponsor, stage, approval, review cadence, strategic alignment, risk score, and archive state per plan.",
                    "Surfaces executive rollups, governance ranking, resource capacity, roadmap milestones, cross-project links, and review snapshots for portfolio oversight."
                ]),
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
                    "Edit dates, duration, predecessors, constraints, baselines, financial values, assignments, actuals, agile type, sprint, story points, epic, and tags.",
                    "Supports CSV/Excel-compatible imports for tasks, assignments, dependencies, constraints, baselines, plus starter templates and import reports."
                ]),
                AppFeatureGuide(title: "Agile Board", icon: NavigationItem.agileBoard.icon, availability: "Native Plan Only", summary: "Hybrid planning surface for backlog, sprint, and agile reporting on the same native plan data.", details: [
                    "Organizes native tasks into backlog and board lanes with status, sprint, epic, story-point, parent, and tag metadata.",
                    "Includes sprint planner, capacity review, bucket ordering, workflow controls, reports, focus mode, and an optional details pane.",
                    "Keeps agile execution tied to the same dates, resources, calendars, assignments, baselines, and financial model used elsewhere in the app."
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
                    "Surfaces CPI, SPI, EAC, VAC, top slippages, cost overruns, overtime drivers, and saved status snapshot history."
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
                    "Documents document modes, screen-by-screen features, portfolio workflows, imports, keyboard shortcuts, and financial glossary terms.",
                    "Use it as the in-app reference when moving between portfolio oversight, native editing, schedule control, and agile delivery."
                ])
            ]
        )
    ]

    static let documentModes: [AppDocumentModeGuide] = [
        AppDocumentModeGuide(
            typeName: ".mpp",
            bestFor: "Reviewing Microsoft Project schedules on macOS",
            editing: "Read-only review and analysis",
            notes: [
                "Use imported MPP files for dashboard review, schedule analysis, workload, diagnostics, and exports.",
                "Imported MPP files can still be registered in Portfolio for multi-project rollups, even though editing screens remain read-only.",
                "Imported MPP files keep original project data and do not unlock native editing screens like Plan Builder or Status Center."
            ]
        ),
        AppDocumentModeGuide(
            typeName: ".mppplan",
            bestFor: "Building and updating plans directly in the app",
            editing: "Full native editing",
            notes: [
                "Native plans can be opened into the live workspace from Portfolio and edited directly across planning, statusing, resource, calendar, agile, and finance workflows.",
                "Native plans unlock Plan Builder, Gantt editing, Resources, Calendar, Status Center, finance entry, imports, and native save/open later.",
                "Use `.mppplan` when the app is the working system for planning, statusing, and project controls."
            ]
        )
    ]

    static let workflows: [AppWorkflowGuide] = [
        AppWorkflowGuide(
            title: "Start Here",
            icon: "play.circle",
            summary: "Recommended first-run path for understanding the app quickly.",
            steps: [
                "Open the included showcase `.mppplan` to see a fully populated native schedule with resources, calendars, status, and finance already filled in.",
                "Visit `Portfolio` for workspace context, then `Dashboard` for overall health, followed by `Plan Builder` and `Gantt Chart` for the two main editing surfaces.",
                "Continue to `Agile Board`, `Status Center`, `Earned Value`, `Resources`, and `Calendar` to see delivery, controls, and staffing workflows."
            ]
        ),
        AppWorkflowGuide(
            title: "Portfolio Review Cadence",
            icon: "square.stack.3d.up",
            summary: "Use this path for multi-project PMO review, governance, and recurring portfolio checkpoints.",
            steps: [
                "Import multiple `.mpp` or `.mppplan` documents into `Portfolio` and group them by workspace, program, health, or approval state.",
                "Enrich each plan with metadata such as sponsor, objective, stage, review cadence, strategic alignment, and risk score.",
                "Use executive, governance, roadmap, dependency, and capacity signals to identify issues, then capture a review snapshot or export a review pack."
            ]
        ),
        AppWorkflowGuide(
            title: "Build a Native Plan",
            icon: "square.and.pencil",
            summary: "Use this path when creating or maintaining a plan directly in the app.",
            steps: [
                "Create a new `.mppplan` document or duplicate a native plan you already have.",
                "Use `Plan Builder` for grid-first entry, hierarchy editing, constraints, baselines, assignments, and finance values.",
                "Use `Gantt Chart` in Edit mode when date movement, visual resizing, linking, or structure changes are easier to do on a timeline.",
                "Use `Resources` and `Calendar` to set staffing, rates, working time, and exceptions before deeper controls work."
            ]
        ),
        AppWorkflowGuide(
            title: "Hybrid Agile Planning",
            icon: "rectangle.3.group.bubble.left",
            summary: "Use this path when you want backlog, sprint, and board flow on top of the same project schedule.",
            steps: [
                "Add agile metadata in `Plan Builder`, including agile type, board status, sprint, story points, epic, and tags.",
                "Open `Agile Board` to manage backlog flow, assign work into sprints, and review sprint capacity and committed points.",
                "Capture periodic snapshots in `Status Center`, then review trend and sprint reporting back in `Agile Board`."
            ]
        ),
        AppWorkflowGuide(
            title: "Import Spreadsheet Data",
            icon: "square.and.arrow.down",
            summary: "Use mapped imports when your source data already lives in spreadsheets.",
            steps: [
                "Open a native `.mppplan`, then use import actions in `Plan Builder`, `Resources`, or `Calendar`.",
                "Map your spreadsheet columns in the import sheet rather than forcing a fixed template shape.",
                "Review the import report for created, updated, skipped, and warning rows, then jump back to affected items if needed."
            ]
        ),
        AppWorkflowGuide(
            title: "Status and Controls Cycle",
            icon: "checklist",
            summary: "Use this path for weekly or periodic updates after the plan is underway.",
            steps: [
                "Set the project status date in `Status Center`, then update actual start, actual finish, progress, actual cost, and assignment actual/remaining/overtime work.",
                "Review `Earned Value` for CPI, SPI, EAC, VAC, S-curve shape, and task-level cost/schedule variance.",
                "Finish in `Validation`, `Diagnostics`, `Workload`, and `Dashboard` to identify issues, overloads, and review outputs."
            ]
        )
    ]

    static let importCoverage: [String] = [
        "Tasks, resources, calendars, assignments, dependencies, constraints, baselines, and financial fields support mapped CSV import.",
        "Excel-compatible `.xls` templates are included for bulk loading and recurring update cycles.",
        "Template exports provide starter sheets, while import reports let you reopen mapping, export warnings, and jump to affected items."
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
        .hoverHighlight()
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
                    Text("A quick reference for portfolio review, building plans, updating status, and reading financial and earned value signals.")
                        .foregroundStyle(.secondary)
                }

                guideSection(
                    title: "What This App Covers",
                    icon: "square.text.square",
                    lines: [
                        "Open imported `.mpp` schedules for review and analysis.",
                        "Register multiple `.mpp` and `.mppplan` documents in `Portfolio` for portfolio-level review, governance, and capacity analysis.",
                        isEditablePlan ? "Create and edit native `.mppplan` schedules directly in the app." : "Create a new `.mppplan` document from File > New to edit plans directly in the app.",
                        "Review schedule, workload, resources, calendars, status, financials, agile delivery, and earned value from the same project model."
                    ]
                )

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Use the included showcase plan as your first guided tour through the app.")
                            .font(.headline)
                        Text("Open `aurora-commerce-launch.mppplan` to see tasks, hierarchy, calendars, resources, assignments, status, and financial controls already populated.")
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Label("Native sample plan included", systemImage: "doc.badge.plus")
                                .font(.caption.weight(.semibold))
                            Label("Best viewed with Portfolio → Dashboard → Plan Builder → Agile Board → Status Center", systemImage: "arrow.right.circle")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                } label: {
                    Label("Start With The Sample Plan", systemImage: "star")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(AppHelpCatalog.documentModes) { mode in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(mode.typeName)
                                        .font(.system(.headline, design: .monospaced))
                                    Text(mode.bestFor)
                                        .font(.subheadline.weight(.semibold))
                                }
                                Text("Editing: \(mode.editing)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                ForEach(Array(mode.notes.enumerated()), id: \.offset) { note in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 6))
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 6)
                                        Text(note.element)
                                            .font(.caption)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }

                            if mode.id != AppHelpCatalog.documentModes.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(8)
                } label: {
                    Label("Document Modes", systemImage: "doc.on.doc")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(AppHelpCatalog.workflows) { workflow in
                            workflowCard(workflow)
                        }
                    }
                    .padding(8)
                } label: {
                    Label("Common Workflows", systemImage: "point.3.filled.connected.trianglepath.dotted")
                }

                guideSection(
                    title: "Portfolio & Governance",
                    icon: "square.stack.3d.up",
                    lines: [
                        "Use `Portfolio` to register multiple plans, open one into the live workspace, and filter by health, approval, and archive state.",
                        "Populate workspace, program, sponsor, objective, stage, review date, review cadence, strategic alignment, and risk score so governance views are meaningful.",
                        "Use the portfolio summaries for executive ranking, roadmap milestones, cross-project dependencies, resource capacity, and recurring review snapshots."
                    ]
                )

                guideSection(
                    title: "Build a Plan",
                    icon: "square.and.pencil",
                    lines: [
                        "Use `Plan Builder` for fast grid entry and detailed task editing.",
                        "Use `Agile Board` when you need backlog, sprint, board-status, and story-point views on the same native plan.",
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
                    title: "Import Coverage",
                    icon: "tablecells",
                    lines: AppHelpCatalog.importCoverage
                )

                guideSection(
                    title: "Status & Control",
                    icon: "checklist",
                    lines: [
                        "Use `Status Center` to set status date, actual dates, progress, actual cost, assignment actual/remaining/overtime work, and capture reporting snapshots.",
                        "Use `Earned Value` for CPI, SPI, EAC, VAC, S-curve, and task-level EVM.",
                        "Use `Dashboard`, `Validation`, and `Diagnostics` to spot schedule-quality and resource-risk issues, then use `Agile Board` reports and `Portfolio` review snapshots for broader delivery and governance follow-up."
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
                        "Imported `.mpp` files are review-first documents. They feed analysis, dashboards, schedule views, read-only inspection screens, and portfolio rollups.",
                        isEditablePlan ? "This document is a native `.mppplan`, so plan creation, statusing, finance entry, resource editing, calendar editing, and agile workflows are available." : "Create a native `.mppplan` from `File > New` when you want in-app editing, imports, status updates, agile workflows, and native save/open later.",
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

    private func workflowCard(_ workflow: AppWorkflowGuide) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(workflow.title, systemImage: workflow.icon)
                .font(.headline)

            Text(workflow.summary)
                .foregroundStyle(.primary)

            ForEach(Array(workflow.steps.enumerated()), id: \.offset) { item in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(item.offset + 1).")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .leading)
                    Text(item.element)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
