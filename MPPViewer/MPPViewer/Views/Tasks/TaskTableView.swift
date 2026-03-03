import SwiftUI

struct TaskTableView: View {
    let tasks: [ProjectTask]
    let allTasks: [Int: ProjectTask]
    let searchText: String

    @State private var collapsedIDs: Set<Int> = []

    var filteredTasks: [ProjectTask] {
        if searchText.isEmpty {
            return tasks
        }
        return filterTasks(tasks, searchText: searchText.lowercased())
    }

    var body: some View {
        if filteredTasks.isEmpty {
            ContentUnavailableView("No Tasks", systemImage: "list.bullet.indent", description: Text(searchText.isEmpty ? "This project has no tasks." : "No tasks match your search."))
        } else {
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Button("Expand All") {
                        collapsedIDs.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .disabled(collapsedIDs.isEmpty)

                    Button("Collapse All") {
                        for task in project_tasks(filteredTasks) where task.summary == true && !task.children.isEmpty {
                            collapsedIDs.insert(task.uniqueID)
                        }
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    // Legend
                    HStack(spacing: 14) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill").font(.caption2).foregroundStyle(.blue)
                            Text("Summary").font(.caption)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "diamond.fill").font(.caption2).foregroundStyle(.orange)
                            Text("Milestone").font(.caption)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("Critical").font(.caption)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(.primary).frame(width: 8, height: 8)
                            Text("Normal").font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                Table(of: ProjectTask.self) {
                    TableColumn("ID") { task in
                        Text(task.id.map(String.init) ?? "")
                            .monospacedDigit()
                    }
                    .width(min: 30, ideal: 50, max: 60)

                    TableColumn("WBS") { task in
                        Text(task.wbs ?? "")
                            .monospacedDigit()
                    }
                    .width(min: 40, ideal: 60, max: 80)

                    TableColumn("Name") { task in
                        let isSummaryWithChildren = task.summary == true && !task.children.isEmpty
                        let isCollapsed = collapsedIDs.contains(task.uniqueID)

                        HStack(spacing: 4) {
                            let indent = CGFloat((task.outlineLevel ?? 1) - 1) * 16
                            Spacer().frame(width: max(0, indent))

                            if isSummaryWithChildren {
                                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 12)

                                Image(systemName: "folder.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            } else if task.milestone == true {
                                Spacer().frame(width: 16)
                                Image(systemName: "diamond.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            } else {
                                Spacer().frame(width: 16)
                            }

                            Text(task.displayName)
                                .fontWeight(task.summary == true ? .semibold : .regular)
                                .foregroundStyle(task.critical == true ? .red : .primary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSummaryWithChildren {
                                if isCollapsed {
                                    collapsedIDs.remove(task.uniqueID)
                                } else {
                                    collapsedIDs.insert(task.uniqueID)
                                }
                            }
                        }
                        .cursor(isSummaryWithChildren ? .pointingHand : .arrow)
                    }
                    .width(min: 200, ideal: 350)

                    TableColumn("Duration") { task in
                        Text(task.durationDisplay)
                    }
                    .width(min: 60, ideal: 90, max: 120)

                    TableColumn("Start") { task in
                        Text(DateFormatting.shortDate(task.start))
                    }
                    .width(min: 70, ideal: 90, max: 110)

                    TableColumn("Finish") { task in
                        Text(DateFormatting.shortDate(task.finish))
                    }
                    .width(min: 70, ideal: 90, max: 110)

                    TableColumn("% Complete") { task in
                        HStack(spacing: 6) {
                            let pct = task.percentComplete ?? 0
                            ProgressView(value: pct, total: 100)
                                .frame(width: 50)
                            Text(task.percentCompleteDisplay)
                                .monospacedDigit()
                                .font(.caption)
                        }
                    }
                    .width(min: 80, ideal: 110, max: 140)

                    TableColumn("Predecessors") { task in
                        if let preds = task.predecessors, !preds.isEmpty {
                            let predText = preds.compactMap { rel -> String? in
                                guard let predTask = allTasks[rel.targetTaskUniqueID] else { return nil }
                                let taskID = predTask.id.map(String.init) ?? "\(rel.targetTaskUniqueID)"
                                let suffix = rel.type == "FS" ? "" : (rel.type ?? "")
                                return taskID + suffix
                            }.joined(separator: ", ")
                            Text(predText)
                                .font(.caption)
                        }
                    }
                    .width(min: 60, ideal: 100, max: 150)
                } rows: {
                    ForEach(visibleTasks) { task in
                        TableRow(task)
                    }
                }
            }
        }
    }

    private var visibleTasks: [ProjectTask] {
        flattenTasks(filteredTasks, collapsedIDs: collapsedIDs)
    }

    private func flattenTasks(_ tasks: [ProjectTask], collapsedIDs: Set<Int>) -> [ProjectTask] {
        var result: [ProjectTask] = []
        for task in tasks {
            result.append(task)
            if !task.children.isEmpty && !collapsedIDs.contains(task.uniqueID) {
                result.append(contentsOf: flattenTasks(task.children, collapsedIDs: collapsedIDs))
            }
        }
        return result
    }

    /// Collects all tasks recursively (for "Collapse All")
    private func project_tasks(_ tasks: [ProjectTask]) -> [ProjectTask] {
        var result: [ProjectTask] = []
        for task in tasks {
            result.append(task)
            if !task.children.isEmpty {
                result.append(contentsOf: project_tasks(task.children))
            }
        }
        return result
    }

    private func filterTasks(_ tasks: [ProjectTask], searchText: String) -> [ProjectTask] {
        var result: [ProjectTask] = []
        for task in tasks {
            let childMatches = filterTasks(task.children, searchText: searchText)
            let selfMatches = task.name?.lowercased().contains(searchText) == true

            if selfMatches || !childMatches.isEmpty {
                result.append(task)
            }
        }
        return result
    }
}
