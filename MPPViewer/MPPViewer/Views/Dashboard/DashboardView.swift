import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum DashboardAudiencePreset: String, CaseIterable, Identifiable, Codable {
    case projectManager = "Project Manager"
    case executive = "Executive"
    case scheduler = "Scheduler"
    case resourceManager = "Resource Manager"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .projectManager: return "checklist"
        case .executive: return "display"
        case .scheduler: return "calendar.badge.clock"
        case .resourceManager: return "person.3.sequence"
        }
    }

    var summary: String {
        switch self {
        case .projectManager:
            return "Daily review for delivery status, critical tasks, milestones, and open follow-up items."
        case .executive:
            return "High-level health snapshot for progress, schedule exposure, and export-ready summary material."
        case .scheduler:
            return "Variance, milestone movement, and schedule-quality checks for keeping the plan defensible."
        case .resourceManager:
            return "Capacity, overload hotspots, assignments, and resource-risk triage for staffing decisions."
        }
    }

    var recommendedViews: [NavigationItem] {
        switch self {
        case .projectManager:
            return [.tasks, .milestones, .validation]
        case .executive:
            return [.executive, .dashboard, .diff]
        case .scheduler:
            return [.schedule, .gantt, .diagnostics]
        case .resourceManager:
            return [.resources, .resourceRisks, .workload]
        }
    }

    var recommendedExports: [String] {
        switch self {
        case .projectManager:
            return ["Review Pack", "Open Issues", "Issues CSV"]
        case .executive:
            return ["Executive Summary", "Review Pack"]
        case .scheduler:
            return ["Executive Summary", "Open Issues"]
        case .resourceManager:
            return ["Issues CSV", "Open Issues"]
        }
    }
}

private struct DashboardAudienceMetric: Identifiable {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    let progress: Double?

    var id: String { title }
}

private enum DashboardWidget: String, CaseIterable, Codable, Identifiable {
    case baselineAlert = "Baseline Alert"
    case topKPIs = "Top KPI Cards"
    case evm = "EVM Metrics"
    case taskStatus = "Task Status"
    case milestones = "Milestones"
    case resourceSummary = "Resource Summary"
    case scheduleHealth = "Schedule Health"
    case baselineAnalysis = "Baseline Analysis"

    var id: String { rawValue }
}

private enum DashboardTaskScope: String, CaseIterable, Codable, Identifiable {
    case allWork = "All Work"
    case criticalOnly = "Critical Only"
    case behindSchedule = "Behind Schedule"

    var id: String { rawValue }
}

private struct DashboardAudienceConfiguration: Codable {
    var visibleWidgets: [DashboardWidget]
    var taskScope: DashboardTaskScope
    var milestoneLimit: Int

    static func `default`(for preset: DashboardAudiencePreset) -> DashboardAudienceConfiguration {
        switch preset {
        case .projectManager:
            return DashboardAudienceConfiguration(
                visibleWidgets: [.baselineAlert, .topKPIs, .evm, .taskStatus, .milestones, .resourceSummary, .scheduleHealth, .baselineAnalysis],
                taskScope: .allWork,
                milestoneLimit: 8
            )
        case .executive:
            return DashboardAudienceConfiguration(
                visibleWidgets: [.baselineAlert, .topKPIs, .milestones, .scheduleHealth, .baselineAnalysis],
                taskScope: .criticalOnly,
                milestoneLimit: 4
            )
        case .scheduler:
            return DashboardAudienceConfiguration(
                visibleWidgets: [.baselineAlert, .topKPIs, .taskStatus, .milestones, .scheduleHealth, .baselineAnalysis],
                taskScope: .behindSchedule,
                milestoneLimit: 8
            )
        case .resourceManager:
            return DashboardAudienceConfiguration(
                visibleWidgets: [.topKPIs, .taskStatus, .resourceSummary, .scheduleHealth],
                taskScope: .criticalOnly,
                milestoneLimit: 4
            )
        }
    }
}

private struct DashboardSnapshot: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let projectTitle: String
    let preset: DashboardAudiencePreset
    let configuration: DashboardAudienceConfiguration
    let headline: String
    let markdown: String
}

struct DashboardView: View {
    let project: ProjectModel

    @State private var stats: ProjectStats?
    @AppStorage(ReviewNotesStore.key) private var taskReviewNotesData: Data = Data()
    @AppStorage("dashboardAudiencePreset") private var audiencePresetRawValue = DashboardAudiencePreset.projectManager.rawValue
    @AppStorage("dashboardAudienceConfigurations") private var audienceConfigurationData: Data = Data()
    @AppStorage("dashboardSnapshots") private var snapshotData: Data = Data()
    @State private var isCustomizationExpanded = false
    @State private var selectedSnapshotID: UUID?

    private var audiencePreset: DashboardAudiencePreset {
        get { DashboardAudiencePreset(rawValue: audiencePresetRawValue) ?? .projectManager }
        nonmutating set { audiencePresetRawValue = newValue.rawValue }
    }

    private var currentAudienceConfiguration: DashboardAudienceConfiguration {
        decodeAudienceConfigurations()[audiencePreset.rawValue] ?? .default(for: audiencePreset)
    }

    private var snapshots: [DashboardSnapshot] {
        decodeSnapshots()
    }

