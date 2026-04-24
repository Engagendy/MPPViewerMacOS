import SwiftUI

struct MilestonesView: View {
    let tasks: [ProjectTask]
    let allTasks: [Int: ProjectTask]
    let searchText: String

    @State private var preparedItems: [MilestoneItem]
    @State private var sortOrder = [KeyPathComparator(\MilestoneItem.sortDate, order: .forward)]

    private var items: [MilestoneItem] {
        preparedItems.sorted(using: sortOrder)
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

    private var atRiskCount: Int {
        items.filter { $0.healthLevel == .high || $0.healthLevel == .medium }.count
    }

    init(tasks: [ProjectTask], allTasks: [Int: ProjectTask], searchText: String) {
        self.tasks = tasks
        self.allTasks = allTasks
        self.searchText = searchText
        self._preparedItems = State(initialValue: Self.buildItems(tasks: tasks, allTasks: allTasks, searchText: searchText))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Milestones")
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
                    statusChip(count: atRiskCount, label: "At Risk", color: .orange)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if items.isEmpty {
                ContentUnavailableView(
                    "No Milestones",
                    systemImage: "diamond",
                    description: Text(searchText.isEmpty ? "This project has no explicit milestones." : "No items match your search.")
                )
            } else {
                Table(items, sortOrder: $sortOrder) {
                    TableColumn("") { _ in
                        Image(systemName: "diamond.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    .width(min: 24, ideal: 28, max: 32)

                    TableColumn("ID", value: \.taskID) { item in
                        Text(item.taskID)
                            .monospacedDigit()
                    }
                    .width(min: 30, ideal: 50, max: 60)

                    TableColumn("Name", value: \.name) { item in
                        Text(item.name)
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

                    TableColumn("Baseline") { item in
                        Text(item.baselineText)
                            .font(.caption)
                            .foregroundStyle(item.healthColor)
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

                    TableColumn("Health") { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.healthLabel)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(item.healthColor)
                            Text(item.healthReason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .width(min: 220, ideal: 320)
                }
            }
        }
        .onAppear {
            preparedItems = Self.buildItems(tasks: tasks, allTasks: allTasks, searchText: searchText)
        }
        .onChange(of: searchText) { _, newValue in
            preparedItems = Self.buildItems(tasks: tasks, allTasks: allTasks, searchText: newValue)
        }
    }

    private static func buildItems(tasks: [ProjectTask], allTasks: [Int: ProjectTask], searchText: String) -> [MilestoneItem] {
        let normalizedSearch = searchText.lowercased()
        let searched = searchText.isEmpty ? tasks.filter { $0.isDisplayMilestone } : tasks.filter {
            $0.isDisplayMilestone &&
            $0.name?.lowercased().contains(normalizedSearch) == true
        }

        return searched.map { MilestoneItem(task: $0, allTasks: allTasks) }
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

struct MilestoneItem: Identifiable {
    let id: Int
    let taskID: String
    let name: String
    let date: Date?
    let finishDate: Date?
    let percentComplete: Double
    let isCritical: Bool
    let predecessorText: String
    let isOverdue: Bool
    let baselineVarianceDays: Int?
    let blockedPredecessorCount: Int
    let healthReason: String
    let healthLevel: HealthLevel

    var sortDate: Date {
        date ?? .distantFuture
    }

    var baselineText: String {
        guard let baselineVarianceDays else { return "No baseline" }
        if baselineVarianceDays == 0 { return "On baseline" }
        return "\(baselineVarianceDays > 0 ? "+" : "")\(baselineVarianceDays)d"
    }

    var healthLabel: String {
        switch healthLevel {
        case .low:
            return "Stable"
        case .medium:
            return "Watch"
        case .high:
            return "Risk"
        }
    }

    var healthColor: Color {
        switch healthLevel {
        case .low:
            return .green
        case .medium:
            return .orange
        case .high:
            return .red
        }
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
        self.isCritical = task.critical == true
        self.percentComplete = task.percentComplete ?? 0

        let targetDate = task.startDate
        self.date = targetDate
        self.finishDate = task.finishDate

        let now = Calendar.current.startOfDay(for: Date())
        if let d = targetDate, percentComplete < 100 {
            self.isOverdue = d < now
        } else {
            self.isOverdue = false
        }
        self.baselineVarianceDays = task.finishVarianceDays ?? task.startVarianceDays

        let predecessorTasks = (task.predecessors ?? []).compactMap { allTasks[$0.targetTaskUniqueID] }
        let incompletePredecessors = predecessorTasks.filter { !$0.isCompleted }
        self.blockedPredecessorCount = incompletePredecessors.count

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

        let slippedDays = max(0, baselineVarianceDays ?? 0)
        let latePredecessorNames = incompletePredecessors
            .filter { ($0.finishDate ?? .distantPast) < now || ($0.finishDate ?? .distantPast) > (targetDate ?? .distantFuture) }
            .map(\.displayName)

        if percentComplete >= 100 {
            self.healthLevel = .low
            self.healthReason = "Milestone is complete."
        } else if !latePredecessorNames.isEmpty {
            self.healthLevel = .high
            self.healthReason = "Blocked by predecessor: \(latePredecessorNames.prefix(2).joined(separator: ", "))"
        } else if isOverdue && blockedPredecessorCount > 0 {
            self.healthLevel = .high
            self.healthReason = "Past due and still waiting on \(blockedPredecessorCount) predecessor(s)."
        } else if isOverdue && percentComplete == 0 {
            self.healthLevel = .high
            self.healthReason = "Target date passed with no progress recorded."
        } else if slippedDays > 0 {
            self.healthLevel = slippedDays >= 7 ? .high : .medium
            self.healthReason = "Slipped \(slippedDays) day(s) against the baseline."
        } else if blockedPredecessorCount > 0 {
            self.healthLevel = .medium
            self.healthReason = "Waiting on \(blockedPredecessorCount) predecessor task(s)."
        } else if percentComplete > 0 {
            self.healthLevel = .low
            self.healthReason = "Work has started and no active dependency block is visible."
        } else {
            self.healthLevel = .low
            self.healthReason = "No active blocker is visible from current dependencies."
        }
    }
}

enum HealthLevel {
    case low
    case medium
    case high
}

extension MilestoneItem: Comparable {
    static func < (lhs: MilestoneItem, rhs: MilestoneItem) -> Bool {
        (lhs.date ?? .distantFuture) < (rhs.date ?? .distantFuture)
    }
}
