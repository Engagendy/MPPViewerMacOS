import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case summary = "Summary"
    case tasks = "Tasks"
    case gantt = "Gantt Chart"
    case schedule = "Schedule"
    case milestones = "Milestones"
    case resources = "Resources"
    case calendar = "Calendar"

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
        case .calendar: return "calendar"
        }
    }
}

struct ContentView: View {
    let document: MPPDocument
    @StateObject private var store = ProjectStore()
    @State private var selectedNav: NavigationItem? = .dashboard
    @State private var searchText = ""

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
        .searchable(text: $searchText, prompt: "Filter tasks by name")
        .navigationTitle(store.project?.properties.projectTitle ?? "MPP Viewer")
        .task {
            await store.loadFromDocument(document)
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
            TaskTableView(tasks: project.rootTasks, allTasks: project.tasksByID, searchText: searchText, resources: project.resources, assignments: project.assignments)
        case .gantt:
            GanttChartView(project: project, searchText: searchText)
        case .schedule:
            ScheduleView(project: project, searchText: searchText)
        case .milestones:
            MilestonesView(tasks: project.tasks, allTasks: project.tasksByID, searchText: searchText)
        case .resources:
            ResourceSheetView(resources: project.resources, assignments: project.assignments)
        case .calendar:
            CalendarView(calendars: project.calendars)
        case .none:
            Text("Select a view from the sidebar")
                .foregroundStyle(.secondary)
        }
    }
}
