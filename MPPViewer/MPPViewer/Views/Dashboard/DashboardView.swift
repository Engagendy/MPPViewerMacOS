import SwiftUI

struct DashboardView: View {
    let project: ProjectModel

    @State private var stats: ProjectStats?

    var body: some View {
        Group {
            if let stats = stats {
                dashboardContent(stats: stats)
            } else {
                ProgressView("Loading dashboard...")
            }
        }
        .task {
            let computed = ProjectStats(project: project)
            stats = computed
        }
    }

    private func dashboardContent(stats: ProjectStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Top KPI Cards
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                ], spacing: 16) {
                    KPICard(
                        title: "Overall Progress",
                        value: "\(stats.overallPercent)%",
                        subtitle: "\(stats.completedTasks) of \(stats.totalWorkTasks) tasks done",
                        icon: "chart.pie.fill",
                        color: stats.overallPercent >= 75 ? .green : stats.overallPercent >= 40 ? .blue : .orange,
                        progress: Double(stats.overallPercent) / 100.0
                    )

                    KPICard(
                        title: "On Track",
                        value: "\(stats.onTrackTasks)",
                        subtitle: "\(stats.behindTasks) behind schedule",
                        icon: "checkmark.circle.fill",
                        color: stats.behindTasks == 0 ? .green : .orange
                    )

                    KPICard(
                        title: "Critical Tasks",
                        value: "\(stats.criticalTasks)",
                        subtitle: "\(stats.criticalIncompleteTasks) incomplete",
                        icon: "exclamationmark.triangle.fill",
                        color: stats.criticalIncompleteTasks > 0 ? .red : .green
                    )

                    KPICard(
                        title: "Total Cost",
                        value: stats.totalCostFormatted,
                        subtitle: "across \(stats.totalWorkTasks) tasks",
                        icon: "dollarsign.circle.fill",
                        color: .blue
                    )
                }

                // EVM KPI Row
                if stats.evmMetrics.bac > 0 {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16),
                    ], spacing: 16) {
                        KPICard(
                            title: "Cost Performance (CPI)",
                            value: String(format: "%.2f", stats.evmMetrics.cpi),
                            subtitle: stats.evmMetrics.cpi >= 1.0 ? "Under budget" : "Over budget",
                            icon: "dollarsign.circle.fill",
                            color: stats.evmMetrics.cpi >= 1.0 ? .green : .red
                        )
                        KPICard(
                            title: "Schedule Performance (SPI)",
                            value: String(format: "%.2f", stats.evmMetrics.spi),
                            subtitle: stats.evmMetrics.spi >= 1.0 ? "Ahead of schedule" : "Behind schedule",
                            icon: "clock.fill",
                            color: stats.evmMetrics.spi >= 1.0 ? .green : .red
                        )
                    }
                }

                // Second Row
                HStack(alignment: .top, spacing: 16) {
                    // Task Status Breakdown
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Task Status")
                                .font(.headline)

                            StatusBar(segments: [
                                StatusSegment(label: "Completed", count: stats.completedTasks, color: .green),
                                StatusSegment(label: "In Progress", count: stats.inProgressTasks, color: .blue),
                                StatusSegment(label: "Not Started", count: stats.notStartedTasks, color: .gray),
                                StatusSegment(label: "Overdue", count: stats.overdueTasks, color: .red),
                            ], total: stats.totalWorkTasks)

                            Divider()

                            HStack(spacing: 20) {
                                statusLegend("Completed", count: stats.completedTasks, color: .green)
                                statusLegend("In Progress", count: stats.inProgressTasks, color: .blue)
                                statusLegend("Not Started", count: stats.notStartedTasks, color: .gray)
                                statusLegend("Overdue", count: stats.overdueTasks, color: .red)
                            }
                        }
                        .padding(4)
                    }

                    // Milestones
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Upcoming Milestones")
                                .font(.headline)

                            if stats.upcomingMilestones.isEmpty {
                                Text("No upcoming milestones")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(stats.upcomingMilestones, id: \.uniqueID) { task in
                                    HStack {
                                        Image(systemName: "diamond.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                        Text(task.displayName)
                                            .lineLimit(1)
                                        Spacer()
                                        if let date = task.startDate {
                                            Text(date, style: .date)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        milestoneBadge(for: task)
                                    }
                                    .font(.caption)

                                    if task.uniqueID != stats.upcomingMilestones.last?.uniqueID {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding(4)
                    }
                }

                // Third Row
                HStack(alignment: .top, spacing: 16) {
                    // Resource Summary
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Resources")
                                .font(.headline)

                            let workResources = project.resources.filter { $0.type == "work" || $0.type == nil }
                            let materialResources = project.resources.filter { $0.type == "material" }

                            HStack(spacing: 24) {
                                VStack {
                                    Text("\(project.resources.count)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Text("Total")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                VStack {
                                    Text("\(workResources.count)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.blue)
                                    Text("Work")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                VStack {
                                    Text("\(materialResources.count)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.orange)
                                    Text("Material")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                VStack {
                                    Text("\(project.assignments.count)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.green)
                                    Text("Assignments")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Schedule Health
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Schedule")
                                .font(.headline)

                            if let start = project.properties.startDate {
                                infoRow("Project Start", value: DateFormatting.mediumDateTime(start))
                            }
                            if let finish = project.properties.finishDate {
                                infoRow("Project Finish", value: DateFormatting.mediumDateTime(finish))
                            }
                            infoRow("Duration", value: stats.projectDurationText)
                            infoRow("Days Remaining", value: stats.daysRemainingText)
                            if stats.projectDurationDays > 0 {
                                ProgressView(value: Double(stats.daysElapsed), total: Double(stats.projectDurationDays))
                                    .tint(stats.daysRemaining < 0 ? .red : .blue)
                            }
                        }
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } // end dashboardContent

    private func statusLegend(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count)").fontWeight(.medium)
            Text(label)
        }
        .font(.caption)
    }

    @ViewBuilder
    private func milestoneBadge(for task: ProjectTask) -> some View {
        let pct = task.percentComplete ?? 0
        let isOverdue: Bool = {
            guard let date = task.startDate, pct < 100 else { return false }
            return date < Calendar.current.startOfDay(for: Date())
        }()

        if pct >= 100 {
            Text("Done")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.green.opacity(0.15))
                .foregroundStyle(.green)
                .clipShape(Capsule())
        } else if isOverdue {
            Text("Overdue")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(Capsule())
        } else {
            Text("Pending")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.gray.opacity(0.15))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.caption)
    }
}

// MARK: - KPI Card

struct KPICard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    var progress: Double? = nil

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Spacer()
                }
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                if let progress = progress {
                    ProgressView(value: progress)
                        .tint(color)
                }
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(2)
        }
    }
}

// MARK: - Status Bar

struct StatusSegment {
    let label: String
    let count: Int
    let color: Color
}

struct StatusBar: View {
    let segments: [StatusSegment]
    let total: Int

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(segments.indices, id: \.self) { i in
                    let seg = segments[i]
                    if seg.count > 0 {
                        let width = max(4, geometry.size.width * CGFloat(seg.count) / CGFloat(max(1, total)))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(seg.color)
                            .frame(width: width)
                            .help("\(seg.label): \(seg.count)")
                    }
                }
            }
        }
        .frame(height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Project Stats

struct ProjectStats {
    let totalWorkTasks: Int
    let completedTasks: Int
    let inProgressTasks: Int
    let notStartedTasks: Int
    let overdueTasks: Int
    let onTrackTasks: Int
    let behindTasks: Int
    let criticalTasks: Int
    let criticalIncompleteTasks: Int
    let overallPercent: Int
    let totalCost: Double
    let upcomingMilestones: [ProjectTask]
    let projectDurationDays: Int
    let daysElapsed: Int
    let daysRemaining: Int
    let evmMetrics: EVMMetrics

    var totalCostFormatted: String {
        if totalCost == 0 { return "N/A" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: totalCost)) ?? "$\(Int(totalCost))"
    }

    var projectDurationText: String {
        if projectDurationDays <= 0 { return "N/A" }
        return "\(projectDurationDays) days"
    }

    var daysRemainingText: String {
        if daysRemaining < 0 {
            return "\(-daysRemaining) days overdue"
        } else if daysRemaining == 0 {
            return "Due today"
        }
        return "\(daysRemaining) days"
    }

    init(project: ProjectModel) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let workTasks = project.tasks.filter { $0.summary != true && $0.milestone != true }

        self.totalWorkTasks = workTasks.count

        self.completedTasks = workTasks.filter { ($0.percentComplete ?? 0) >= 100 }.count

        self.inProgressTasks = workTasks.filter {
            let pct = $0.percentComplete ?? 0
            return pct > 0 && pct < 100
        }.count

        let overdue = workTasks.filter {
            let pct = $0.percentComplete ?? 0
            guard pct < 100, let finish = $0.finishDate else { return false }
            return finish < today
        }
        self.overdueTasks = overdue.count

        let overdueIDs = Set(overdue.map { $0.uniqueID })
        self.notStartedTasks = workTasks.filter {
            ($0.percentComplete ?? 0) == 0 && !overdueIDs.contains($0.uniqueID)
        }.count

        self.behindTasks = overdueTasks
        self.onTrackTasks = totalWorkTasks - overdueTasks

        self.criticalTasks = project.tasks.filter { $0.critical == true }.count
        self.criticalIncompleteTasks = project.tasks.filter { $0.critical == true && ($0.percentComplete ?? 0) < 100 }.count

        let totalPct = workTasks.reduce(0.0) { $0 + ($1.percentComplete ?? 0) }
        self.overallPercent = workTasks.isEmpty ? 0 : Int(totalPct / Double(workTasks.count))

        self.totalCost = project.tasks.compactMap { $0.cost }.reduce(0, +)

        // Upcoming milestones: incomplete milestones with dates in the next 30 days
        self.upcomingMilestones = project.tasks
            .filter { $0.milestone == true }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            .prefix(8)
            .map { $0 }

        // Project duration
        let allStarts = project.tasks.compactMap { $0.startDate }
        let allFinishes = project.tasks.compactMap { $0.finishDate }
        let projectStart = allStarts.min()
        let projectFinish = allFinishes.max()

        if let start = projectStart, let finish = projectFinish {
            self.projectDurationDays = max(1, calendar.dateComponents([.day], from: start, to: finish).day ?? 0)
            self.daysElapsed = max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
            self.daysRemaining = calendar.dateComponents([.day], from: today, to: finish).day ?? 0
        } else {
            self.projectDurationDays = 0
            self.daysElapsed = 0
            self.daysRemaining = 0
        }

        // EVM
        let statusDate: Date = {
            if let sd = project.properties.statusDate {
                return DateFormatting.parseMPXJDate(sd) ?? today
            }
            return today
        }()
        self.evmMetrics = EVMCalculator.projectMetrics(tasks: project.tasks, statusDate: statusDate)
    }
}
