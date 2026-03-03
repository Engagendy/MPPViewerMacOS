import SwiftUI

struct MilestonesView: View {
    let tasks: [ProjectTask]
    let allTasks: [Int: ProjectTask]
    let searchText: String

    @State private var selectedFilter: MilestoneFilter = .all
    @State private var sortOrder = [KeyPathComparator(\MilestoneItem.sortDate, order: .forward)]

    private var items: [MilestoneItem] {
        let filtered: [ProjectTask]
        switch selectedFilter {
        case .all:
            filtered = tasks.filter { $0.milestone == true || $0.summary == true }
        case .milestones:
            filtered = tasks.filter { $0.milestone == true }
        case .deliverables:
            filtered = tasks.filter { $0.summary == true }
        }

        let searched = searchText.isEmpty ? filtered : filtered.filter {
            $0.name?.lowercased().contains(searchText.lowercased()) == true
        }

        return searched.map { MilestoneItem(task: $0, allTasks: allTasks) }
            .sorted(using: sortOrder)
    }

    private var completedCount: Int {
        items.filter { $0.percentComplete >= 100 }.count
    }

    private var upcomingCount: Int {
        items.filter { $0.percentComplete < 100 && $0.date != nil && $0.date! >= Date() }.count
    }

    private var overdueCount: Int {
        items.filter { $0.percentComplete < 100 && $0.date != nil && $0.date! < Date() }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Milestones & Deliverables")
                    .font(.headline)
                Text("(\(items.count) items)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Status summary chips
                HStack(spacing: 12) {
                    statusChip(count: completedCount, label: "Completed", color: .green)
                    statusChip(count: upcomingCount, label: "Upcoming", color: .blue)
                    statusChip(count: overdueCount, label: "Overdue", color: .red)
                }

                Divider().frame(height: 16)

                // Filter picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(MilestoneFilter.allCases) { filter in
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

            if items.isEmpty {
                ContentUnavailableView(
                    "No Milestones",
                    systemImage: "diamond",
                    description: Text(searchText.isEmpty ? "This project has no milestones or deliverables." : "No items match your search.")
                )
            } else {
                Table(items, sortOrder: $sortOrder) {
                    TableColumn("Type") { item in
                        HStack(spacing: 4) {
                            if item.isMilestone {
                                Image(systemName: "diamond.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text("Milestone")
                            } else {
                                Image(systemName: "folder.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                Text("Deliverable")
                            }
                        }
                        .font(.caption)
                    }
                    .width(min: 80, ideal: 100, max: 120)

                    TableColumn("ID", value: \.taskID) { item in
                        Text(item.taskID)
                            .monospacedDigit()
                    }
                    .width(min: 30, ideal: 50, max: 60)

                    TableColumn("Name", value: \.name) { item in
                        Text(item.name)
                            .fontWeight(item.isMilestone ? .regular : .semibold)
                            .foregroundStyle(item.isCritical ? .red : .primary)
                            .lineLimit(2)
                    }
                    .width(min: 200, ideal: 300)

                    TableColumn("Date", value: \.sortDate) { item in
                        if let date = item.date {
                            Text(date, style: .date)
                                .foregroundStyle(item.isOverdue ? .red : .primary)
                        }
                    }
                    .width(min: 80, ideal: 100, max: 120)

                    TableColumn("Status") { item in
                        statusBadge(for: item)
                    }
                    .width(min: 80, ideal: 100, max: 120)

                    TableColumn("% Complete", value: \.percentComplete) { item in
                        HStack(spacing: 6) {
                            ProgressView(value: item.percentComplete, total: 100)
                                .frame(width: 50)
                            Text("\(Int(item.percentComplete))%")
                                .monospacedDigit()
                                .font(.caption)
                        }
                    }
                    .width(min: 80, ideal: 110, max: 140)

                    TableColumn("Predecessors") { item in
                        Text(item.predecessorText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 100, max: 150)
                }
            }
        }
    }

    private func statusChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count)").fontWeight(.medium)
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func statusBadge(for item: MilestoneItem) -> some View {
        let (label, color) = item.statusInfo
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Supporting Types

enum MilestoneFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case milestones = "Milestones"
    case deliverables = "Deliverables"

    var id: String { rawValue }
}

struct MilestoneItem: Identifiable {
    let id: Int
    let taskID: String
    let name: String
    let date: Date?
    let finishDate: Date?
    let percentComplete: Double
    let isMilestone: Bool
    let isCritical: Bool
    let predecessorText: String
    let isOverdue: Bool

    var sortDate: Date {
        date ?? .distantFuture
    }

    var statusInfo: (String, Color) {
        if percentComplete >= 100 {
            return ("Completed", .green)
        } else if isOverdue {
            return ("Overdue", .red)
        } else if percentComplete > 0 {
            return ("In Progress", .blue)
        } else {
            return ("Not Started", .gray)
        }
    }

    init(task: ProjectTask, allTasks: [Int: ProjectTask]) {
        self.id = task.uniqueID
        self.taskID = task.id.map(String.init) ?? ""
        self.name = task.displayName
        self.isMilestone = task.milestone == true
        self.isCritical = task.critical == true
        self.percentComplete = task.percentComplete ?? 0

        let targetDate = task.milestone == true ? task.startDate : task.finishDate
        self.date = targetDate
        self.finishDate = task.finishDate

        let now = Calendar.current.startOfDay(for: Date())
        if let d = targetDate, percentComplete < 100 {
            self.isOverdue = d < now
        } else {
            self.isOverdue = false
        }

        if let preds = task.predecessors, !preds.isEmpty {
            self.predecessorText = preds.compactMap { rel -> String? in
                guard let predTask = allTasks[rel.targetTaskUniqueID] else { return nil }
                let tid = predTask.id.map(String.init) ?? "\(rel.targetTaskUniqueID)"
                let suffix = rel.type == "FS" ? "" : (rel.type ?? "")
                return tid + suffix
            }.joined(separator: ", ")
        } else {
            self.predecessorText = ""
        }
    }
}

extension MilestoneItem: Comparable {
    static func < (lhs: MilestoneItem, rhs: MilestoneItem) -> Bool {
        (lhs.date ?? .distantFuture) < (rhs.date ?? .distantFuture)
    }
}
