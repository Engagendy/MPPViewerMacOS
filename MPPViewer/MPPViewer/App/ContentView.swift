import SwiftUI
import Combine

extension Notification.Name {
    static let navigateToItem = Notification.Name("navigateToItem")
}

enum NavigationItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case summary = "Summary"
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
        case .summary: return "doc.text"
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
            task.name?.lowercased().contains(search) == true ||
            task.wbs?.lowercased().contains(search) == true ||
            task.notes?.lowercased().contains(search) == true
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
        .searchable(text: $searchText, prompt: "Search tasks by name, WBS, or notes")
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
        case .summary:
            ProjectSummaryView(project: project)
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
            ResourceSheetView(resources: project.resources, assignments: project.assignments)
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