    private var selectedSnapshot: DashboardSnapshot? {
        guard let selectedSnapshotID else { return snapshots.first }
        return snapshots.first(where: { $0.id == selectedSnapshotID }) ?? snapshots.first
    }

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
            if selectedSnapshotID == nil {
                selectedSnapshotID = snapshots.first?.id
            }
        }
    }

    private func dashboardContent(stats: ProjectStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                audienceDashboardSection(stats: stats)

                HStack {
                    Button {
                        saveAudienceSnapshot(stats: stats)
                    } label: {
                        Label("Save Snapshot", systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        exportAudienceDashboard(stats: stats)
                    } label: {
                        Label("Export Audience Dashboard", systemImage: "square.and.arrow.up.on.square")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        exportReviewPack()
                    } label: {
                        Label("Export Review Pack", systemImage: "doc.richtext")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        exportOpenIssues()
                    } label: {
                        Label("Export Open Issues", systemImage: "exclamationmark.bubble")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        exportOpenIssuesCSV()
                    } label: {
                        Label("Issues CSV", systemImage: "tablecells")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                    Button {
                        exportExecutiveSummary(stats: stats)
                    } label: {
                        Label("Export Summary", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                }

                if !snapshots.isEmpty {
                    snapshotSection
                }

                if currentAudienceConfiguration.visibleWidgets.contains(.baselineAlert) {
                    BaselineAlertView(stats: stats)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                }

                // Top KPI Cards
                if currentAudienceConfiguration.visibleWidgets.contains(.topKPIs) {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16),
                    ], spacing: 16) {
                        ForEach(audienceMetrics(stats: stats)) { metric in
                            KPICard(
                                title: metric.title,
                                value: metric.value,
                                subtitle: metric.subtitle,
                                icon: metric.icon,
                                color: metric.color,
                                progress: metric.progress
                            )
                        }
                    }
                }

                // EVM KPI Row
                if currentAudienceConfiguration.visibleWidgets.contains(.evm), stats.evmMetrics.bac > 0 {
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
                if currentAudienceConfiguration.visibleWidgets.contains(.taskStatus) || currentAudienceConfiguration.visibleWidgets.contains(.milestones) {
                    HStack(alignment: .top, spacing: 16) {
                        if currentAudienceConfiguration.visibleWidgets.contains(.taskStatus) {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(taskStatusTitle)
                                        .font(.headline)

                                    if filteredTaskTotal == 0 {
                                        Text("No tasks match the current dashboard filter.")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                            .padding(.vertical, 8)
                                    } else {
                                        StatusBar(segments: [
                                            StatusSegment(label: "Completed", count: filteredCompletedTasks, color: .green),
                                            StatusSegment(label: "In Progress", count: filteredInProgressTasks, color: .blue),
                                            StatusSegment(label: "Not Started", count: filteredNotStartedTasks, color: .gray),
                                            StatusSegment(label: "Overdue", count: filteredOverdueTasks, color: .red),
                                        ], total: filteredTaskTotal)

                                        Divider()

                                        HStack(spacing: 20) {
                                            statusLegend("Completed", count: filteredCompletedTasks, color: .green)
                                            statusLegend("In Progress", count: filteredInProgressTasks, color: .blue)
                                            statusLegend("Not Started", count: filteredNotStartedTasks, color: .gray)
                                            statusLegend("Overdue", count: filteredOverdueTasks, color: .red)
                                        }
                                    }
                                }
                                .padding(4)
                            }
                        }

                        if currentAudienceConfiguration.visibleWidgets.contains(.milestones) {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Upcoming Milestones")
                                        .font(.headline)

                                    if displayedMilestones(stats).isEmpty {
                                        Text("No upcoming milestones")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                            .padding(.vertical, 8)
                                    } else {
                                        ForEach(displayedMilestones(stats), id: \.uniqueID) { task in
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

                                            if task.uniqueID != displayedMilestones(stats).last?.uniqueID {
                                                Divider()
                                            }
                                        }
                                    }
                                }
                                .padding(4)
                            }
                        }
                    }
                }

                // Third Row
                if currentAudienceConfiguration.visibleWidgets.contains(.resourceSummary) || currentAudienceConfiguration.visibleWidgets.contains(.scheduleHealth) {
                    HStack(alignment: .top, spacing: 16) {
                        if currentAudienceConfiguration.visibleWidgets.contains(.resourceSummary) {
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
                        }

                        if currentAudienceConfiguration.visibleWidgets.contains(.scheduleHealth) {
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
                }

                if currentAudienceConfiguration.visibleWidgets.contains(.baselineAnalysis), stats.hasBaselineData {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Baseline Analysis")
                                    .font(.headline)
                                Spacer()
                                baselinePill("\(stats.baselineTrackedTasks) tracked", color: .blue)
                                baselinePill("\(stats.baselineSlippedTasks) slipped", color: stats.baselineSlippedTasks > 0 ? .red : .green)
                                baselinePill("\(stats.baselineOnPlanTasks) on plan", color: .green)
                            }

                            HStack(alignment: .top, spacing: 24) {
                                baselineStat("Ahead", "\(stats.baselineAheadTasks)", color: .blue)
                                baselineStat("On Baseline", "\(stats.baselineOnPlanTasks)", color: .green)
                                baselineStat("Late vs Baseline", "\(stats.baselineSlippedTasks)", color: .red)
                                baselineStat("Milestone Slips", "\(stats.baselineSlippedMilestones)", color: stats.baselineSlippedMilestones > 0 ? .orange : .green)
                            }

                            Divider()

                            infoRow("Average Finish Variance", value: stats.averageFinishVarianceText)
                            infoRow("Worst Finish Variance", value: stats.worstFinishVarianceText)
                            infoRow("Largest Slip Task", value: stats.worstFinishVarianceTaskName)
                        }
                        .padding(4)
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } // end dashboardContent

    private func audienceDashboardSection(stats: ProjectStats) -> some View {
        GroupBox("Audience Dashboard") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(audiencePreset.rawValue)
                            .font(.headline)
                        Text(audiencePreset.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(DashboardAudiencePreset.allCases) { preset in
                            Button {
                                audiencePreset = preset
                            } label: {
                                Label(preset.rawValue, systemImage: preset.icon)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(audiencePreset == preset ? dashboardTint(for: preset) : .secondary.opacity(0.35))
                        }
                    }
                }

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recommended Views")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(audiencePreset.recommendedViews, id: \.self) { item in
                                Button {
                                    NotificationCenter.default.post(name: .navigateToItem, object: item)
                                } label: {
                                    Label(item.rawValue, systemImage: item.icon)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recommended Exports")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(audiencePreset.recommendedExports, id: \.self) { export in
                                Text(export)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(dashboardTint(for: audiencePreset).opacity(0.12))
                                    .foregroundStyle(dashboardTint(for: audiencePreset))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                DisclosureGroup("Customize Layout", isExpanded: $isCustomizationExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Task Filter")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Task Filter", selection: taskScopeBinding) {
                                    ForEach(DashboardTaskScope.allCases) { scope in
                                        Text(scope.rawValue).tag(scope)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Milestone Count")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Milestone Count", selection: milestoneLimitBinding) {
                                    Text("4").tag(4)
                                    Text("8").tag(8)
                                    Text("12").tag(12)
                                }
                                .pickerStyle(.segmented)
                            }
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                            ForEach(DashboardWidget.allCases) { widget in
                                Toggle(widget.rawValue, isOn: widgetBinding(for: widget))
                            }
                        }

                        Button("Reset \(audiencePreset.rawValue) Layout") {
                            resetAudienceConfiguration()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }

                Text(audienceDetail(stats: stats))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    private var snapshotSection: some View {
        GroupBox("Saved Snapshots") {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(snapshots.count) saved review snapshots")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(snapshots.prefix(6)) { snapshot in
                        Button {
                            selectedSnapshotID = snapshot.id
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(snapshot.preset.rawValue)
                                        .fontWeight(.medium)
                                    Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(snapshot.headline)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedSnapshot?.id == snapshot.id ? dashboardTint(for: snapshot.preset).opacity(0.12) : Color.secondary.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 230, alignment: .leading)

                Divider()

                if let selectedSnapshot {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedSnapshot.projectTitle)
                                    .font(.headline)
                                Text("\(selectedSnapshot.preset.rawValue) · \(selectedSnapshot.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Apply Snapshot") {
                                applySnapshot(selectedSnapshot)
                            }
                            .buttonStyle(.bordered)

                            Button("Export Snapshot") {
                                exportSnapshot(selectedSnapshot)
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                deleteSnapshot(selectedSnapshot.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                        }

                        Text(selectedSnapshot.headline)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView {
                            Text(selectedSnapshot.markdown)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 180, maxHeight: 260)
                        .padding(10)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .padding(4)
        }
    }

    private func statusLegend(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count)").fontWeight(.medium)
            Text(label)
        }
        .font(.caption)
    }

    private func audienceMetrics(stats: ProjectStats) -> [DashboardAudienceMetric] {
        switch audiencePreset {
        case .projectManager:
            return [
                DashboardAudienceMetric(
                    title: "Average Task Progress",
                    value: "\(stats.averageProgressPercent)%",
                    subtitle: "\(stats.completedPercent)% of work tasks completed",
                    icon: "chart.pie.fill",
                    color: stats.averageProgressPercent >= 75 ? .green : stats.averageProgressPercent >= 40 ? .blue : .orange,
                    progress: Double(stats.averageProgressPercent) / 100.0
                ),
                DashboardAudienceMetric(
                    title: "On Track",
                    value: "\(stats.onTrackTasks)",
                    subtitle: "\(stats.behindTasks) behind schedule",
                    icon: "checkmark.circle.fill",
                    color: stats.behindTasks == 0 ? .green : .orange,
                    progress: nil
                ),
                DashboardAudienceMetric(
                    title: "Critical Tasks",
                    value: "\(stats.criticalTasks)",
                    subtitle: "\(stats.criticalIncompleteTasks) incomplete",
                    icon: "exclamationmark.triangle.fill",
                    color: stats.criticalIncompleteTasks > 0 ? .red : .green,
                    progress: nil
                ),
                DashboardAudienceMetric(
                    title: "Open Issues",
                    value: "\(unresolvedIssueCount)",
                    subtitle: "\(followUpIssueCount) flagged for follow-up",
                    icon: "exclamationmark.bubble.fill",
                    color: unresolvedIssueCount > 0 ? .orange : .green,
                    progress: nil
                )
            ]
        case .executive:
            return [
                DashboardAudienceMetric(
                    title: "Average Task Progress",
                    value: "\(stats.averageProgressPercent)%",
                    subtitle: "\(stats.completedPercent)% of work tasks completed",
                    icon: "chart.pie.fill",
                    color: stats.averageProgressPercent >= 75 ? .green : .blue,
                    progress: Double(stats.averageProgressPercent) / 100.0
                ),
                DashboardAudienceMetric(
                    title: "Schedule Position",
                    value: stats.daysRemainingText,
                    subtitle: "\(stats.overdueTasks) overdue tasks",
                    icon: "calendar.badge.clock",
                    color: stats.daysRemaining < 0 ? .red : .orange,
                    progress: nil
                ),
                DashboardAudienceMetric(
                    title: "Critical Incomplete",
                    value: "\(stats.criticalIncompleteTasks)",
                    subtitle: "\(stats.criticalTasks) total critical tasks",
                    icon: "exclamationmark.triangle.fill",
                    color: stats.criticalIncompleteTasks > 0 ? .red : .green,
                    progress: nil
                ),
                DashboardAudienceMetric(
                    title: "Total Cost",
                    value: stats.totalCostFormatted,
                    subtitle: "across \(stats.totalWorkTasks) tasks",
                    icon: "dollarsign.circle.fill",
                    color: .blue,
                    progress: nil
                )
            ]
        case .scheduler:
            return [
                DashboardAudienceMetric(
                    title: "Behind Schedule",
                    value: "\(stats.behindTasks)",
                    subtitle: "\(stats.onTrackTasks) currently on track",
                    icon: "clock.badge.exclamationmark",
                    color: stats.behindTasks > 0 ? .red : .green,
                    progress: nil
                ),
                DashboardAudienceMetric(
                    title: "Baseline Slips",
                    value: "\(stats.baselineSlippedTasks)",
                    subtitle: stats.hasBaselineData ? "\(stats.baselineTrackedTasks) tracked tasks" : "No baseline imported",
                    icon: "flag.pattern.checkered.2.crossed",
                    color: stats.baselineSlippedTasks > 0 ? .orange : .green,
                    progress: nil
                ),
                DashboardAudienceMetric(
                    title: "Milestones Ahead",
                    value: "\(stats.upcomingMilestones.count)",
                    subtitle: "next visible milestone commitments",
                    icon: "diamond.fill",
                    color: .orange,
                    progress: nil
                ),
                DashboardAudienceMetric(
                    title: "Worst Finish Variance",
                    value: stats.worstFinishVarianceText,
                    subtitle: stats.worstFinishVarianceTaskName,
                    icon: "arrow.trianglehead.2.clockwise.rotate.90",
                    color: (stats.worstFinishVarianceDays ?? 0) > 0 ? .red : .blue,
                    progress: nil
                )
            ]
        case .resourceManager:
            return [
                DashboardAudienceMetric(
                    title: "Work Resources",
                    value: "\(workResourceCount)",
                    subtitle: "\(project.assignments.count) assignments mapped",
                    icon: "person.2.fill",
                    color: .blue,
                    progress: nil
                ),
                DashboardAudienceMetric(
                    title: "Resource Risks",
                    value: "\(resourceRiskCount)",
                    subtitle: "\(resourceErrorCount) severe overload signals",
                    icon: "person.crop.circle.badge.exclamationmark",
                    color: resourceRiskCount > 0 ? .red : .green,
                    progress: nil
                ),
                DashboardAudienceMetric(
                    title: "Follow-Up Issues",
                    value: "\(followUpIssueCount)",
                    subtitle: "\(unresolvedIssueCount) unresolved total",
                    icon: "bubble.left.and.exclamationmark.bubble.right.fill",
                    color: followUpIssueCount > 0 ? .orange : .green,
                    progress: nil
                ),
                DashboardAudienceMetric(
                    title: "Total Cost",
                    value: stats.totalCostFormatted,
                    subtitle: "use with workload and assignment reviews",
                    icon: "dollarsign.circle.fill",
                    color: .blue,
                    progress: nil
                )
            ]
        }
    }

    private func audienceDetail(stats: ProjectStats) -> String {
        switch audiencePreset {
        case .projectManager:
            return "Focus on \(stats.criticalIncompleteTasks) incomplete critical tasks, \(stats.upcomingMilestones.count) upcoming milestones, and \(unresolvedIssueCount) unresolved review items before the next check-in."
        case .executive:
            return "This preset keeps the review centered on progress, finish risk, and export-ready materials for leadership updates."
        case .scheduler:
            return "Use this preset to move quickly from baseline drift and milestone pressure into schedule, Gantt, and diagnostics views."
        case .resourceManager:
            return "Use this preset to review \(resourceRiskCount) resource-risk signals, current overload patterns, and issue follow-up before changing staffing assumptions."
        }
    }

    private var taskStatusTitle: String {
        switch currentAudienceConfiguration.taskScope {
        case .allWork:
            return "Task Status"
        case .criticalOnly:
            return "Critical Task Status"
        case .behindSchedule:
            return "Behind Schedule Status"
        }
    }

    private var reviewAnnotations: [Int: TaskReviewAnnotation] {
        ReviewNotesStore.decodeAnnotations(taskReviewNotesData)
    }

    private var unresolvedIssueCount: Int {
        reviewAnnotations.values.filter(\.isUnresolved).count
    }

    private var followUpIssueCount: Int {
        reviewAnnotations.values.filter(\.needsFollowUp).count
    }

    private var workResourceCount: Int {
        project.resources.filter { $0.type == "work" || $0.type == nil }.count
    }

    private var resourceRiskCount: Int {
        ResourceDiagnostics.analyze(project: project).count
    }

    private var resourceErrorCount: Int {
        ResourceDiagnostics.analyze(project: project).filter { $0.severity == .error }.count
    }

    private func dashboardTint(for preset: DashboardAudiencePreset) -> Color {
        switch preset {
        case .projectManager: return .blue
        case .executive: return .indigo
        case .scheduler: return .orange
        case .resourceManager: return .green
        }
    }

    private var filteredWorkTasks: [ProjectTask] {
        let today = Calendar.current.startOfDay(for: Date())
        let workTasks = project.tasks.filter { $0.summary != true && $0.milestone != true }

        switch currentAudienceConfiguration.taskScope {
        case .allWork:
            return workTasks
        case .criticalOnly:
            return workTasks.filter { $0.critical == true }
        case .behindSchedule:
            return workTasks.filter {
                ($0.percentComplete ?? 0) < 100 &&
                ($0.finishDate?.compare(today) == .orderedAscending)
            }
        }
    }

    private var filteredTaskTotal: Int {
        filteredWorkTasks.count
    }

    private var filteredCompletedTasks: Int {
        filteredWorkTasks.filter { ($0.percentComplete ?? 0) >= 100 }.count
    }

    private var filteredInProgressTasks: Int {
        filteredWorkTasks.filter {
            let pct = $0.percentComplete ?? 0
            return pct > 0 && pct < 100
        }.count
    }

    private var filteredOverdueTasks: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return filteredWorkTasks.filter {
            ($0.percentComplete ?? 0) < 100 &&
            ($0.finishDate?.compare(today) == .orderedAscending)
        }.count
    }

    private var filteredNotStartedTasks: Int {
        let overdueIDs = Set(filteredWorkTasks.filter {
            ($0.percentComplete ?? 0) < 100 &&
            ($0.finishDate?.compare(Calendar.current.startOfDay(for: Date())) == .orderedAscending)
        }.map(\.uniqueID))

        return filteredWorkTasks.filter {
            ($0.percentComplete ?? 0) == 0 && !overdueIDs.contains($0.uniqueID)
        }.count
    }

    private func displayedMilestones(_ stats: ProjectStats) -> [ProjectTask] {
        Array(stats.upcomingMilestones.prefix(currentAudienceConfiguration.milestoneLimit))
    }

    private var taskScopeBinding: Binding<DashboardTaskScope> {
        Binding(
            get: { currentAudienceConfiguration.taskScope },
            set: { newValue in
                updateAudienceConfiguration { $0.taskScope = newValue }
            }
        )
    }

    private var milestoneLimitBinding: Binding<Int> {
        Binding(
            get: { currentAudienceConfiguration.milestoneLimit },
            set: { newValue in
                updateAudienceConfiguration { $0.milestoneLimit = newValue }
            }
        )
    }

    private func widgetBinding(for widget: DashboardWidget) -> Binding<Bool> {
        Binding(
            get: { currentAudienceConfiguration.visibleWidgets.contains(widget) },
            set: { isEnabled in
                updateAudienceConfiguration { configuration in
                    var widgets = configuration.visibleWidgets
                    if isEnabled {
                        if !widgets.contains(widget) {
                            widgets.append(widget)
                        }
                    } else if widgets.count > 1 {
                        widgets.removeAll { $0 == widget }
                    }
                    configuration.visibleWidgets = widgets
                }
            }
        )
    }

    private func resetAudienceConfiguration() {
        updateAudienceConfiguration { configuration in
            configuration = .default(for: audiencePreset)
        }
    }

    private func decodeAudienceConfigurations() -> [String: DashboardAudienceConfiguration] {
        guard !audienceConfigurationData.isEmpty else { return [:] }
        return (try? JSONDecoder().decode([String: DashboardAudienceConfiguration].self, from: audienceConfigurationData)) ?? [:]
    }

    private func updateAudienceConfiguration(_ update: (inout DashboardAudienceConfiguration) -> Void) {
        var configurations = decodeAudienceConfigurations()
        var configuration = configurations[audiencePreset.rawValue] ?? .default(for: audiencePreset)
        update(&configuration)
        configurations[audiencePreset.rawValue] = configuration
        audienceConfigurationData = (try? JSONEncoder().encode(configurations)) ?? Data()
    }

    private func decodeSnapshots() -> [DashboardSnapshot] {
        guard !snapshotData.isEmpty else { return [] }
        return (try? JSONDecoder().decode([DashboardSnapshot].self, from: snapshotData)) ?? []
    }

    private func persistSnapshots(_ snapshots: [DashboardSnapshot]) {
        snapshotData = (try? JSONEncoder().encode(snapshots)) ?? Data()
    }

    private func baselinePill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func baselineStat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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

    private func exportExecutiveSummary(stats: ProjectStats) {
        let validationIssues = ProjectValidator.validate(project: project)
        var lines: [String] = [
            "# \(project.properties.projectTitle ?? "Project") Executive Summary",
            "",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "",
            "## Headline Metrics",
            "- Average task progress: \(stats.averageProgressPercent)%",
            "- Completed-task ratio: \(stats.completedPercent)%",
            "- Total work tasks: \(stats.totalWorkTasks)",
            "- Completed tasks: \(stats.completedTasks)",
            "- In progress tasks: \(stats.inProgressTasks)",
            "- Overdue tasks: \(stats.overdueTasks)",
            "- Critical incomplete tasks: \(stats.criticalIncompleteTasks)",
            "- Days remaining: \(stats.daysRemainingText)",
            "- Total cost: \(stats.totalCostFormatted)",
            "",
            "## Validation Snapshot",
            "- Errors: \(validationIssues.filter { $0.severity == .error }.count)",
            "- Warnings: \(validationIssues.filter { $0.severity == .warning }.count)",
            "- Info: \(validationIssues.filter { $0.severity == .info }.count)",
            "",
            "## Upcoming Milestones",
        ]
        lines.append(contentsOf: milestoneSummaryLines(stats.upcomingMilestones))

        let markdown = lines.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Executive Summary \(PDFExporter.fileNameTimestamp).md"
        panel.allowedContentTypes = [UTType.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func exportAudienceDashboard(stats: ProjectStats) {
        let markdown = audienceDashboardMarkdown(stats: stats)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(audiencePreset.rawValue) Dashboard \(PDFExporter.fileNameTimestamp).md"
        panel.allowedContentTypes = [UTType.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func saveAudienceSnapshot(stats: ProjectStats) {
        let snapshot = DashboardSnapshot(
            id: UUID(),
            createdAt: Date(),
            projectTitle: project.properties.projectTitle ?? "Project",
            preset: audiencePreset,
            configuration: currentAudienceConfiguration,
            headline: audienceDetail(stats: stats),
            markdown: audienceDashboardMarkdown(stats: stats)
        )

        var storedSnapshots = snapshots
        storedSnapshots.insert(snapshot, at: 0)
        storedSnapshots = Array(storedSnapshots.prefix(12))
        persistSnapshots(storedSnapshots)
        selectedSnapshotID = snapshot.id
    }

    private func applySnapshot(_ snapshot: DashboardSnapshot) {
        audiencePresetRawValue = snapshot.preset.rawValue
        var configurations = decodeAudienceConfigurations()
        configurations[snapshot.preset.rawValue] = snapshot.configuration
        audienceConfigurationData = (try? JSONEncoder().encode(configurations)) ?? Data()
    }

    private func exportSnapshot(_ snapshot: DashboardSnapshot) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(snapshot.preset.rawValue) Snapshot \(PDFExporter.fileNameTimestamp).md"
        panel.allowedContentTypes = [UTType.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? snapshot.markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func deleteSnapshot(_ id: UUID) {
        let remaining = snapshots.filter { $0.id != id }
        persistSnapshots(remaining)
        selectedSnapshotID = remaining.first?.id
    }

    private func audienceDashboardMarkdown(stats: ProjectStats) -> String {
        var lines: [String] = [
            "# \(project.properties.projectTitle ?? "Project") \(audiencePreset.rawValue) Dashboard",
            "",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "",
            "## Dashboard Profile",
            "- Audience: \(audiencePreset.rawValue)",
            "- Focus: \(audiencePreset.summary)",
            "- Task Filter: \(currentAudienceConfiguration.taskScope.rawValue)",
            "- Milestone Count: \(currentAudienceConfiguration.milestoneLimit)",
            "- Visible Widgets: \(currentAudienceConfiguration.visibleWidgets.map(\.rawValue).joined(separator: ", "))",
            "",
            "## Recommended Navigation",
        ]

        lines.append(contentsOf: audiencePreset.recommendedViews.map { "- \($0.rawValue)" })
        lines.append("")
        lines.append("## Recommended Exports")
        lines.append(contentsOf: audiencePreset.recommendedExports.map { "- \($0)" })
        lines.append("")
        lines.append("## Headline")
        lines.append(audienceDetail(stats: stats))
        lines.append("")
        lines.append("## KPI Snapshot")
        lines.append(contentsOf: audienceMetrics(stats: stats).map { "- \($0.title): \($0.value) (\($0.subtitle))" })

        if currentAudienceConfiguration.visibleWidgets.contains(.baselineAlert), stats.hasBaselineData {
            lines.append("")
            lines.append("## Baseline Alert")
            if stats.baselineSlippedTasks > 0 || stats.baselineSlippedMilestones > 0 {
                lines.append("- Status: Needs review")
                lines.append("- Slipped tasks: \(stats.baselineSlippedTasks)")
                lines.append("- Slipped milestones: \(stats.baselineSlippedMilestones)")
                lines.append("- Worst finish variance: \(stats.worstFinishVarianceText)")
            } else {
                lines.append("- Status: On track")
                lines.append("- Tracked tasks: \(stats.baselineTrackedTasks)")
                lines.append("- Average finish variance: \(stats.averageFinishVarianceText)")
            }
        }

        if currentAudienceConfiguration.visibleWidgets.contains(.taskStatus) {
            lines.append("")
            lines.append("## \(taskStatusTitle)")
            lines.append("- Scope total: \(filteredTaskTotal)")
            lines.append("- Completed: \(filteredCompletedTasks)")
            lines.append("- In progress: \(filteredInProgressTasks)")
            lines.append("- Not started: \(filteredNotStartedTasks)")
            lines.append("- Overdue: \(filteredOverdueTasks)")
        }

        if currentAudienceConfiguration.visibleWidgets.contains(.milestones) {
            lines.append("")
            lines.append("## Milestones")
            lines.append(contentsOf: milestoneSummaryLines(displayedMilestones(stats)))
        }

        if currentAudienceConfiguration.visibleWidgets.contains(.resourceSummary) {
            let workResources = project.resources.filter { $0.type == "work" || $0.type == nil }.count
            let materialResources = project.resources.filter { $0.type == "material" }.count
            lines.append("")
            lines.append("## Resource Summary")
            lines.append("- Total resources: \(project.resources.count)")
            lines.append("- Work resources: \(workResources)")
            lines.append("- Material resources: \(materialResources)")
            lines.append("- Assignments: \(project.assignments.count)")
        }

        if currentAudienceConfiguration.visibleWidgets.contains(.scheduleHealth) {
            lines.append("")
            lines.append("## Schedule Health")
            if let start = project.properties.startDate {
                lines.append("- Project start: \(DateFormatting.mediumDateTime(start))")
            }
            if let finish = project.properties.finishDate {
                lines.append("- Project finish: \(DateFormatting.mediumDateTime(finish))")
            }
            lines.append("- Duration: \(stats.projectDurationText)")
            lines.append("- Days remaining: \(stats.daysRemainingText)")
        }

        if currentAudienceConfiguration.visibleWidgets.contains(.baselineAnalysis), stats.hasBaselineData {
            lines.append("")
            lines.append("## Baseline Analysis")
            lines.append("- Tracked tasks: \(stats.baselineTrackedTasks)")
            lines.append("- Ahead: \(stats.baselineAheadTasks)")
            lines.append("- On baseline: \(stats.baselineOnPlanTasks)")
            lines.append("- Late vs baseline: \(stats.baselineSlippedTasks)")
            lines.append("- Milestone slips: \(stats.baselineSlippedMilestones)")
            lines.append("- Average finish variance: \(stats.averageFinishVarianceText)")
            lines.append("- Worst finish variance: \(stats.worstFinishVarianceText)")
            lines.append("- Largest slip task: \(stats.worstFinishVarianceTaskName)")
        }

        return lines.joined(separator: "\n")
    }

    private func exportReviewPack() {
        guard let stats else { return }
        exportReviewPackReport(project: project, stats: stats, reviewAnnotations: reviewAnnotations)
    }

    private func exportOpenIssues() {
        exportOpenIssuesReport(project: project, reviewAnnotations: reviewAnnotations)
    }

    private func exportOpenIssuesCSV() {
        CSVExporter.exportOpenIssuesToCSV(
            project: project,
            reviewAnnotations: reviewAnnotations,
            fileName: "Open Issues \(PDFExporter.fileNameTimestamp).csv"
        )
    }

    private func milestoneSummaryLines(_ milestones: [ProjectTask]) -> [String] {
        guard !milestones.isEmpty else { return ["- No upcoming milestones"] }
        return milestones.map { milestone in
            let dateText = milestone.startDate.map { _ in DateFormatting.shortDate(milestone.start) } ?? "No date"
            let status: String
            let pct = milestone.percentComplete ?? 0
            if pct >= 100 {
                status = "Done"
            } else if let date = milestone.startDate, date < Calendar.current.startOfDay(for: Date()) {
                status = "Overdue"
            } else {
                status = "Pending"
            }
            return "- \(milestone.displayName) — \(dateText) — \(status)"
        }
    }
}

struct ExecutiveModeView: View {
    let project: ProjectModel

    @State private var stats: ProjectStats?

    var body: some View {
        Group {
            if let stats {
                executiveContent(stats: stats)
            } else {
                ProgressView("Loading executive view...")
            }
        }
        .task {
            stats = ProjectStats(project: project)
        }
    }

    private func executiveContent(stats: ProjectStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(project.properties.projectTitle ?? "Project")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text(executiveHeadline(stats))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            executivePill("Progress \(stats.averageProgressPercent)%", color: stats.averageProgressPercent >= 75 ? .green : .blue)
                            executivePill("Done \(stats.completedPercent)%", color: stats.completedPercent >= 75 ? .green : .blue)
                            executivePill(stats.daysRemainingText, color: stats.daysRemaining < 0 ? .red : .orange)
                            executivePill("\(stats.criticalIncompleteTasks) critical incomplete", color: stats.criticalIncompleteTasks > 0 ? .red : .green)
                        }
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        Button {
                            exportExecutiveSummary(stats: stats)
                        } label: {
                            Label("Export Summary", systemImage: "doc.text")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            exportReviewPackReport(project: project, stats: stats, reviewAnnotations: ReviewNotesStore.currentAnnotations())
                        } label: {
                            Label("Export Review Pack", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            exportOpenIssuesReport(project: project, reviewAnnotations: ReviewNotesStore.currentAnnotations())
                        } label: {
                            Label("Export Open Issues", systemImage: "exclamationmark.bubble")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            CSVExporter.exportOpenIssuesToCSV(
                                project: project,
                                reviewAnnotations: ReviewNotesStore.currentAnnotations(),
                                fileName: "Open Issues \(PDFExporter.fileNameTimestamp).csv"
                            )
                        } label: {
                            Label("Issues CSV", systemImage: "tablecells")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if stats.hasBaselineData {
                    BaselineAlertView(stats: stats)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 18),
                    GridItem(.flexible(), spacing: 18),
                    GridItem(.flexible(), spacing: 18)
                ], spacing: 18) {
                    executiveMetricCard(
                        title: "Average Task Progress",
                        value: "\(stats.averageProgressPercent)%",
                        detail: "\(stats.completedPercent)% of work tasks are fully completed",
                        color: stats.averageProgressPercent >= 75 ? .green : .blue
                    )
                    executiveMetricCard(
                        title: "Schedule Position",
                        value: stats.daysRemainingText,
                        detail: "\(stats.overdueTasks) overdue tasks, \(stats.onTrackTasks) on track",
                        color: stats.daysRemaining < 0 ? .red : .orange
                    )
                    executiveMetricCard(
                        title: "Cost Outlook",
                        value: stats.totalCostFormatted,
                        detail: stats.evmMetrics.bac > 0 ? "CPI \(String(format: "%.2f", stats.evmMetrics.cpi)) · SPI \(String(format: "%.2f", stats.evmMetrics.spi))" : "EVM not available",
                        color: .blue
                    )
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Executive Summary")
                        .font(.headline)
                        Text(executiveNarrative(stats))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                }

                HStack(alignment: .top, spacing: 20) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Top Risks")
                                .font(.headline)
                            ForEach(executiveRiskItems(stats), id: \.title) { item in
                                executiveBullet(title: item.title, value: item.value)
                                if item.title != executiveRiskItems(stats).last?.title {
                                    Divider()
                                }
                            }
                        }
                        .padding(8)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Major Milestones")
                                .font(.headline)
                            if stats.upcomingMilestones.isEmpty {
                                Text("No upcoming milestones")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(stats.upcomingMilestones.prefix(4), id: \.uniqueID) { milestone in
                                    HStack(alignment: .top) {
                                        Image(systemName: "diamond.fill")
                                            .foregroundStyle(.orange)
                                            .font(.caption2)
                                            .padding(.top, 4)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(milestone.displayName)
                                                .fontWeight(.medium)
                                            Text(milestone.startDate.map { DateFormatting.mediumDateTime($0) } ?? "No date")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        milestoneBadge(for: milestone)
                                    }
                                    if milestone.uniqueID != stats.upcomingMilestones.prefix(4).last?.uniqueID {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .padding(28)
        }
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.06), Color.orange.opacity(0.04), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var validationSummary: String {
        let issues = ProjectValidator.validate(project: project)
        let errors = issues.filter { $0.severity == .error }.count
        let warnings = issues.filter { $0.severity == .warning }.count
        if errors == 0 && warnings == 0 { return "No major validation problems detected." }
        return "\(errors) errors and \(warnings) warnings need review."
    }

    private var diagnosticsSummary: String {
        let signals = ProjectDiagnostics.analyze(project: project)
        if signals.isEmpty { return "No major dependency or constraint hotspots detected." }
        return "\(signals.count) dependency and constraint signals flagged."
    }

    private var resourceRiskSummary: String {
        let risks = ResourceDiagnostics.analyze(project: project)
        if risks.isEmpty { return "No resource over-allocation hotspots detected." }
        return "\(risks.count) resource allocation risks identified."
    }

    private func executiveHeadline(_ stats: ProjectStats) -> String {
        if stats.daysRemaining < 0 {
            return "Project is currently running overdue and needs executive attention."
        }
        if stats.criticalIncompleteTasks > 0 {
            return "Delivery is active with critical-path work still open."
        }
        return "Project is progressing without major critical-path alarms."
    }

    private func executiveNarrative(_ stats: ProjectStats) -> String {
        let schedulePhrase = stats.daysRemaining < 0 ? "The schedule is beyond its target finish by \(-stats.daysRemaining) days." : "The schedule currently shows \(stats.daysRemainingText.lowercased())."
        let progressPhrase = "Average task progress is \(stats.averageProgressPercent)% and \(stats.completedPercent)% of work tasks are fully completed."
        let riskPhrase = stats.criticalIncompleteTasks > 0 ? "\(stats.criticalIncompleteTasks) critical tasks remain open and represent the main delivery risk." : "There are no incomplete critical tasks currently flagged."
        return "\(schedulePhrase) \(progressPhrase) \(riskPhrase)"
    }

    private func executiveMetricCard(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func executivePill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func executiveBullet(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func executiveStatLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func executiveRiskItems(_ stats: ProjectStats) -> [(title: String, value: String)] {
        [
            ("Schedule", stats.daysRemaining < 0 ? "Project is overdue by \(-stats.daysRemaining) days." : "Project timeline shows \(stats.daysRemainingText.lowercased())."),
            ("Quality of Data", validationSummary),
            ("Dependencies", diagnosticsSummary),
            ("Resources", resourceRiskSummary)
        ]
    }

    private func baselineAlert(stats: ProjectStats) -> some View {
        let hasSlip = stats.baselineSlippedTasks > 0 || stats.baselineSlippedMilestones > 0
        let accentColor = hasSlip ? Color.red : Color.green
        let icon = hasSlip ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
        let message = hasSlip
            ? "Baseline slipped tasks: \(stats.baselineSlippedTasks) · worst slip \(stats.worstFinishVarianceText)"
            : "Baseline is tracked for \(stats.baselineTrackedTasks) tasks · avg variance \(stats.averageFinishVarianceText)"

        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(hasSlip ? "Baseline variance alert" : "Baseline tracking")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(accentColor)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(hasSlip ? "Needs review" : "On track")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accentColor.opacity(0.18))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accentColor.opacity(0.35), lineWidth: 1)
        )
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

    private func exportExecutiveSummary(stats: ProjectStats) {
        let validationIssues = ProjectValidator.validate(project: project)
        var lines: [String] = [
            "# \(project.properties.projectTitle ?? "Project") Executive Summary",
            "",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "",
            "## Headline Metrics",
            "- Average task progress: \(stats.averageProgressPercent)%",
            "- Completed-task ratio: \(stats.completedPercent)%",
            "- Total work tasks: \(stats.totalWorkTasks)",
            "- Completed tasks: \(stats.completedTasks)",
            "- In progress tasks: \(stats.inProgressTasks)",
            "- Overdue tasks: \(stats.overdueTasks)",
            "- Critical incomplete tasks: \(stats.criticalIncompleteTasks)",
            "- Days remaining: \(stats.daysRemainingText)",
            "- Total cost: \(stats.totalCostFormatted)",
            "",
            "## Validation Snapshot",
            "- Errors: \(validationIssues.filter { $0.severity == .error }.count)",
            "- Warnings: \(validationIssues.filter { $0.severity == .warning }.count)",
            "- Info: \(validationIssues.filter { $0.severity == .info }.count)",
            "",
            "## Upcoming Milestones",
        ] + milestoneSummaryLines(stats.upcomingMilestones)

        let markdown = lines.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Executive Summary \(PDFExporter.fileNameTimestamp).md"
        panel.allowedContentTypes = [UTType.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func milestoneSummaryLines(_ milestones: [ProjectTask]) -> [String] {
        guard !milestones.isEmpty else { return ["- No upcoming milestones"] }
        return milestones.map { milestone in
            let dateText = milestone.startDate.map { _ in DateFormatting.shortDate(milestone.start) } ?? "No date"
            let status: String
            let pct = milestone.percentComplete ?? 0
            if pct >= 100 {
                status = "Done"
            } else if let date = milestone.startDate, date < Calendar.current.startOfDay(for: Date()) {
                status = "Overdue"
            } else {
                status = "Pending"
            }
            return "- \(milestone.displayName) — \(dateText) — \(status)"
        }
    }
}

struct BaselineAlertView: View {
    let stats: ProjectStats

    private var hasSlip: Bool {
        stats.baselineSlippedTasks > 0 || stats.baselineSlippedMilestones > 0
    }

    private var accentColor: Color {
        hasSlip ? .red : .green
    }

    private var message: String {
        if hasSlip {
            return "Slipped tasks: \(stats.baselineSlippedTasks) · worst slip \(stats.worstFinishVarianceText)"
        } else {
            return "Baseline tracked for \(stats.baselineTrackedTasks) tasks · avg variance \(stats.averageFinishVarianceText)"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hasSlip ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(hasSlip ? "Baseline variance alert" : "Baseline tracking")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(hasSlip ? "Review" : "On track")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(accentColor.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accentColor.opacity(0.35), lineWidth: 1)
        )
    }
}

private func exportReviewPackReport(project: ProjectModel, stats: ProjectStats, reviewAnnotations: [Int: TaskReviewAnnotation]) {
    let validationIssues = ProjectValidator.validate(project: project)
    let diagnostics = ProjectDiagnostics.analyze(project: project)
    let resourceIssues = ResourceDiagnostics.analyze(project: project)
    let milestones = project.tasks.filter { $0.isDisplayMilestone }.prefix(10)
    let annotatedTasks = reviewAnnotations.compactMap { uniqueID, annotation -> (ProjectTask, TaskReviewAnnotation)? in
        guard let task = project.tasksByID[uniqueID] else { return nil }
        guard annotation.hasContent else { return nil }
        return (task, annotation)
    }
    .sorted { $0.0.displayName < $1.0.displayName }
    let unresolvedAnnotations = annotatedTasks.filter { $0.1.isUnresolved }

    let validationSummaryLines = [
        "- Errors: \(validationIssues.filter { $0.severity == .error }.count)",
        "- Warnings: \(validationIssues.filter { $0.severity == .warning }.count)",
        "- Info: \(validationIssues.filter { $0.severity == .info }.count)",
    ]
    let validationDetailLines = validationIssues.prefix(10).map { issue in
        "- [\(issue.severity.label)] \(issue.taskName ?? "Project"): \(issue.message)"
    }
    let diagnosticsLines = diagnostics.prefix(10).map { item in
        "- [\(item.category.label)] \(item.taskName ?? "Project"): \(item.message)"
    }
    let resourceRiskLines = resourceIssues.prefix(10).map { item in
        "- [\(item.severity.label)] \(item.resourceName): \(item.message)"
    }
    let milestoneLines = milestones.map { milestone in
        let variance = milestone.finishVarianceDays ?? milestone.startVarianceDays
        let varianceText = variance.map { "\($0 > 0 ? "+" : "")\($0)d vs baseline" } ?? "No baseline"
        return "- \(milestone.displayName): \(DateFormatting.shortDate(milestone.start)) · \(varianceText)"
    }
    let annotationSummaryLines = [
        "- Annotated tasks: \(annotatedTasks.count)",
        "- Open issues: \(unresolvedAnnotations.count)",
        "- Needs follow-up: \(annotatedTasks.filter { $0.1.needsFollowUp }.count)",
    ]
    let reviewNoteLines = annotatedTasks.isEmpty
        ? ["- No local issue annotations"]
        : annotatedTasks.map { task, annotation in
            formatAnnotationLine(task: task, annotation: annotation)
        }

    var lines: [String] = [
        "# \(project.properties.projectTitle ?? "Project") Review Pack",
        "",
        "Generated: \(ISO8601DateFormatter().string(from: Date()))",
        "",
        "## Executive Summary",
        "- Average task progress: \(stats.averageProgressPercent)%",
        "- Completed-task ratio: \(stats.completedPercent)%",
        "- Days remaining: \(stats.daysRemainingText)",
        "- Critical incomplete tasks: \(stats.criticalIncompleteTasks)",
        "- Baseline tracked tasks: \(stats.baselineTrackedTasks)",
        "- Baseline slipped tasks: \(stats.baselineSlippedTasks)",
        "",
        "## Validation",
    ]
    lines.append(contentsOf: validationSummaryLines)
    lines.append(contentsOf: validationDetailLines)
    lines.append("")
    lines.append("## Diagnostics")
    lines.append("- Total findings: \(diagnostics.count)")
    lines.append(contentsOf: diagnosticsLines)
    lines.append("")
    lines.append("## Resource Risks")
    lines.append("- Total findings: \(resourceIssues.count)")
    lines.append(contentsOf: resourceRiskLines)
    lines.append("")
    lines.append("## Milestone Outlook")
    lines.append(contentsOf: milestoneLines)
    lines.append("")
    lines.append("## Issue Annotations")
    lines.append(contentsOf: annotationSummaryLines)
    lines.append(contentsOf: reviewNoteLines)

    let markdown = lines.joined(separator: "\n")
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Review Pack \(PDFExporter.fileNameTimestamp).md"
    panel.allowedContentTypes = [UTType.plainText]
    panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
    }
}

private func exportOpenIssuesReport(project: ProjectModel, reviewAnnotations: [Int: TaskReviewAnnotation]) {
    let openIssues = reviewAnnotations.compactMap { uniqueID, annotation -> (ProjectTask, TaskReviewAnnotation)? in
        guard let task = project.tasksByID[uniqueID], annotation.isUnresolved else { return nil }
        return (task, annotation)
    }
    .sorted { lhs, rhs in
        if lhs.1.needsFollowUp != rhs.1.needsFollowUp {
            return lhs.1.needsFollowUp && !rhs.1.needsFollowUp
        }
        return lhs.0.displayName < rhs.0.displayName
    }

    var lines: [String] = [
        "# \(project.properties.projectTitle ?? "Project") Open Issues",
        "",
        "Generated: \(ISO8601DateFormatter().string(from: Date()))",
        "",
        "- Total unresolved items: \(openIssues.count)",
        "- Follow-up required: \(openIssues.filter { $0.1.needsFollowUp }.count)",
        "",
        "## Items"
    ]

    if openIssues.isEmpty {
        lines.append("- No unresolved issue annotations")
    } else {
        lines.append(contentsOf: openIssues.map { task, annotation in
            formatAnnotationLine(task: task, annotation: annotation)
        })
    }

    let markdown = lines.joined(separator: "\n")
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Open Issues \(PDFExporter.fileNameTimestamp).md"
    panel.allowedContentTypes = [UTType.plainText]
    panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
    }
}

private func formatAnnotationLine(task: ProjectTask, annotation: TaskReviewAnnotation) -> String {
    let followUpText = annotation.needsFollowUp ? " · follow-up required" : ""
    let noteText = annotation.trimmedNote.isEmpty
        ? "No note provided"
        : annotation.trimmedNote.replacingOccurrences(of: "\n", with: " ")
    return "- \(task.displayName) [\(annotation.status.rawValue)\(followUpText)]: \(noteText)"
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
    let baselineTrackedTasks: Int
    let baselineOnPlanTasks: Int
    let baselineAheadTasks: Int
    let baselineSlippedTasks: Int
    let baselineSlippedMilestones: Int
    let averageFinishVarianceDays: Int?
    let worstFinishVarianceTaskName: String
    let worstFinishVarianceDays: Int?

    var averageProgressPercent: Int { overallPercent }

    var completedPercent: Int {
        guard totalWorkTasks > 0 else { return 0 }
        return Int((Double(completedTasks) / Double(totalWorkTasks) * 100.0).rounded())
    }

    var hasBaselineData: Bool {
        baselineTrackedTasks > 0
    }

    var averageFinishVarianceText: String {
        guard let averageFinishVarianceDays else { return "N/A" }
        if averageFinishVarianceDays == 0 { return "On baseline" }
        return "\(averageFinishVarianceDays > 0 ? "+" : "")\(averageFinishVarianceDays) days"
    }

    var worstFinishVarianceText: String {
        guard let worstFinishVarianceDays else { return "N/A" }
        if worstFinishVarianceDays == 0 { return "On baseline" }
        return "\(worstFinishVarianceDays > 0 ? "+" : "")\(worstFinishVarianceDays) days"
    }

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

        let baselineTasks = project.tasks.filter { $0.summary != true && $0.hasBaseline }
        self.baselineTrackedTasks = baselineTasks.count
        self.baselineOnPlanTasks = baselineTasks.filter { ($0.finishVarianceDays ?? $0.startVarianceDays ?? 0) == 0 }.count
        self.baselineAheadTasks = baselineTasks.filter { ($0.finishVarianceDays ?? $0.startVarianceDays ?? 0) < 0 }.count
        self.baselineSlippedTasks = baselineTasks.filter { ($0.finishVarianceDays ?? $0.startVarianceDays ?? 0) > 0 }.count
        self.baselineSlippedMilestones = project.tasks.filter { $0.isDisplayMilestone && ($0.finishVarianceDays ?? $0.startVarianceDays ?? 0) > 0 }.count

        let finishVariances = baselineTasks.compactMap { $0.finishVarianceDays ?? $0.startVarianceDays }
        if finishVariances.isEmpty {
            self.averageFinishVarianceDays = nil
        } else {
            let average = Double(finishVariances.reduce(0, +)) / Double(finishVariances.count)
            self.averageFinishVarianceDays = Int(average.rounded())
        }

        if let worstTask = baselineTasks.max(by: { abs($0.finishVarianceDays ?? $0.startVarianceDays ?? 0) < abs($1.finishVarianceDays ?? $1.startVarianceDays ?? 0) }) {
            self.worstFinishVarianceTaskName = worstTask.displayName
            self.worstFinishVarianceDays = worstTask.finishVarianceDays ?? worstTask.startVarianceDays
        } else {
            self.worstFinishVarianceTaskName = "N/A"
            self.worstFinishVarianceDays = nil
        }

        // Upcoming milestones: incomplete milestones with dates in the next 30 days
        self.upcomingMilestones = project.tasks
            .filter { $0.isDisplayMilestone }
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
