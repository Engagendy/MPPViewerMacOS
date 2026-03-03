import SwiftUI

struct TaskDetailView: View {
    let task: ProjectTask
    let allTasks: [Int: ProjectTask]
    let resources: [ProjectResource]
    let assignments: [ResourceAssignment]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                header

                Divider()

                // General Info
                GroupBox("General") {
                    detailGrid {
                        detailRow("ID", value: task.id.map(String.init))
                        detailRow("WBS", value: task.wbs)
                        detailRow("Outline Level", value: task.outlineLevel.map(String.init))
                        detailRow("Type", value: taskTypeLabel)
                        detailRow("Priority", value: task.priority.map(String.init))
                        detailRow("Active", value: task.active.map { $0 ? "Yes" : "No" })
                        detailRow("GUID", value: task.guid)
                    }
                }

                // Schedule
                GroupBox("Schedule") {
                    detailGrid {
                        detailRow("Start", value: DateFormatting.mediumDateTime(task.start))
                        detailRow("Finish", value: DateFormatting.mediumDateTime(task.finish))
                        detailRow("Actual Start", value: DateFormatting.mediumDateTime(task.actualStart))
                        detailRow("Actual Finish", value: DateFormatting.mediumDateTime(task.actualFinish))
                        detailRow("Duration", value: task.durationDisplay)
                        detailRow("Actual Duration", value: task.actualDuration.map { DurationFormatting.formatSeconds($0) })
                        detailRow("Remaining Duration", value: task.remainingDuration.map { DurationFormatting.formatSeconds($0) })
                        detailRow("Constraint", value: task.constraintType)
                        detailRow("Constraint Date", value: DateFormatting.mediumDateTime(task.constraintDate))
                    }
                }

                // Progress
                GroupBox("Progress") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let pct = task.percentComplete {
                            HStack {
                                Text("% Complete")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 120, alignment: .trailing)
                                ProgressView(value: pct, total: 100)
                                    .frame(width: 100)
                                Text("\(Int(pct))%")
                                    .fontWeight(.medium)
                            }
                            .font(.caption)
                        }
                        if let pctWork = task.percentWorkComplete {
                            detailRow("% Work Complete", value: "\(Int(pctWork))%")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(2)
                }

                // Cost & Work
                if task.cost != nil || task.work != nil {
                    GroupBox("Cost & Work") {
                        detailGrid {
                            if let cost = task.cost {
                                let formatter = NumberFormatter()
                                let _ = (formatter.numberStyle = .currency)
                                detailRow("Cost", value: formatter.string(from: NSNumber(value: cost)))
                            }
                            if let work = task.work {
                                detailRow("Work", value: DurationFormatting.formatSeconds(work))
                            }
                        }
                    }
                }

                // Predecessors
                if let preds = task.predecessors, !preds.isEmpty {
                    GroupBox("Predecessors") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(preds) { rel in
                                relationRow(rel, label: "from")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(2)
                    }
                }

                // Successors
                if let succs = task.successors, !succs.isEmpty {
                    GroupBox("Successors") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(succs) { rel in
                                relationRow(rel, label: "to")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(2)
                    }
                }

                // Assigned Resources
                let taskAssignments = assignments.filter { $0.taskUniqueID == task.uniqueID }
                if !taskAssignments.isEmpty {
                    GroupBox("Assigned Resources") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(taskAssignments, id: \.id) { assignment in
                                let resourceName = resources
                                    .first(where: { $0.uniqueID == assignment.resourceUniqueID })?
                                    .name ?? "Resource \(assignment.resourceUniqueID ?? 0)"
                                HStack {
                                    Image(systemName: "person.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                    Text(resourceName)
                                    Spacer()
                                    if let units = assignment.assignmentUnits {
                                        Text("\(Int(units * 100))%")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(2)
                    }
                }

                // Notes
                if let notes = task.notes, !notes.isEmpty {
                    GroupBox("Notes") {
                        Text(notes)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(2)
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if task.summary == true {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                } else if task.milestone == true {
                    Image(systemName: "diamond.fill")
                        .foregroundStyle(.orange)
                }
                if task.critical == true {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            Text(task.displayName)
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                if task.milestone == true {
                    badge("Milestone", color: .orange)
                }
                if task.summary == true {
                    badge("Summary", color: .blue)
                }
                if task.critical == true {
                    badge("Critical", color: .red)
                }
                if (task.percentComplete ?? 0) >= 100 {
                    badge("Completed", color: .green)
                }
            }
        }
    }

    private func badge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Helpers

    private var taskTypeLabel: String {
        if task.milestone == true { return "Milestone" }
        if task.summary == true { return "Summary" }
        return task.type ?? "Task"
    }

    @ViewBuilder
    private func detailGrid(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(2)
    }

    @ViewBuilder
    private func detailRow(_ label: String, value: String?) -> some View {
        if let value = value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .trailing)
                Text(value)
                    .textSelection(.enabled)
            }
            .font(.caption)
        }
    }

    private func relationRow(_ rel: TaskRelation, label: String) -> some View {
        let targetTask = allTasks[rel.targetTaskUniqueID]
        let taskName = targetTask?.displayName ?? "Task \(rel.targetTaskUniqueID)"
        let taskID = targetTask?.id.map(String.init) ?? "\(rel.targetTaskUniqueID)"
        let relType = rel.type ?? "FS"
        let lagText = rel.lag.map { $0 != 0 ? " (\(DurationFormatting.formatSeconds($0)) lag)" : "" } ?? ""

        return HStack {
            Text("\(taskID)")
                .fontWeight(.medium)
            Text(taskName)
            Spacer()
            Text("\(relType)\(lagText)")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
