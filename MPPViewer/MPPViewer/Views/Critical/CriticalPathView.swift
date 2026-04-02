import SwiftUI

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
                            LazyVStack(spacing: 8) {
                                ForEach(nearCriticalTasks.prefix(25)) { task in
                                    criticalRow(task, highlight: .orange)
                                    if task.uniqueID != nearCriticalTasks.prefix(25).last?.uniqueID {
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
                if let descriptor = task.baselineVarianceDescriptor, descriptor.days != 0 {
                    baselineBadge(descriptor)
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

    private func baselineBadge(_ descriptor: BaselineVarianceDescriptor) -> some View {
        Text(descriptor.label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(descriptor.color.opacity(0.2))
            )
            .foregroundStyle(descriptor.color)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(descriptor.color.opacity(0.6), lineWidth: 0.8)
            )
    }
}
