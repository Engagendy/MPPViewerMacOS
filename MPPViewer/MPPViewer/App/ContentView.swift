import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let navigateToItem = Notification.Name("navigateToItem")
}

enum NavigationItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case executive = "Executive Mode"
    case summary = "Summary"
    case validation = "Validation"
    case diagnostics = "Diagnostics"
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

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .executive: return "display"
        case .summary: return "doc.text"
        case .validation: return "checklist.unchecked"
        case .diagnostics: return "stethoscope"
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
        }
    }
}

struct ContentView: View {
    let document: MPPDocument
    @StateObject private var store = ProjectStore()
    @State private var selectedNav: NavigationItem? = .dashboard
    @State private var searchText = ""
    @State private var navigateToTaskID: Int?
    @AppStorage("flaggedTaskIDs") private var flaggedTaskIDsData: Data = Data()

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
        guard let project = store.project, !searchText.isEmpty else { return [] }
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

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedNav)
        } detail: {
            Group {
                if store.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Converting MPP file...")
                            .foregroundStyle(.secondary)
                    }
                } else if let error = store.error {
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
                } else if let project = store.project {
                    detailView(for: selectedNav, project: project)
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
        .navigationTitle(store.project?.properties.projectTitle ?? "MPP Viewer")
        .task {
            await store.loadFromDocument(document)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToItem)) { notification in
            if let item = notification.object as? NavigationItem {
                selectedNav = item
            }
        }
    }

    @ViewBuilder
    private func detailView(for item: NavigationItem?, project: ProjectModel) -> some View {
        switch item {
        case .dashboard:
            DashboardView(project: project)
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
            GanttChartView(project: project, searchText: searchText)
        case .schedule:
            ScheduleView(project: project, searchText: searchText)
        case .milestones:
            MilestonesView(tasks: project.tasks, allTasks: project.tasksByID, searchText: searchText)
        case .resources:
            ResourceSheetView(
                resources: project.resources,
                assignments: project.assignments,
                allTasks: project.tasksByID,
                navigateToTaskID: $navigateToTaskID,
                selectedNav: $selectedNav
            )
        case .earnedValue:
            EarnedValueView(project: project)
        case .workload:
            WorkloadView(project: project)
        case .calendar:
            CalendarView(calendars: project.calendars)
        case .timeline:
            TimelineView(project: project)
        case .diff:
            DiffView(project: project)
        case .none:
            Text("Select a view from the sidebar")
                .foregroundStyle(.secondary)
        }
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
                    TableColumn("Severity") { item in
                        Label(item.severity.label, systemImage: item.severity.icon)
                            .foregroundStyle(item.severity.color)
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
