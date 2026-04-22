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
        defaultTemplateExports.map(\.rawValue)
    }

    var defaultTemplateExports: [DashboardTemplateExport] {
        switch self {
        case .projectManager:
            return [.reviewPack, .openIssues, .issuesCSV]
        case .executive:
            return [.executiveSummary, .reviewPack]
        case .scheduler:
            return [.executiveSummary, .openIssues]
        case .resourceManager:
            return [.issuesCSV, .openIssues]
        }
    }
}

enum DashboardTemplateExport: String, CaseIterable, Codable, Identifiable {
    case audienceDashboard = "Audience Dashboard"
    case reviewPack = "Review Pack"
    case openIssues = "Open Issues"
    case issuesCSV = "Issues CSV"
    case executiveSummary = "Executive Summary"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .audienceDashboard: return "square.and.arrow.up.on.square"
        case .reviewPack: return "doc.richtext"
        case .openIssues: return "exclamationmark.bubble"
        case .issuesCSV: return "tablecells"
        case .executiveSummary: return "doc.text"
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

private struct DashboardProjectAnalysis {
    let validationIssues: [ProjectValidationIssue]
    let diagnosticItems: [ProjectDiagnosticItem]
    let resourceIssues: [ResourceDiagnosticItem]

    static func build(project: ProjectModel) -> DashboardProjectAnalysis {
        DashboardProjectAnalysis(
            validationIssues: ProjectValidator.validate(project: project),
            diagnosticItems: ProjectDiagnostics.analyze(project: project),
            resourceIssues: ResourceDiagnostics.analyze(project: project)
        )
    }
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
    var cadence: SnapshotCadence
    var customTitle: String?
    var isPinned: Bool
    let sourceReviewTemplateID: UUID?
    let headline: String
    let markdown: String
    let flaggedTaskIDs: [Int]
    let reviewAnnotations: [Int: TaskReviewAnnotation]

    var displayTitle: String {
        let trimmed = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? preset.rawValue : trimmed
    }

    var flaggedTaskCount: Int { flaggedTaskIDs.count }
    var annotatedTaskCount: Int { reviewAnnotations.count }
    var unresolvedIssueCount: Int { reviewAnnotations.values.filter(\.isUnresolved).count }
    var followUpIssueCount: Int { reviewAnnotations.values.filter(\.needsFollowUp).count }

    init(
        id: UUID,
        createdAt: Date,
        projectTitle: String,
        preset: DashboardAudiencePreset,
        configuration: DashboardAudienceConfiguration,
        cadence: SnapshotCadence = .adHoc,
        customTitle: String? = nil,
        isPinned: Bool = false,
        sourceReviewTemplateID: UUID? = nil,
        headline: String,
        markdown: String,
        flaggedTaskIDs: [Int],
        reviewAnnotations: [Int: TaskReviewAnnotation]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.projectTitle = projectTitle
        self.preset = preset
        self.configuration = configuration
        self.cadence = cadence
        self.customTitle = customTitle
        self.isPinned = isPinned
        self.sourceReviewTemplateID = sourceReviewTemplateID
        self.headline = headline
        self.markdown = markdown
        self.flaggedTaskIDs = flaggedTaskIDs.sorted()
        self.reviewAnnotations = reviewAnnotations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        projectTitle = try container.decode(String.self, forKey: .projectTitle)
        preset = try container.decode(DashboardAudiencePreset.self, forKey: .preset)
        configuration = try container.decode(DashboardAudienceConfiguration.self, forKey: .configuration)
        cadence = try container.decodeIfPresent(SnapshotCadence.self, forKey: .cadence) ?? .adHoc
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        sourceReviewTemplateID = try container.decodeIfPresent(UUID.self, forKey: .sourceReviewTemplateID)
        headline = try container.decode(String.self, forKey: .headline)
        markdown = try container.decode(String.self, forKey: .markdown)
        flaggedTaskIDs = (try container.decodeIfPresent([Int].self, forKey: .flaggedTaskIDs) ?? []).sorted()
        reviewAnnotations = try container.decodeIfPresent([Int: TaskReviewAnnotation].self, forKey: .reviewAnnotations) ?? [:]
    }
}

private struct DashboardSnapshotComparison {
    let selected: DashboardSnapshot
    let baseline: DashboardSnapshot
    let addedFlaggedTasks: [String]
    let clearedFlaggedTasks: [String]
    let addedAnnotatedTasks: [String]
    let clearedAnnotatedTasks: [String]
    let newOpenIssues: [String]
    let resolvedIssues: [String]
    let addedFollowUpTasks: [String]
    let clearedFollowUpTasks: [String]
    let flaggedDelta: Int
    let annotatedDelta: Int
    let unresolvedDelta: Int
    let followUpDelta: Int
    let presetChanged: Bool
    let taskScopeChanged: Bool
    let milestoneLimitChanged: Bool
    let widgetChangeCount: Int

    var hasReviewChanges: Bool {
        flaggedDelta != 0 ||
        annotatedDelta != 0 ||
        unresolvedDelta != 0 ||
        followUpDelta != 0 ||
        !addedFlaggedTasks.isEmpty ||
        !clearedFlaggedTasks.isEmpty ||
        !addedAnnotatedTasks.isEmpty ||
        !clearedAnnotatedTasks.isEmpty ||
        !newOpenIssues.isEmpty ||
        !resolvedIssues.isEmpty ||
        !addedFollowUpTasks.isEmpty ||
        !clearedFollowUpTasks.isEmpty
    }

    var hasLayoutChanges: Bool {
        presetChanged || taskScopeChanged || milestoneLimitChanged || widgetChangeCount > 0
    }
}

private enum SnapshotTrendFocus: String {
    case openIssues = "Open Issues"
    case followUp = "Follow-Up"
    case flagged = "Flagged Tasks"
    case annotations = "Annotated Tasks"
}

private enum SnapshotCadence: String, CaseIterable, Codable, Identifiable {
    case weeklyPM = "Weekly PM"
    case executive = "Executive"
    case baselineCheck = "Baseline Check"
    case adHoc = "Ad Hoc"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .weeklyPM: return .blue
        case .executive: return .indigo
        case .baselineCheck: return .orange
        case .adHoc: return .secondary
        }
    }

    var reviewIntervalDays: Int? {
        switch self {
        case .weeklyPM: return 7
        case .executive: return 14
        case .baselineCheck: return 14
        case .adHoc: return nil
        }
    }
}

private enum SnapshotCadenceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case weeklyPM = "Weekly PM"
    case executive = "Executive"
    case baselineCheck = "Baseline Check"
    case adHoc = "Ad Hoc"

    var id: String { rawValue }

    var cadence: SnapshotCadence? {
        switch self {
        case .all: return nil
        case .weeklyPM: return .weeklyPM
        case .executive: return .executive
        case .baselineCheck: return .baselineCheck
        case .adHoc: return .adHoc
        }
    }
}

private enum SnapshotTemplate: String, CaseIterable, Identifiable {
    case weeklyPMReview = "Weekly PM Review"
    case executiveGateReview = "Executive Gate Review"
    case baselineHealthCheck = "Baseline Health Check"
    case adHocRiskReview = "Ad Hoc Risk Review"

    var id: String { rawValue }

    var preset: DashboardAudiencePreset {
        switch self {
        case .weeklyPMReview: return .projectManager
        case .executiveGateReview: return .executive
        case .baselineHealthCheck: return .scheduler
        case .adHocRiskReview: return .resourceManager
        }
    }

    var cadence: SnapshotCadence {
        switch self {
        case .weeklyPMReview: return .weeklyPM
        case .executiveGateReview: return .executive
        case .baselineHealthCheck: return .baselineCheck
        case .adHocRiskReview: return .adHoc
        }
    }

    var isPinned: Bool {
        switch self {
        case .adHocRiskReview: return false
        default: return true
        }
    }

    var icon: String {
        switch self {
        case .weeklyPMReview: return "calendar.badge.clock"
        case .executiveGateReview: return "display"
        case .baselineHealthCheck: return "flag.pattern.checkered.2.crossed"
        case .adHocRiskReview: return "exclamationmark.triangle"
        }
    }

    var summary: String {
        switch self {
        case .weeklyPMReview:
            return "Daily delivery review with milestone and issue visibility."
        case .executiveGateReview:
            return "Condensed leadership view for schedule exposure and summary exports."
        case .baselineHealthCheck:
            return "Variance-focused review for finish movement and baseline drift."
        case .adHocRiskReview:
            return "Resource-led risk triage for overload and follow-up pressure."
        }
    }
}

private struct DashboardReviewTemplate: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    var title: String
    let preset: DashboardAudiencePreset
    let configuration: DashboardAudienceConfiguration
    var cadence: SnapshotCadence
    var isPinned: Bool
    var preferredExports: [DashboardTemplateExport]
    var reminderSnoozedUntil: Date?
    var dismissedReminderKey: String?
    var reminderEvents: [ReviewReminderEvent]

    var summary: String {
        "\(preset.rawValue) · \(configuration.taskScope.rawValue) · \(configuration.visibleWidgets.count) widgets"
    }

    init(
        id: UUID,
        createdAt: Date,
        title: String,
        preset: DashboardAudiencePreset,
        configuration: DashboardAudienceConfiguration,
        cadence: SnapshotCadence,
        isPinned: Bool,
        preferredExports: [DashboardTemplateExport],
        reminderSnoozedUntil: Date? = nil,
        dismissedReminderKey: String? = nil,
        reminderEvents: [ReviewReminderEvent] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.preset = preset
        self.configuration = configuration
        self.cadence = cadence
        self.isPinned = isPinned
        self.preferredExports = preferredExports
        self.reminderSnoozedUntil = reminderSnoozedUntil
        self.dismissedReminderKey = dismissedReminderKey
        self.reminderEvents = reminderEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        title = try container.decode(String.self, forKey: .title)
        preset = try container.decode(DashboardAudiencePreset.self, forKey: .preset)
        configuration = try container.decode(DashboardAudienceConfiguration.self, forKey: .configuration)
        cadence = try container.decode(SnapshotCadence.self, forKey: .cadence)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        preferredExports = try container.decodeIfPresent([DashboardTemplateExport].self, forKey: .preferredExports) ?? preset.defaultTemplateExports
        reminderSnoozedUntil = try container.decodeIfPresent(Date.self, forKey: .reminderSnoozedUntil)
        dismissedReminderKey = try container.decodeIfPresent(String.self, forKey: .dismissedReminderKey)
        reminderEvents = try container.decodeIfPresent([ReviewReminderEvent].self, forKey: .reminderEvents) ?? []
    }
}

private struct ReviewQueueEntry: Identifiable {
    let template: DashboardReviewTemplate
    let lastRun: DashboardSnapshot?
    let dueDate: Date?
    let daysUntilDue: Int?

    var id: UUID { template.id }
}

private struct ReviewReminderEvent: Codable, Identifiable {
    enum Action: String, Codable {
        case snoozed = "Snoozed"
        case dismissed = "Dismissed"
        case restored = "Restored"
        case completed = "Completed"
    }

    let id: UUID
    let action: Action
    let createdAt: Date
    let detail: String
    let reminderKey: String?
}

private enum ReviewQueueFocus: String, Equatable {
    case oftenSnoozed = "Often Snoozed"
    case overdue = "Overdue Reviews"
    case hiddenDue = "Hidden While Due"
}

private struct ReviewQueueActionFeedback: Identifiable {
    let id = UUID()
    let message: String
    let color: Color
    let icon: String
}

struct DashboardView: View {
    let project: ProjectModel

    @State private var stats: ProjectStats?
    @State private var projectAnalysis: DashboardProjectAnalysis?
    @AppStorage("flaggedTaskIDs") private var flaggedTaskIDsData: Data = Data()
    @AppStorage(ReviewNotesStore.key) private var taskReviewNotesData: Data = Data()
    @AppStorage("dashboardAudiencePreset") private var audiencePresetRawValue = DashboardAudiencePreset.projectManager.rawValue
    @AppStorage("dashboardAudienceConfigurations") private var audienceConfigurationData: Data = Data()
    @AppStorage("dashboardSnapshots") private var snapshotData: Data = Data()
    @AppStorage("dashboardReviewTemplates") private var reviewTemplateData: Data = Data()
    @State private var isCustomizationExpanded = false
    @State private var selectedSnapshotID: UUID?
    @State private var comparisonSnapshotID: UUID?
    @State private var selectedTrendFocus: SnapshotTrendFocus?
    @State private var cadenceFilter: SnapshotCadenceFilter = .all
    @State private var appliedReviewTemplateID: UUID?
    @State private var selectedReviewQueueFocus: ReviewQueueFocus?
    @State private var reviewQueueActionFeedback: ReviewQueueActionFeedback?
    @State private var customTemplateTitle = ""
    @State private var customTemplateCadence: SnapshotCadence = .weeklyPM
    @State private var customTemplatePinned = true
    @State private var customTemplatePreferredExports: Set<DashboardTemplateExport> = Set(DashboardAudiencePreset.projectManager.defaultTemplateExports)

    private var audiencePreset: DashboardAudiencePreset {
        get { DashboardAudiencePreset(rawValue: audiencePresetRawValue) ?? .projectManager }
        nonmutating set { audiencePresetRawValue = newValue.rawValue }
    }

    private var currentAudienceConfiguration: DashboardAudienceConfiguration {
        decodeAudienceConfigurations()[audiencePreset.rawValue] ?? .default(for: audiencePreset)
    }

    private var snapshots: [DashboardSnapshot] {
        decodeSnapshots().sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var reviewTemplates: [DashboardReviewTemplate] {
        decodeReviewTemplates().sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var appliedReviewTemplate: DashboardReviewTemplate? {
        guard let appliedReviewTemplateID else { return nil }
        return reviewTemplates.first(where: { $0.id == appliedReviewTemplateID })
    }

    private var filteredSnapshots: [DashboardSnapshot] {
        guard let cadence = cadenceFilter.cadence else { return snapshots }
        return snapshots.filter { $0.cadence == cadence }
    }

    private var selectedSnapshot: DashboardSnapshot? {
        guard let selectedSnapshotID else { return filteredSnapshots.first ?? snapshots.first }
        return filteredSnapshots.first(where: { $0.id == selectedSnapshotID }) ?? filteredSnapshots.first ?? snapshots.first
    }

    private var comparisonSnapshot: DashboardSnapshot? {
        guard let selectedSnapshot else { return nil }

        if let comparisonSnapshotID,
           comparisonSnapshotID != selectedSnapshot.id,
           let match = snapshots.first(where: { $0.id == comparisonSnapshotID }) {
            return match
        }

        return comparisonSnapshotOptions(for: selectedSnapshot.id).first
    }

    private var snapshotComparison: DashboardSnapshotComparison? {
        guard let selectedSnapshot, let comparisonSnapshot else { return nil }
        return buildSnapshotComparison(selected: selectedSnapshot, baseline: comparisonSnapshot)
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
            projectAnalysis = DashboardProjectAnalysis.build(project: project)
            if selectedSnapshotID == nil {
                selectedSnapshotID = snapshots.first?.id
            }
            if comparisonSnapshotID == nil {
                comparisonSnapshotID = defaultComparisonSnapshotID(for: selectedSnapshotID)
            }
        }
        .onChange(of: cadenceFilter) { _, _ in
            guard let selectedSnapshotID,
                  filteredSnapshots.contains(where: { $0.id == selectedSnapshotID }) else {
                selectedSnapshotID = filteredSnapshots.first?.id ?? snapshots.first?.id
                comparisonSnapshotID = defaultComparisonSnapshotID(for: selectedSnapshotID)
                selectedTrendFocus = nil
                return
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

                    Menu {
                        ForEach(SnapshotTemplate.allCases) { template in
                            Button {
                                saveSnapshotTemplate(template, stats: stats)
                            } label: {
                                Label(template.rawValue, systemImage: template.icon)
                            }
                        }

                        if !reviewTemplates.isEmpty {
                            Divider()

                            ForEach(reviewTemplates) { template in
                                Button {
                                    saveReviewTemplateSnapshot(template, stats: stats)
                                } label: {
                                    Label(template.title, systemImage: template.preset.icon)
                                }
                            }
                        }
                    } label: {
                        Label("Snapshot Template", systemImage: "square.stack.3d.up")
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
                                appliedReviewTemplateID = nil
                                customTemplatePreferredExports = Set(preset.defaultTemplateExports)
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

                if let appliedReviewTemplate,
                   appliedReviewTemplate.preset == audiencePreset {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Template Exports")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(appliedReviewTemplate.preferredExports) { export in
                                Button {
                                    performTemplateExport(export, stats: stats)
                                } label: {
                                    Label(export.rawValue, systemImage: export.icon)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        if let lastRun = latestSnapshot(for: appliedReviewTemplate) {
                            Text("Last review run \(lastRun.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if let dueLabel = templateDueLabel(for: appliedReviewTemplate) {
                            baselinePill(dueLabel.text, color: dueLabel.color)
                                .font(.caption2)
                        }

                        reminderActivityStrip(for: appliedReviewTemplate, limit: 4)
                    }
                }

                reviewQueueSection(stats: stats)

                reviewTemplatesSection(stats: stats)

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

    private func reviewTemplatesSection(stats: ProjectStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Review Templates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Apply a known dashboard mode or save it as a labeled run.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(SnapshotTemplate.allCases) { template in
                        snapshotTemplateCard(template, stats: stats)
                    }
                }
                .padding(.vertical, 2)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Save Current Layout as Template")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .center, spacing: 12) {
                    TextField("Template Name", text: $customTemplateTitle)
                        .textFieldStyle(.roundedBorder)

                    Picker("Cadence", selection: $customTemplateCadence) {
                        ForEach(SnapshotCadence.allCases) { cadence in
                            Text(cadence.rawValue).tag(cadence)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)

                    Toggle("Pin", isOn: $customTemplatePinned)
                        .toggleStyle(.checkbox)

                    Button("Save Current Template") {
                        saveCurrentReviewTemplate()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(customTemplateTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                templateExportSelection(
                    selectedExports: customTemplatePreferredExports,
                    toggle: toggleCustomTemplateExport
                )
            }

            if !reviewTemplates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("My Templates")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(reviewTemplates) { template in
                                customReviewTemplateCard(template, stats: stats)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func reviewQueueSection(stats: ProjectStats) -> some View {
        let queueEntries = activeReviewQueueEntries
        let suppressedEntries = suppressedReviewQueueEntries
        let snoozedEntries = frequentlySnoozedQueueEntries
        let overdueEntries = overdueReviewQueueEntries
        let focusedEntries = selectedReviewQueueFocus.flatMap(reviewQueueEntries(for:)) ?? []
        let focusedSuppressedEntries = focusedEntries.filter { entry in
            suppressedEntries.contains(where: { $0.id == entry.id })
        }
        let focusedActiveEntries = focusedEntries.filter { entry in
            !suppressedEntries.contains(where: { $0.id == entry.id })
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Review Queue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !queueEntries.isEmpty {
                    Text("\(queueEntries.count) active reminders")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if queueEntries.isEmpty && suppressedEntries.isEmpty {
                Text("No due review reminders right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if queueEntries.isEmpty {
                Text("No active reminders right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(queueEntries.prefix(4)) { entry in
                    reviewQueueEntryRow(entry, stats: stats, isSuppressed: false)
                }
            }

            if !snoozedEntries.isEmpty || !overdueEntries.isEmpty || !suppressedEntries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review Friction")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 10) {
                        if !snoozedEntries.isEmpty {
                            reviewFrictionCard(
                                title: "Often Snoozed",
                                accent: .orange,
                                summary: "\(snoozedEntries.count) templates were snoozed multiple times.",
                                isSelected: selectedReviewQueueFocus == .oftenSnoozed,
                                items: snoozedEntries.prefix(2).map { entry in
                                    "\(entry.template.title) · \(reminderEventCount(for: entry.template, action: .snoozed)) snoozes"
                                },
                                action: {
                                    toggleReviewQueueFocus(.oftenSnoozed)
                                }
                            )
                        }

                        if !overdueEntries.isEmpty {
                            reviewFrictionCard(
                                title: "Overdue Reviews",
                                accent: .red,
                                summary: "\(overdueEntries.count) templates are past due.",
                                isSelected: selectedReviewQueueFocus == .overdue,
                                items: overdueEntries.prefix(2).map { entry in
                                    "\(entry.template.title) · \(overdueSummary(for: entry))"
                                },
                                action: {
                                    toggleReviewQueueFocus(.overdue)
                                }
                            )
                        }

                        if !suppressedEntries.isEmpty {
                            reviewFrictionCard(
                                title: "Hidden While Due",
                                accent: .secondary,
                                summary: "\(suppressedEntries.count) due reminders are currently hidden.",
                                isSelected: selectedReviewQueueFocus == .hiddenDue,
                                items: suppressedEntries.prefix(2).map { entry in
                                    "\(entry.template.title) · \(suppressionSummary(for: entry) ?? "Suppressed")"
                                },
                                action: {
                                    toggleReviewQueueFocus(.hiddenDue)
                                }
                            )
                        }
                    }
                }
            }

            if let selectedReviewQueueFocus, !focusedEntries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(selectedReviewQueueFocus.rawValue) Focus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(focusedEntries.count) templates")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if !focusedSuppressedEntries.isEmpty {
                            Button("Restore All") {
                                restoreReminders(for: focusedSuppressedEntries)
                            }
                            .buttonStyle(.bordered)
                        }
                        if !focusedActiveEntries.isEmpty {
                            Menu("Snooze All") {
                                Button("1 day") {
                                    snoozeReminders(for: focusedActiveEntries, days: 1)
                                }
                                Button("3 days") {
                                    snoozeReminders(for: focusedActiveEntries, days: 3)
                                }
                                Button("7 days") {
                                    snoozeReminders(for: focusedActiveEntries, days: 7)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        Button("Save All") {
                            saveReviewTemplateSnapshots(for: focusedEntries, stats: stats)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(reviewQueueFocusAccent(for: selectedReviewQueueFocus))
                        Button("Clear") {
                            self.selectedReviewQueueFocus = nil
                            reviewQueueActionFeedback = nil
                        }
                        .buttonStyle(.bordered)
                    }

                    if let reviewQueueActionFeedback {
                        reviewQueueFeedbackBanner(reviewQueueActionFeedback)
                    }

                    ForEach(focusedEntries.prefix(4)) { entry in
                        reviewQueueEntryRow(entry, stats: stats, isSuppressed: suppressedEntries.contains(where: { $0.id == entry.id }))
                    }
                }
            }

            if !suppressedEntries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Suppressed Reminders")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(suppressedEntries.count) hidden")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    ForEach(suppressedEntries.prefix(3)) { entry in
                        reviewQueueEntryRow(entry, stats: stats, isSuppressed: true)
                    }
                }
            }
        }
    }

    private func snapshotTemplateCard(_ template: SnapshotTemplate, stats: ProjectStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Label(template.rawValue, systemImage: template.icon)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if template.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Text(template.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                baselinePill(template.preset.rawValue, color: dashboardTint(for: template.preset))
                baselinePill(template.cadence.rawValue, color: template.cadence.color)
            }
            .font(.caption2)

            HStack(spacing: 8) {
                Button("Apply") {
                    applySnapshotTemplate(template)
                }
                .buttonStyle(.borderedProminent)
                .tint(dashboardTint(for: template.preset))

                Button("Save Run") {
                    saveSnapshotTemplate(template, stats: stats)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(width: 270, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(dashboardTint(for: template.preset).opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(dashboardTint(for: template.preset).opacity(0.18), lineWidth: 1)
        )
    }

    private func reviewQueueEntryRow(
        _ entry: ReviewQueueEntry,
        stats: ProjectStats,
        isSuppressed: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.template.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(entry.template.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    baselinePill(entry.template.cadence.rawValue, color: entry.template.cadence.color)
                    if let schedule = reviewQueueLabel(for: entry) {
                        baselinePill(schedule.text, color: schedule.color)
                    }
                }
                .font(.caption2)
                if let lastRun = entry.lastRun {
                    Text("Last run \(lastRun.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if isSuppressed, let suppression = suppressionSummary(for: entry) {
                    Text(suppression)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let latestEvent = entry.template.reminderEvents.first {
                    Text("\(latestEvent.action.rawValue) \(latestEvent.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if isSuppressed {
                    Button("Restore") {
                        restoreReminder(for: entry.template.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(dashboardTint(for: entry.template.preset))
                } else {
                    Menu("Snooze") {
                        Button("1 day") {
                            snoozeReminder(for: entry.template.id, days: 1)
                        }
                        Button("3 days") {
                            snoozeReminder(for: entry.template.id, days: 3)
                        }
                        Button("7 days") {
                            snoozeReminder(for: entry.template.id, days: 7)
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Dismiss") {
                        dismissReminder(for: entry)
                    }
                    .buttonStyle(.bordered)
                }

                Button("Apply") {
                    applyReviewTemplate(entry.template)
                }
                .buttonStyle(.bordered)

                if isSuppressed {
                    Button("Save Run") {
                        saveReviewTemplateSnapshot(entry.template, stats: stats)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Save Run") {
                        saveReviewTemplateSnapshot(entry.template, stats: stats)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(dashboardTint(for: entry.template.preset))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSuppressed ? Color.secondary.opacity(0.06) : dashboardTint(for: entry.template.preset).opacity(0.08))
        )
    }

    private func reviewFrictionCard(
        title: String,
        accent: Color,
        summary: String,
        isSelected: Bool,
        items: [String],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(accent)

                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption2)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(isSelected ? 0.16 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent.opacity(isSelected ? 0.35 : 0.15), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func reviewQueueFeedbackBanner(_ feedback: ReviewQueueActionFeedback) -> some View {
        Label(feedback.message, systemImage: feedback.icon)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(feedback.color.opacity(0.12))
            )
            .foregroundStyle(feedback.color)
    }

    private func customReviewTemplateCard(_ template: DashboardReviewTemplate, stats: ProjectStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Label(template.title, systemImage: template.preset.icon)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if template.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Text(template.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                baselinePill(template.preset.rawValue, color: dashboardTint(for: template.preset))
                baselinePill(template.cadence.rawValue, color: template.cadence.color)
            }
            .font(.caption2)

            if let lastRun = latestSnapshot(for: template) {
                Text("Last run \(lastRun.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if template.cadence != .adHoc {
                Text("No review run saved yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let dueLabel = templateDueLabel(for: template) {
                baselinePill(dueLabel.text, color: dueLabel.color)
                    .font(.caption2)
            }

            reminderActivityStrip(for: template, limit: 3)

            templateExportSelection(
                selectedExports: Set(template.preferredExports),
                toggle: { export in
                    toggleReviewTemplateExport(template.id, export: export)
                }
            )

            TextField("Template Name", text: reviewTemplateTitleBinding(for: template))
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Picker("Cadence", selection: reviewTemplateCadenceBinding(for: template)) {
                    ForEach(SnapshotCadence.allCases) { cadence in
                        Text(cadence.rawValue).tag(cadence)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Pin", isOn: reviewTemplatePinnedBinding(for: template))
                    .toggleStyle(.checkbox)
            }

            HStack(spacing: 8) {
                Button("Apply") {
                    applyReviewTemplate(template)
                }
                .buttonStyle(.borderedProminent)
                .tint(dashboardTint(for: template.preset))

                Button("Save Run") {
                    saveReviewTemplateSnapshot(template, stats: stats)
                }
                .buttonStyle(.bordered)

                Button("Overwrite") {
                    overwriteReviewTemplate(template.id)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    deleteReviewTemplate(template.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(width: 290, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(dashboardTint(for: template.preset).opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(dashboardTint(for: template.preset).opacity(0.18), lineWidth: 1)
        )
    }

    private func templateExportSelection(
        selectedExports: Set<DashboardTemplateExport>,
        toggle: @escaping (DashboardTemplateExport) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preferred Exports")
                .font(.caption2)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                ForEach(DashboardTemplateExport.allCases) { export in
                    Button {
                        toggle(export)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedExports.contains(export) ? "checkmark.circle.fill" : "circle")
                            Text(export.rawValue)
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var snapshotSection: some View {
        GroupBox("Saved Snapshots") {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(filteredSnapshots.count) saved review snapshots")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Cadence", selection: $cadenceFilter) {
                            ForEach(SnapshotCadenceFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    ForEach(filteredSnapshots.prefix(6)) { snapshot in
                        Button {
                            selectedSnapshotID = snapshot.id
                            comparisonSnapshotID = defaultComparisonSnapshotID(for: snapshot.id)
                            selectedTrendFocus = nil
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(snapshot.displayTitle)
                                            .fontWeight(.medium)
                                        if snapshot.isPinned {
                                            Image(systemName: "pin.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                        }
                                    }
                                    baselinePill(snapshot.cadence.rawValue, color: snapshot.cadence.color)
                                        .font(.caption2)
                                    Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(snapshot.headline)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Text(snapshotReviewSummary(snapshot))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
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
                            Button(selectedSnapshot.isPinned ? "Unpin" : "Pin") {
                                togglePinnedSnapshot(selectedSnapshot.id)
                            }
                            .buttonStyle(.bordered)

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

                        TextField("Snapshot Label", text: snapshotTitleBinding(for: selectedSnapshot))
                            .textFieldStyle(.roundedBorder)

                        Picker("Review Cadence", selection: snapshotCadenceBinding(for: selectedSnapshot)) {
                            ForEach(SnapshotCadence.allCases) { cadence in
                                Text(cadence.rawValue).tag(cadence)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(selectedSnapshot.headline)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            baselinePill("\(selectedSnapshot.flaggedTaskCount) flagged", color: selectedSnapshot.flaggedTaskCount > 0 ? .orange : .secondary)
                            baselinePill("\(selectedSnapshot.annotatedTaskCount) annotated", color: selectedSnapshot.annotatedTaskCount > 0 ? .blue : .secondary)
                            baselinePill("\(selectedSnapshot.unresolvedIssueCount) unresolved", color: selectedSnapshot.unresolvedIssueCount > 0 ? .red : .green)
                            baselinePill("\(selectedSnapshot.followUpIssueCount) follow-up", color: selectedSnapshot.followUpIssueCount > 0 ? .orange : .green)
                        }
                        .font(.caption2)

                        if snapshots.count > 1 {
                            snapshotTrendSection(for: selectedSnapshot)
                        }

                        if snapshots.count > 1 {
                            snapshotComparisonSection(for: selectedSnapshot)
                        }

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

    private func snapshotTrendSection(for snapshot: DashboardSnapshot) -> some View {
        let history = snapshotHistoryWindow(for: snapshot.id)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Recent Review Trends")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 10) {
                snapshotTrendCard(
                    title: "Open Issues",
                    values: history.map(\.unresolvedIssueCount),
                    accent: .red,
                    isSelected: selectedTrendFocus == .openIssues
                ) {
                    focusTrend(.openIssues, using: history)
                }
                snapshotTrendCard(
                    title: "Follow-Up Load",
                    values: history.map(\.followUpIssueCount),
                    accent: .orange,
                    isSelected: selectedTrendFocus == .followUp
                ) {
                    focusTrend(.followUp, using: history)
                }
                snapshotTrendCard(
                    title: "Flagged Tasks",
                    values: history.map(\.flaggedTaskCount),
                    accent: .orange,
                    isSelected: selectedTrendFocus == .flagged
                ) {
                    focusTrend(.flagged, using: history)
                }
                snapshotTrendCard(
                    title: "Annotated Tasks",
                    values: history.map(\.annotatedTaskCount),
                    accent: .blue,
                    isSelected: selectedTrendFocus == .annotations
                ) {
                    focusTrend(.annotations, using: history)
                }
            }

            Text("Window: \(history.count) snapshots from \(history.first?.createdAt.formatted(date: .abbreviated, time: .omitted) ?? "") to \(history.last?.createdAt.formatted(date: .abbreviated, time: .omitted) ?? "")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func snapshotTrendCard(
        title: String,
        values: [Int],
        accent: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let current = values.last ?? 0
        let baseline = values.first ?? current
        let delta = current - baseline

        return Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(current)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(delta > 0 ? accent : delta < 0 ? .green : .primary)
                baselinePill(trendDeltaLabel(delta), color: delta > 0 ? accent : delta < 0 ? .green : .secondary)
                Text(values.map(String.init).joined(separator: " • "))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(accent.opacity(isSelected ? 0.18 : 0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.6) : .clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func snapshotComparisonSection(for snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("Compare Against")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Compare Against", selection: comparisonSnapshotBinding(for: snapshot)) {
                    ForEach(comparisonSnapshotOptions(for: snapshot.id)) { candidate in
                        Text(snapshotLabel(candidate)).tag(Optional(candidate.id))
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                if let comparisonSnapshot {
                    Text("Baseline: \(comparisonSnapshot.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let comparison = snapshotComparison {
                    Button("Export Delta") {
                        exportSnapshotComparison(comparison)
                    }
                    .buttonStyle(.bordered)
                }
            }

                if let comparison = snapshotComparison {
                    HStack(spacing: 8) {
                        snapshotDeltaPill("Flagged", delta: comparison.flaggedDelta, accent: .orange)
                        snapshotDeltaPill("Annotated", delta: comparison.annotatedDelta, accent: .blue)
                        snapshotDeltaPill("Open", delta: comparison.unresolvedDelta, accent: .red)
                    snapshotDeltaPill("Follow-Up", delta: comparison.followUpDelta, accent: .orange)
                }
                .font(.caption2)

                if comparison.hasLayoutChanges {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Layout Changes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(snapshotLayoutSummary(comparison))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let selectedTrendFocus {
                    snapshotFocusedChangeSection(comparison: comparison, focus: selectedTrendFocus)
                }

                if comparison.hasReviewChanges {
                    snapshotChangeList("New Flagged Tasks", items: comparison.addedFlaggedTasks, color: .orange)
                    snapshotChangeList("Cleared Flags", items: comparison.clearedFlaggedTasks, color: .secondary)
                    snapshotChangeList("New Annotations", items: comparison.addedAnnotatedTasks, color: .blue)
                    snapshotChangeList("Cleared Annotations", items: comparison.clearedAnnotatedTasks, color: .secondary)
                    snapshotChangeList("New Open Issues", items: comparison.newOpenIssues, color: .red)
                    snapshotChangeList("Resolved Issues", items: comparison.resolvedIssues, color: .green)
                    snapshotChangeList("Added Follow-Up", items: comparison.addedFollowUpTasks, color: .orange)
                    snapshotChangeList("Cleared Follow-Up", items: comparison.clearedFollowUpTasks, color: .green)
                } else {
                    Text("No review-state changes between these snapshots.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func snapshotChangeList(_ title: String, items: [String], color: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(color)
                ForEach(Array(items.prefix(4)), id: \.self) { item in
                    Text("• \(item)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if items.count > 4 {
                    Text("• ... \(items.count - 4) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func snapshotFocusedChangeSection(comparison: DashboardSnapshotComparison, focus: SnapshotTrendFocus) -> some View {
        let details = focusedTrendDetails(for: comparison, focus: focus)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(focus.rawValue) Focus")
                    .font(.caption)
                    .foregroundStyle(details.color)
                Spacer()
                if !details.deltaText.isEmpty {
                    Text(details.deltaText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if details.primary.isEmpty && details.secondary.isEmpty {
                Text("No focused churn in this comparison.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                if !details.primary.isEmpty {
                    snapshotFocusedItems(details.primaryTitle, items: details.primary)
                }
                if !details.secondary.isEmpty {
                    snapshotFocusedItems(details.secondaryTitle, items: details.secondary)
                }
            }
        }
        .padding(10)
        .background(details.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func snapshotFocusedItems(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(Array(items.prefix(5)), id: \.self) { item in
                Text("• \(item)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if items.count > 5 {
                Text("• ... \(items.count - 5) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
        audienceMetrics(stats: stats, preset: audiencePreset)
    }

    private func audienceMetrics(stats: ProjectStats, preset: DashboardAudiencePreset) -> [DashboardAudienceMetric] {
        switch preset {
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
        audienceDetail(stats: stats, preset: audiencePreset)
    }

    private func audienceDetail(stats: ProjectStats, preset: DashboardAudiencePreset) -> String {
        switch preset {
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
        taskStatusTitle(for: currentAudienceConfiguration)
    }

    private func taskStatusTitle(for configuration: DashboardAudienceConfiguration) -> String {
        switch configuration.taskScope {
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

    private var flaggedTaskIDs: Set<Int> {
        guard !flaggedTaskIDsData.isEmpty else { return [] }
        return (try? JSONDecoder().decode(Set<Int>.self, from: flaggedTaskIDsData)) ?? []
    }

    private var unresolvedIssueCount: Int {
        reviewAnnotations.values.filter(\.isUnresolved).count
    }

    private var followUpIssueCount: Int {
        reviewAnnotations.values.filter(\.needsFollowUp).count
    }

    private func snapshotLabel(_ snapshot: DashboardSnapshot) -> String {
        "\(snapshot.displayTitle) · \(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func comparisonSnapshotOptions(for selectedID: UUID) -> [DashboardSnapshot] {
        snapshots.filter { $0.id != selectedID }
    }

    private func defaultComparisonSnapshotID(for selectedID: UUID?) -> UUID? {
        guard let selectedID,
              let selectedIndex = snapshots.firstIndex(where: { $0.id == selectedID }) else {
            return snapshots.dropFirst().first?.id
        }

        if snapshots.indices.contains(selectedIndex + 1) {
            return snapshots[selectedIndex + 1].id
        }
        if selectedIndex > 0 {
            return snapshots[selectedIndex - 1].id
        }
        return nil
    }

    private func comparisonSnapshotBinding(for selectedSnapshot: DashboardSnapshot) -> Binding<UUID?> {
        Binding(
            get: {
                if let comparisonSnapshotID,
                   comparisonSnapshotID != selectedSnapshot.id,
                   comparisonSnapshotOptions(for: selectedSnapshot.id).contains(where: { $0.id == comparisonSnapshotID }) {
                    return comparisonSnapshotID
                }
                return comparisonSnapshotOptions(for: selectedSnapshot.id).first?.id
            },
            set: { newValue in
                comparisonSnapshotID = newValue
            }
        )
    }

    private func snapshotHistoryWindow(for selectedID: UUID, limit: Int = 5) -> [DashboardSnapshot] {
        guard let selectedIndex = snapshots.firstIndex(where: { $0.id == selectedID }) else { return [] }
        let olderWindow = Array(snapshots[selectedIndex...].prefix(limit))
        return olderWindow.reversed()
    }

    private func focusTrend(_ focus: SnapshotTrendFocus, using history: [DashboardSnapshot]) {
        selectedTrendFocus = focus
        if let baseline = history.first, let current = history.last, baseline.id != current.id {
            comparisonSnapshotID = baseline.id
        }
    }

    private func buildSnapshotComparison(selected: DashboardSnapshot, baseline: DashboardSnapshot) -> DashboardSnapshotComparison {
        let selectedFlagged = Set(selected.flaggedTaskIDs)
        let baselineFlagged = Set(baseline.flaggedTaskIDs)
        let selectedAnnotated = Set(selected.reviewAnnotations.keys)
        let baselineAnnotated = Set(baseline.reviewAnnotations.keys)
        let selectedOpenIssues = Set(selected.reviewAnnotations.filter { $0.value.isUnresolved }.map(\.key))
        let baselineOpenIssues = Set(baseline.reviewAnnotations.filter { $0.value.isUnresolved }.map(\.key))
        let selectedFollowUp = Set(selected.reviewAnnotations.filter { $0.value.needsFollowUp }.map(\.key))
        let baselineFollowUp = Set(baseline.reviewAnnotations.filter { $0.value.needsFollowUp }.map(\.key))

        return DashboardSnapshotComparison(
            selected: selected,
            baseline: baseline,
            addedFlaggedTasks: taskNames(for: selectedFlagged.subtracting(baselineFlagged)),
            clearedFlaggedTasks: taskNames(for: baselineFlagged.subtracting(selectedFlagged)),
            addedAnnotatedTasks: taskNames(for: selectedAnnotated.subtracting(baselineAnnotated)),
            clearedAnnotatedTasks: taskNames(for: baselineAnnotated.subtracting(selectedAnnotated)),
            newOpenIssues: taskNames(for: selectedOpenIssues.subtracting(baselineOpenIssues)),
            resolvedIssues: taskNames(for: baselineOpenIssues.subtracting(selectedOpenIssues)),
            addedFollowUpTasks: taskNames(for: selectedFollowUp.subtracting(baselineFollowUp)),
            clearedFollowUpTasks: taskNames(for: baselineFollowUp.subtracting(selectedFollowUp)),
            flaggedDelta: selected.flaggedTaskCount - baseline.flaggedTaskCount,
            annotatedDelta: selected.annotatedTaskCount - baseline.annotatedTaskCount,
            unresolvedDelta: selected.unresolvedIssueCount - baseline.unresolvedIssueCount,
            followUpDelta: selected.followUpIssueCount - baseline.followUpIssueCount,
            presetChanged: selected.preset != baseline.preset,
            taskScopeChanged: selected.configuration.taskScope != baseline.configuration.taskScope,
            milestoneLimitChanged: selected.configuration.milestoneLimit != baseline.configuration.milestoneLimit,
            widgetChangeCount: Set(selected.configuration.visibleWidgets).symmetricDifference(Set(baseline.configuration.visibleWidgets)).count
        )
    }

    private func taskNames(for ids: Set<Int>) -> [String] {
        ids.compactMap { project.tasksByID[$0]?.displayName }.sorted()
    }

    private struct FocusedTrendDetails {
        let color: Color
        let deltaText: String
        let primaryTitle: String
        let primary: [String]
        let secondaryTitle: String
        let secondary: [String]
    }

    private func focusedTrendDetails(for comparison: DashboardSnapshotComparison, focus: SnapshotTrendFocus) -> FocusedTrendDetails {
        switch focus {
        case .openIssues:
            return FocusedTrendDetails(
                color: .red,
                deltaText: "Open \(signedDeltaText(comparison.unresolvedDelta))",
                primaryTitle: "New Open Issues",
                primary: comparison.newOpenIssues,
                secondaryTitle: "Resolved Issues",
                secondary: comparison.resolvedIssues
            )
        case .followUp:
            return FocusedTrendDetails(
                color: .orange,
                deltaText: "Follow-Up \(signedDeltaText(comparison.followUpDelta))",
                primaryTitle: "Added Follow-Up",
                primary: comparison.addedFollowUpTasks,
                secondaryTitle: "Cleared Follow-Up",
                secondary: comparison.clearedFollowUpTasks
            )
        case .flagged:
            return FocusedTrendDetails(
                color: .orange,
                deltaText: "Flags \(signedDeltaText(comparison.flaggedDelta))",
                primaryTitle: "New Flagged Tasks",
                primary: comparison.addedFlaggedTasks,
                secondaryTitle: "Cleared Flags",
                secondary: comparison.clearedFlaggedTasks
            )
        case .annotations:
            return FocusedTrendDetails(
                color: .blue,
                deltaText: "Annotations \(signedDeltaText(comparison.annotatedDelta))",
                primaryTitle: "New Annotations",
                primary: comparison.addedAnnotatedTasks,
                secondaryTitle: "Cleared Annotations",
                secondary: comparison.clearedAnnotatedTasks
            )
        }
    }

    private func trendDeltaLabel(_ delta: Int) -> String {
        if delta > 0 {
            return "+\(delta) vs oldest"
        }
        if delta < 0 {
            return "\(delta) vs oldest"
        }
        return "No change"
    }

    private func snapshotTitleBinding(for snapshot: DashboardSnapshot) -> Binding<String> {
        Binding(
            get: { snapshot.customTitle ?? "" },
            set: { newValue in
                updateSnapshot(snapshot.id) { storedSnapshot in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    storedSnapshot.customTitle = trimmed.isEmpty ? nil : trimmed
                }
            }
        )
    }

    private func snapshotCadenceBinding(for snapshot: DashboardSnapshot) -> Binding<SnapshotCadence> {
        Binding(
            get: { snapshot.cadence },
            set: { newValue in
                updateSnapshot(snapshot.id) { storedSnapshot in
                    storedSnapshot.cadence = newValue
                }
            }
        )
    }

    private func togglePinnedSnapshot(_ id: UUID) {
        updateSnapshot(id) { snapshot in
            snapshot.isPinned.toggle()
        }
    }

    private func defaultSnapshotCadence(for preset: DashboardAudiencePreset) -> SnapshotCadence {
        switch preset {
        case .projectManager:
            return .weeklyPM
        case .executive:
            return .executive
        case .scheduler:
            return .baselineCheck
        case .resourceManager:
            return .adHoc
        }
    }

    private var workResourceCount: Int {
        project.resources.filter { $0.type == "work" || $0.type == nil }.count
    }

    private var resourceRiskCount: Int {
        projectAnalysis?.resourceIssues.count ?? 0
    }

    private var resourceErrorCount: Int {
        projectAnalysis?.resourceIssues.filter { $0.severity == .error }.count ?? 0
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
        filteredWorkTasks(for: currentAudienceConfiguration.taskScope)
    }

    private func filteredWorkTasks(for scope: DashboardTaskScope) -> [ProjectTask] {
        let today = Calendar.current.startOfDay(for: Date())
        let workTasks = project.tasks.filter { $0.summary != true && $0.milestone != true }

        switch scope {
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

    private func filteredTaskTotal(for configuration: DashboardAudienceConfiguration) -> Int {
        filteredWorkTasks(for: configuration.taskScope).count
    }

    private var filteredCompletedTasks: Int {
        filteredWorkTasks.filter { ($0.percentComplete ?? 0) >= 100 }.count
    }

    private func filteredCompletedTasks(for configuration: DashboardAudienceConfiguration) -> Int {
        filteredWorkTasks(for: configuration.taskScope).filter { ($0.percentComplete ?? 0) >= 100 }.count
    }

    private var filteredInProgressTasks: Int {
        filteredWorkTasks.filter {
            let pct = $0.percentComplete ?? 0
            return pct > 0 && pct < 100
        }.count
    }

    private func filteredInProgressTasks(for configuration: DashboardAudienceConfiguration) -> Int {
        filteredWorkTasks(for: configuration.taskScope).filter {
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

    private func filteredOverdueTasks(for configuration: DashboardAudienceConfiguration) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        return filteredWorkTasks(for: configuration.taskScope).filter {
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

    private func filteredNotStartedTasks(for configuration: DashboardAudienceConfiguration) -> Int {
        let scopedTasks = filteredWorkTasks(for: configuration.taskScope)
        let overdueIDs = Set(scopedTasks.filter {
            ($0.percentComplete ?? 0) < 100 &&
            ($0.finishDate?.compare(Calendar.current.startOfDay(for: Date())) == .orderedAscending)
        }.map(\.uniqueID))

        return scopedTasks.filter {
            ($0.percentComplete ?? 0) == 0 && !overdueIDs.contains($0.uniqueID)
        }.count
    }

    private func displayedMilestones(_ stats: ProjectStats) -> [ProjectTask] {
        Array(stats.upcomingMilestones.prefix(currentAudienceConfiguration.milestoneLimit))
    }

    private func displayedMilestones(_ stats: ProjectStats, configuration: DashboardAudienceConfiguration) -> [ProjectTask] {
        Array(stats.upcomingMilestones.prefix(configuration.milestoneLimit))
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

    private func decodeReviewTemplates() -> [DashboardReviewTemplate] {
        guard !reviewTemplateData.isEmpty else { return [] }
        return (try? JSONDecoder().decode([DashboardReviewTemplate].self, from: reviewTemplateData)) ?? []
    }

    private func persistReviewTemplates(_ templates: [DashboardReviewTemplate]) {
        reviewTemplateData = (try? JSONEncoder().encode(templates)) ?? Data()
    }

    private func updateReviewTemplate(_ id: UUID, update: (inout DashboardReviewTemplate) -> Void) {
        var storedTemplates = decodeReviewTemplates()
        guard let index = storedTemplates.firstIndex(where: { $0.id == id }) else { return }
        update(&storedTemplates[index])
        persistReviewTemplates(storedTemplates)
    }

    private func orderedTemplateExports(from exports: Set<DashboardTemplateExport>) -> [DashboardTemplateExport] {
        DashboardTemplateExport.allCases.filter { exports.contains($0) }
    }

    private func appendReminderEvent(
        _ event: ReviewReminderEvent,
        to template: inout DashboardReviewTemplate
    ) {
        template.reminderEvents.insert(event, at: 0)
        template.reminderEvents = Array(template.reminderEvents.prefix(10))
    }

    private func latestSnapshot(for template: DashboardReviewTemplate) -> DashboardSnapshot? {
        snapshots.first(where: { $0.sourceReviewTemplateID == template.id })
    }

    private var reviewQueueEntries: [ReviewQueueEntry] {
        reviewTemplates
            .filter { $0.cadence.reviewIntervalDays != nil }
            .map { template in
                let lastRun = latestSnapshot(for: template)
                let dueDate = lastRun.flatMap { nextReviewDate(for: template, from: $0.createdAt) }
                let daysUntilDue = dueDate.map { daysUntilStartOfDay($0) }
                return ReviewQueueEntry(
                    template: template,
                    lastRun: lastRun,
                    dueDate: dueDate,
                    daysUntilDue: daysUntilDue
                )
            }
            .sorted(by: compareReviewQueueEntries)
    }

    private var activeReviewQueueEntries: [ReviewQueueEntry] {
        reviewQueueEntries.filter(isQueueAttentionNeeded)
    }

    private var suppressedReviewQueueEntries: [ReviewQueueEntry] {
        reviewQueueEntries.filter(isSuppressedQueueAttention)
    }

    private var frequentlySnoozedQueueEntries: [ReviewQueueEntry] {
        reviewQueueEntries
            .filter { reminderEventCount(for: $0.template, action: .snoozed) >= 2 }
            .sorted {
                let lhsCount = reminderEventCount(for: $0.template, action: .snoozed)
                let rhsCount = reminderEventCount(for: $1.template, action: .snoozed)
                if lhsCount != rhsCount {
                    return lhsCount > rhsCount
                }
                return compareReviewQueueEntries(lhs: $0, rhs: $1)
            }
    }

    private var overdueReviewQueueEntries: [ReviewQueueEntry] {
        reviewQueueEntries
            .filter { ($0.daysUntilDue ?? 1) < 0 }
            .sorted {
                let lhsDays = $0.daysUntilDue ?? 0
                let rhsDays = $1.daysUntilDue ?? 0
                if lhsDays != rhsDays {
                    return lhsDays < rhsDays
                }
                return compareReviewQueueEntries(lhs: $0, rhs: $1)
            }
    }

    private func reviewQueueEntries(for focus: ReviewQueueFocus) -> [ReviewQueueEntry] {
        switch focus {
        case .oftenSnoozed:
            return frequentlySnoozedQueueEntries
        case .overdue:
            return overdueReviewQueueEntries
        case .hiddenDue:
            return suppressedReviewQueueEntries
        }
    }

    private func toggleReviewQueueFocus(_ focus: ReviewQueueFocus) {
        if selectedReviewQueueFocus == focus {
            selectedReviewQueueFocus = nil
        } else {
            selectedReviewQueueFocus = focus
        }
        reviewQueueActionFeedback = nil
    }

    private func reviewQueueFocusAccent(for focus: ReviewQueueFocus?) -> Color {
        switch focus {
        case .oftenSnoozed:
            return .orange
        case .overdue:
            return .red
        case .hiddenDue:
            return .secondary
        case nil:
            return .accentColor
        }
    }

    private func setReviewQueueActionFeedback(message: String, color: Color, icon: String) {
        reviewQueueActionFeedback = ReviewQueueActionFeedback(
            message: message,
            color: color,
            icon: icon
        )
    }

    private func compareReviewQueueEntries(lhs: ReviewQueueEntry, rhs: ReviewQueueEntry) -> Bool {
        let lhsRank = reviewQueueRank(for: lhs)
        let rhsRank = reviewQueueRank(for: rhs)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        switch (lhs.daysUntilDue, rhs.daysUntilDue) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        default:
            return lhs.template.createdAt > rhs.template.createdAt
        }
    }

    private func reviewQueueRank(for entry: ReviewQueueEntry) -> Int {
        if entry.lastRun == nil { return 0 }
        guard let daysUntilDue = entry.daysUntilDue else { return 3 }
        if daysUntilDue < 0 { return 0 }
        if daysUntilDue == 0 { return 1 }
        return 2
    }

    private func reviewQueueLabel(for entry: ReviewQueueEntry) -> (text: String, color: Color)? {
        if entry.lastRun == nil {
            return ("Needs first run", .orange)
        }
        guard let dueDate = entry.dueDate,
              let daysUntilDue = entry.daysUntilDue else {
            return nil
        }

        if daysUntilDue < 0 {
            return ("Overdue by \(-daysUntilDue)d", .red)
        }
        if daysUntilDue == 0 {
            return ("Due today", .orange)
        }
        if daysUntilDue <= 7 {
            return ("Due \(dueDate.formatted(date: .abbreviated, time: .omitted))", .green)
        }
        return ("Later \(dueDate.formatted(date: .abbreviated, time: .omitted))", .secondary)
    }

    private func isQueueAttentionNeeded(for entry: ReviewQueueEntry) -> Bool {
        guard let reminderKey = reminderKey(for: entry) else { return false }
        guard !isReminderSuppressed(for: entry.template, reminderKey: reminderKey) else { return false }
        return needsQueueAttentionWithoutSuppression(for: entry)
    }

    private func isSuppressedQueueAttention(for entry: ReviewQueueEntry) -> Bool {
        guard let reminderKey = reminderKey(for: entry) else { return false }
        guard isReminderSuppressed(for: entry.template, reminderKey: reminderKey) else { return false }
        return needsQueueAttentionWithoutSuppression(for: entry)
    }

    private func needsQueueAttentionWithoutSuppression(for entry: ReviewQueueEntry) -> Bool {
        guard entry.lastRun != nil else { return true }
        guard let daysUntilDue = entry.daysUntilDue else { return false }
        return daysUntilDue <= 7
    }

    private func isReminderSuppressed(for template: DashboardReviewTemplate, reminderKey: String?) -> Bool {
        if let reminderKey, template.dismissedReminderKey == reminderKey {
            return true
        }
        if let snoozedUntil = template.reminderSnoozedUntil,
           Date() < snoozedUntil {
            return true
        }
        return false
    }

    private func suppressionSummary(for entry: ReviewQueueEntry) -> String? {
        if let snoozedUntil = entry.template.reminderSnoozedUntil,
           Date() < snoozedUntil {
            return "Snoozed until \(snoozedUntil.formatted(date: .abbreviated, time: .omitted))"
        }
        if let reminderKey = reminderKey(for: entry),
           entry.template.dismissedReminderKey == reminderKey {
            return "Dismissed for the current review cycle"
        }
        return nil
    }

    private func reminderEventCount(
        for template: DashboardReviewTemplate,
        action: ReviewReminderEvent.Action
    ) -> Int {
        template.reminderEvents.filter { $0.action == action }.count
    }

    private func overdueSummary(for entry: ReviewQueueEntry) -> String {
        guard let daysUntilDue = entry.daysUntilDue, daysUntilDue < 0 else {
            return "Needs attention"
        }
        return "\(-daysUntilDue)d overdue"
    }

    private func nextReviewDate(for template: DashboardReviewTemplate, from lastRun: Date) -> Date? {
        guard let intervalDays = template.cadence.reviewIntervalDays else { return nil }
        return Calendar.current.date(byAdding: .day, value: intervalDays, to: lastRun)
    }

    private func daysUntilStartOfDay(_ date: Date) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        let dueDay = Calendar.current.startOfDay(for: date)
        return Calendar.current.dateComponents([.day], from: today, to: dueDay).day ?? 0
    }

    private func reminderKey(for entry: ReviewQueueEntry) -> String? {
        if entry.lastRun == nil {
            return "first-run"
        }
        guard let dueDate = entry.dueDate else { return nil }
        return "due:\(Calendar.current.startOfDay(for: dueDate).formatted(date: .numeric, time: .omitted))"
    }

    private func templateDueLabel(for template: DashboardReviewTemplate) -> (text: String, color: Color)? {
        guard let lastRun = latestSnapshot(for: template),
              let dueDate = nextReviewDate(for: template, from: lastRun.createdAt) else {
            return nil
        }

        let offsetDays = daysUntilStartOfDay(dueDate)

        if offsetDays < 0 {
            return ("Overdue by \(-offsetDays)d", .red)
        }
        if offsetDays == 0 {
            return ("Due today", .orange)
        }
        return ("Next review in \(offsetDays)d", offsetDays <= 2 ? .orange : .green)
    }

    private func decodeSnapshots() -> [DashboardSnapshot] {
        guard !snapshotData.isEmpty else { return [] }
        return (try? JSONDecoder().decode([DashboardSnapshot].self, from: snapshotData)) ?? []
    }

    private func persistSnapshots(_ snapshots: [DashboardSnapshot]) {
        snapshotData = (try? JSONEncoder().encode(snapshots)) ?? Data()
    }

    private func updateSnapshot(_ id: UUID, update: (inout DashboardSnapshot) -> Void) {
        var storedSnapshots = decodeSnapshots()
        guard let index = storedSnapshots.firstIndex(where: { $0.id == id }) else { return }
        update(&storedSnapshots[index])
        persistSnapshots(storedSnapshots)
    }

    private func persistFlaggedTaskIDs(_ ids: Set<Int>) {
        flaggedTaskIDsData = (try? JSONEncoder().encode(ids)) ?? Data()
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

    @ViewBuilder
    private func reminderActivityStrip(for template: DashboardReviewTemplate, limit: Int) -> some View {
        let events = Array(template.reminderEvents.prefix(limit))

        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Reminder Activity")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(events) { event in
                        reminderEventPill(event)
                    }
                }
            }
        }
    }

    private func reminderEventPill(_ event: ReviewReminderEvent) -> some View {
        let style = reminderEventStyle(for: event.action)
        let label = "\(style.title) \(event.createdAt.formatted(date: .abbreviated, time: .omitted))"

        return Label(label, systemImage: style.icon)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(style.color.opacity(0.12))
            .foregroundStyle(style.color)
            .clipShape(Capsule())
            .help(event.detail)
    }

    private func reminderEventStyle(for action: ReviewReminderEvent.Action) -> (title: String, icon: String, color: Color) {
        switch action {
        case .snoozed:
            return ("Snoozed", "moon.zzz.fill", .orange)
        case .dismissed:
            return ("Dismissed", "bell.slash.fill", .secondary)
        case .restored:
            return ("Restored", "arrow.uturn.backward.circle.fill", .blue)
        case .completed:
            return ("Completed", "checkmark.circle.fill", .green)
        }
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

    private func snapshotReviewSummary(_ snapshot: DashboardSnapshot) -> String {
        "\(snapshot.flaggedTaskCount) flagged · \(snapshot.unresolvedIssueCount) unresolved · \(snapshot.followUpIssueCount) follow-up"
    }

    private func snapshotLayoutSummary(_ comparison: DashboardSnapshotComparison) -> String {
        var parts: [String] = []
        if comparison.presetChanged {
            parts.append("Audience changed from \(comparison.baseline.preset.rawValue) to \(comparison.selected.preset.rawValue)")
        }
        if comparison.taskScopeChanged {
            parts.append("task filter changed")
        }
        if comparison.milestoneLimitChanged {
            parts.append("milestone count changed")
        }
        if comparison.widgetChangeCount > 0 {
            parts.append("\(comparison.widgetChangeCount) widget settings changed")
        }
        return parts.joined(separator: " · ")
    }

    private func snapshotDeltaPill(_ label: String, delta: Int, accent: Color) -> some View {
        let text: String
        let color: Color

        if delta > 0 {
            text = "\(label) +\(delta)"
            color = accent
        } else if delta < 0 {
            text = "\(label) \(delta)"
            color = .green
        } else {
            text = "\(label) 0"
            color = .secondary
        }

        return baselinePill(text, color: color)
    }

    private func signedDeltaText(_ delta: Int) -> String {
        if delta > 0 {
            return "+\(delta)"
        }
        return "\(delta)"
    }

    private func snapshotChangeMarkdownLines(title: String, items: [String]) -> [String] {
        guard !items.isEmpty else { return [] }

        var lines = ["", "## \(title)"]
        lines.append(contentsOf: items.map { "- \($0)" })
        return lines
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
        saveSnapshot(
            stats: stats,
            preset: audiencePreset,
            configuration: currentAudienceConfiguration,
            cadence: defaultSnapshotCadence(for: audiencePreset)
        )
    }

    private func saveSnapshotTemplate(_ template: SnapshotTemplate, stats: ProjectStats) {
        saveTemplateRun(
            title: template.rawValue,
            stats: stats,
            preset: template.preset,
            configuration: .default(for: template.preset),
            cadence: template.cadence,
            isPinned: template.isPinned
        )
    }

    private func applySnapshotTemplate(_ template: SnapshotTemplate) {
        applyTemplate(preset: template.preset, configuration: .default(for: template.preset))
        appliedReviewTemplateID = nil
    }

    private func saveCurrentReviewTemplate() {
        let trimmedTitle = customTemplateTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let template = DashboardReviewTemplate(
            id: UUID(),
            createdAt: Date(),
            title: trimmedTitle,
            preset: audiencePreset,
            configuration: currentAudienceConfiguration,
            cadence: customTemplateCadence,
            isPinned: customTemplatePinned,
            preferredExports: orderedTemplateExports(from: customTemplatePreferredExports.isEmpty ? Set(audiencePreset.defaultTemplateExports) : customTemplatePreferredExports),
            reminderSnoozedUntil: nil,
            dismissedReminderKey: nil,
            reminderEvents: []
        )

        var storedTemplates = reviewTemplates
        storedTemplates.insert(template, at: 0)
        storedTemplates = Array(storedTemplates.prefix(10))
        persistReviewTemplates(storedTemplates)
        customTemplateTitle = ""
        customTemplateCadence = defaultSnapshotCadence(for: audiencePreset)
        customTemplatePinned = true
        customTemplatePreferredExports = Set(audiencePreset.defaultTemplateExports)
    }

    private func saveReviewTemplateSnapshot(_ template: DashboardReviewTemplate, stats: ProjectStats) {
        saveTemplateRun(
            title: template.title,
            stats: stats,
            preset: template.preset,
            configuration: template.configuration,
            cadence: template.cadence,
            isPinned: template.isPinned,
            sourceReviewTemplateID: template.id
        )
        updateReviewTemplate(template.id) { storedTemplate in
            storedTemplate.reminderSnoozedUntil = nil
            storedTemplate.dismissedReminderKey = nil
            appendReminderEvent(
                ReviewReminderEvent(
                    id: UUID(),
                    action: .completed,
                    createdAt: Date(),
                    detail: "Saved review run",
                    reminderKey: nil
                ),
                to: &storedTemplate
            )
        }
    }

    private func saveReviewTemplateSnapshots(for entries: [ReviewQueueEntry], stats: ProjectStats) {
        for entry in entries {
            saveReviewTemplateSnapshot(entry.template, stats: stats)
        }
        guard !entries.isEmpty else { return }
        setReviewQueueActionFeedback(
            message: "\(entries.count) templates saved as review runs",
            color: .green,
            icon: "checkmark.circle.fill"
        )
    }

    private func applyReviewTemplate(_ template: DashboardReviewTemplate) {
        applyTemplate(preset: template.preset, configuration: template.configuration)
        customTemplatePreferredExports = Set(template.preferredExports)
        appliedReviewTemplateID = template.id
    }

    private func reviewTemplateTitleBinding(for template: DashboardReviewTemplate) -> Binding<String> {
        Binding(
            get: { template.title },
            set: { newValue in
                updateReviewTemplate(template.id) { storedTemplate in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    storedTemplate.title = trimmed.isEmpty ? storedTemplate.title : trimmed
                }
            }
        )
    }

    private func reviewTemplateCadenceBinding(for template: DashboardReviewTemplate) -> Binding<SnapshotCadence> {
        Binding(
            get: { template.cadence },
            set: { newValue in
                updateReviewTemplate(template.id) { storedTemplate in
                    storedTemplate.cadence = newValue
                }
            }
        )
    }

    private func reviewTemplatePinnedBinding(for template: DashboardReviewTemplate) -> Binding<Bool> {
        Binding(
            get: { template.isPinned },
            set: { newValue in
                updateReviewTemplate(template.id) { storedTemplate in
                    storedTemplate.isPinned = newValue
                }
            }
        )
    }

    private func toggleCustomTemplateExport(_ export: DashboardTemplateExport) {
        if customTemplatePreferredExports.contains(export) {
            customTemplatePreferredExports.remove(export)
        } else {
            customTemplatePreferredExports.insert(export)
        }
    }

    private func toggleReviewTemplateExport(_ id: UUID, export: DashboardTemplateExport) {
        updateReviewTemplate(id) { storedTemplate in
            var exports = Set(storedTemplate.preferredExports)
            if exports.contains(export) {
                exports.remove(export)
            } else {
                exports.insert(export)
            }
            storedTemplate.preferredExports = orderedTemplateExports(from: exports.isEmpty ? Set(storedTemplate.preset.defaultTemplateExports) : exports)
        }
    }

    private func overwriteReviewTemplate(_ id: UUID) {
        updateReviewTemplate(id) { storedTemplate in
            storedTemplate = DashboardReviewTemplate(
                id: storedTemplate.id,
                createdAt: storedTemplate.createdAt,
                title: storedTemplate.title,
                preset: audiencePreset,
                configuration: currentAudienceConfiguration,
                cadence: storedTemplate.cadence,
                isPinned: storedTemplate.isPinned,
                preferredExports: storedTemplate.preferredExports,
                reminderSnoozedUntil: storedTemplate.reminderSnoozedUntil,
                dismissedReminderKey: storedTemplate.dismissedReminderKey,
                reminderEvents: storedTemplate.reminderEvents
            )
        }
    }

    private func snoozeReminder(for id: UUID, days: Int) {
        guard let snoozedUntil = Calendar.current.date(byAdding: .day, value: days, to: Date()) else { return }
        updateReviewTemplate(id) { storedTemplate in
            storedTemplate.reminderSnoozedUntil = snoozedUntil
            storedTemplate.dismissedReminderKey = nil
            appendReminderEvent(
                ReviewReminderEvent(
                    id: UUID(),
                    action: .snoozed,
                    createdAt: Date(),
                    detail: "Snoozed for \(days)d",
                    reminderKey: nil
                ),
                to: &storedTemplate
            )
        }
    }

    private func snoozeReminders(for entries: [ReviewQueueEntry], days: Int) {
        for entry in entries {
            snoozeReminder(for: entry.template.id, days: days)
        }
        guard !entries.isEmpty else { return }
        setReviewQueueActionFeedback(
            message: "\(entries.count) templates snoozed for \(days)d",
            color: .orange,
            icon: "moon.zzz.fill"
        )
    }

    private func dismissReminder(for entry: ReviewQueueEntry) {
        guard let reminderKey = reminderKey(for: entry) else { return }
        updateReviewTemplate(entry.template.id) { storedTemplate in
            storedTemplate.dismissedReminderKey = reminderKey
            storedTemplate.reminderSnoozedUntil = nil
            appendReminderEvent(
                ReviewReminderEvent(
                    id: UUID(),
                    action: .dismissed,
                    createdAt: Date(),
                    detail: reviewQueueLabel(for: entry)?.text ?? "Dismissed reminder",
                    reminderKey: reminderKey
                ),
                to: &storedTemplate
            )
        }
    }

    private func restoreReminder(for id: UUID) {
        updateReviewTemplate(id) { storedTemplate in
            storedTemplate.dismissedReminderKey = nil
            storedTemplate.reminderSnoozedUntil = nil
            appendReminderEvent(
                ReviewReminderEvent(
                    id: UUID(),
                    action: .restored,
                    createdAt: Date(),
                    detail: "Reminder restored",
                    reminderKey: nil
                ),
                to: &storedTemplate
            )
        }
    }

    private func restoreReminders(for entries: [ReviewQueueEntry]) {
        for entry in entries {
            restoreReminder(for: entry.template.id)
        }
        guard !entries.isEmpty else { return }
        setReviewQueueActionFeedback(
            message: "\(entries.count) hidden reminders restored",
            color: .blue,
            icon: "arrow.uturn.backward.circle.fill"
        )
    }

    private func deleteReviewTemplate(_ id: UUID) {
        persistReviewTemplates(reviewTemplates.filter { $0.id != id })
        if appliedReviewTemplateID == id {
            appliedReviewTemplateID = nil
        }
    }

    private func applyTemplate(preset: DashboardAudiencePreset, configuration: DashboardAudienceConfiguration) {
        audiencePreset = preset
        var configurations = decodeAudienceConfigurations()
        configurations[preset.rawValue] = configuration
        audienceConfigurationData = (try? JSONEncoder().encode(configurations)) ?? Data()
        customTemplateCadence = defaultSnapshotCadence(for: preset)
        customTemplatePreferredExports = Set(preset.defaultTemplateExports)
        isCustomizationExpanded = false
    }

    private func performTemplateExport(_ export: DashboardTemplateExport, stats: ProjectStats) {
        switch export {
        case .audienceDashboard:
            exportAudienceDashboard(stats: stats)
        case .reviewPack:
            exportReviewPack()
        case .openIssues:
            exportOpenIssues()
        case .issuesCSV:
            exportOpenIssuesCSV()
        case .executiveSummary:
            exportExecutiveSummary(stats: stats)
        }
    }

    private func saveTemplateRun(
        title: String,
        stats: ProjectStats,
        preset: DashboardAudiencePreset,
        configuration: DashboardAudienceConfiguration,
        cadence: SnapshotCadence,
        isPinned: Bool,
        sourceReviewTemplateID: UUID? = nil
    ) {
        saveSnapshot(
            stats: stats,
            preset: preset,
            configuration: configuration,
            cadence: cadence,
            customTitle: title,
            isPinned: isPinned,
            sourceReviewTemplateID: sourceReviewTemplateID
        )
    }

    private func saveSnapshot(
        stats: ProjectStats,
        preset: DashboardAudiencePreset,
        configuration: DashboardAudienceConfiguration,
        cadence: SnapshotCadence,
        customTitle: String? = nil,
        isPinned: Bool = false,
        sourceReviewTemplateID: UUID? = nil
    ) {
        let snapshot = DashboardSnapshot(
            id: UUID(),
            createdAt: Date(),
            projectTitle: project.properties.projectTitle ?? "Project",
            preset: preset,
            configuration: configuration,
            cadence: cadence,
            customTitle: customTitle,
            isPinned: isPinned,
            sourceReviewTemplateID: sourceReviewTemplateID,
            headline: audienceDetail(stats: stats, preset: preset),
            markdown: audienceDashboardMarkdown(stats: stats, preset: preset, configuration: configuration),
            flaggedTaskIDs: Array(flaggedTaskIDs),
            reviewAnnotations: reviewAnnotations
        )

        var storedSnapshots = snapshots
        storedSnapshots.insert(snapshot, at: 0)
        storedSnapshots = Array(storedSnapshots.prefix(12))
        persistSnapshots(storedSnapshots)
        selectedSnapshotID = snapshot.id
        comparisonSnapshotID = defaultComparisonSnapshotID(for: snapshot.id)
        selectedTrendFocus = nil
    }

    private func applySnapshot(_ snapshot: DashboardSnapshot) {
        audiencePresetRawValue = snapshot.preset.rawValue
        var configurations = decodeAudienceConfigurations()
        configurations[snapshot.preset.rawValue] = snapshot.configuration
        audienceConfigurationData = (try? JSONEncoder().encode(configurations)) ?? Data()
        appliedReviewTemplateID = nil
        customTemplatePreferredExports = Set(snapshot.preset.defaultTemplateExports)
        persistFlaggedTaskIDs(Set(snapshot.flaggedTaskIDs))
        taskReviewNotesData = ReviewNotesStore.encodeAnnotations(snapshot.reviewAnnotations)
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

    private func exportSnapshotComparison(_ comparison: DashboardSnapshotComparison) {
        let markdown = snapshotComparisonMarkdown(comparison)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Snapshot Delta \(PDFExporter.fileNameTimestamp).md"
        panel.allowedContentTypes = [UTType.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func deleteSnapshot(_ id: UUID) {
        let remaining = snapshots.filter { $0.id != id }
        persistSnapshots(remaining)
        selectedSnapshotID = remaining.first?.id
        comparisonSnapshotID = defaultComparisonSnapshotID(for: selectedSnapshotID)
        selectedTrendFocus = nil
    }

    private func snapshotComparisonMarkdown(_ comparison: DashboardSnapshotComparison) -> String {
        var lines: [String] = [
            "# \(comparison.selected.projectTitle) Snapshot Delta",
            "",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "",
            "## Snapshot Pair",
            "- Current: \(snapshotLabel(comparison.selected))",
            "- Baseline: \(snapshotLabel(comparison.baseline))",
            "",
            "## Review Deltas",
            "- Flagged tasks: \(comparison.selected.flaggedTaskCount) (\(signedDeltaText(comparison.flaggedDelta)))",
            "- Annotated tasks: \(comparison.selected.annotatedTaskCount) (\(signedDeltaText(comparison.annotatedDelta)))",
            "- Open issues: \(comparison.selected.unresolvedIssueCount) (\(signedDeltaText(comparison.unresolvedDelta)))",
            "- Follow-up items: \(comparison.selected.followUpIssueCount) (\(signedDeltaText(comparison.followUpDelta)))"
        ]

        if comparison.hasLayoutChanges {
            lines.append("")
            lines.append("## Layout Changes")
            lines.append("- \(snapshotLayoutSummary(comparison))")
        }

        lines.append(contentsOf: snapshotChangeMarkdownLines(title: "New Flagged Tasks", items: comparison.addedFlaggedTasks))
        lines.append(contentsOf: snapshotChangeMarkdownLines(title: "Cleared Flags", items: comparison.clearedFlaggedTasks))
        lines.append(contentsOf: snapshotChangeMarkdownLines(title: "New Open Issues", items: comparison.newOpenIssues))
        lines.append(contentsOf: snapshotChangeMarkdownLines(title: "Resolved Issues", items: comparison.resolvedIssues))
        lines.append(contentsOf: snapshotChangeMarkdownLines(title: "Added Follow-Up", items: comparison.addedFollowUpTasks))
        lines.append(contentsOf: snapshotChangeMarkdownLines(title: "Cleared Follow-Up", items: comparison.clearedFollowUpTasks))

        if !comparison.hasReviewChanges {
            lines.append("")
            lines.append("## Review Change Summary")
            lines.append("- No review-state changes between these snapshots.")
        }

        return lines.joined(separator: "\n")
    }

    private func audienceDashboardMarkdown(stats: ProjectStats) -> String {
        audienceDashboardMarkdown(stats: stats, preset: audiencePreset, configuration: currentAudienceConfiguration)
    }

    private func audienceDashboardMarkdown(
        stats: ProjectStats,
        preset: DashboardAudiencePreset,
        configuration: DashboardAudienceConfiguration
    ) -> String {
        var lines: [String] = [
            "# \(project.properties.projectTitle ?? "Project") \(preset.rawValue) Dashboard",
            "",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "",
            "## Dashboard Profile",
            "- Audience: \(preset.rawValue)",
            "- Focus: \(preset.summary)",
            "- Task Filter: \(configuration.taskScope.rawValue)",
            "- Milestone Count: \(configuration.milestoneLimit)",
            "- Visible Widgets: \(configuration.visibleWidgets.map(\.rawValue).joined(separator: ", "))",
            "",
            "## Recommended Navigation",
        ]

        lines.append(contentsOf: preset.recommendedViews.map { "- \($0.rawValue)" })
        lines.append("")
        lines.append("## Recommended Exports")
        lines.append(contentsOf: preset.recommendedExports.map { "- \($0)" })
        lines.append("")
        lines.append("## Headline")
        lines.append(audienceDetail(stats: stats, preset: preset))
        lines.append("")
        lines.append("## Review Snapshot")
        lines.append("- Flagged tasks: \(flaggedTaskIDs.count)")
        lines.append("- Annotated tasks: \(reviewAnnotations.count)")
        lines.append("- Unresolved issues: \(unresolvedIssueCount)")
        lines.append("- Follow-up items: \(followUpIssueCount)")
        lines.append(contentsOf: flaggedTaskSnapshotLines())
        lines.append(contentsOf: unresolvedIssueSnapshotLines())
        lines.append("")
        lines.append("## KPI Snapshot")
        lines.append(contentsOf: audienceMetrics(stats: stats, preset: preset).map { "- \($0.title): \($0.value) (\($0.subtitle))" })

        if configuration.visibleWidgets.contains(.baselineAlert), stats.hasBaselineData {
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

        if configuration.visibleWidgets.contains(.taskStatus) {
            lines.append("")
            lines.append("## \(taskStatusTitle(for: configuration))")
            lines.append("- Scope total: \(filteredTaskTotal(for: configuration))")
            lines.append("- Completed: \(filteredCompletedTasks(for: configuration))")
            lines.append("- In progress: \(filteredInProgressTasks(for: configuration))")
            lines.append("- Not started: \(filteredNotStartedTasks(for: configuration))")
            lines.append("- Overdue: \(filteredOverdueTasks(for: configuration))")
        }

        if configuration.visibleWidgets.contains(.milestones) {
            lines.append("")
            lines.append("## Milestones")
            lines.append(contentsOf: milestoneSummaryLines(displayedMilestones(stats, configuration: configuration)))
        }

        if configuration.visibleWidgets.contains(.resourceSummary) {
            let workResources = project.resources.filter { $0.type == "work" || $0.type == nil }.count
            let materialResources = project.resources.filter { $0.type == "material" }.count
            lines.append("")
            lines.append("## Resource Summary")
            lines.append("- Total resources: \(project.resources.count)")
            lines.append("- Work resources: \(workResources)")
            lines.append("- Material resources: \(materialResources)")
            lines.append("- Assignments: \(project.assignments.count)")
        }

        if configuration.visibleWidgets.contains(.scheduleHealth) {
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

        if configuration.visibleWidgets.contains(.baselineAnalysis), stats.hasBaselineData {
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

    private func flaggedTaskSnapshotLines() -> [String] {
        let flaggedTasks = flaggedTaskIDs.sorted().compactMap { project.tasksByID[$0]?.displayName }
        guard !flaggedTasks.isEmpty else { return [] }

        var lines = ["", "### Flagged Tasks"]
        lines.append(contentsOf: flaggedTasks.prefix(5).map { "- \($0)" })
        if flaggedTasks.count > 5 {
            lines.append("- ... \(flaggedTasks.count - 5) more")
        }
        return lines
    }

    private func unresolvedIssueSnapshotLines() -> [String] {
        let issues = reviewAnnotations
            .filter { $0.value.isUnresolved }
            .compactMap { uniqueID, annotation -> String? in
                guard let task = project.tasksByID[uniqueID] else { return nil }
                var tags: [String] = []
                if annotation.status != .notReviewed {
                    tags.append(annotation.status.rawValue)
                }
                if annotation.needsFollowUp {
                    tags.append("Follow-Up")
                }
                let suffix = tags.isEmpty ? "" : " (\(tags.joined(separator: ", ")))"
                return "- \(task.displayName)\(suffix)"
            }
            .sorted()

        guard !issues.isEmpty else { return [] }

        var lines = ["", "### Open Issues"]
        lines.append(contentsOf: issues.prefix(5))
        if issues.count > 5 {
            lines.append("- ... \(issues.count - 5) more")
        }
        return lines
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
    @State private var projectAnalysis: DashboardProjectAnalysis?

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
            projectAnalysis = DashboardProjectAnalysis.build(project: project)
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
        let issues = projectAnalysis?.validationIssues ?? []
        let errors = issues.filter { $0.severity == .error }.count
        let warnings = issues.filter { $0.severity == .warning }.count
        if errors == 0 && warnings == 0 { return "No major validation problems detected." }
        return "\(errors) errors and \(warnings) warnings need review."
    }

    private var diagnosticsSummary: String {
        let signals = projectAnalysis?.diagnosticItems ?? []
        if signals.isEmpty { return "No major dependency or constraint hotspots detected." }
        return "\(signals.count) dependency and constraint signals flagged."
    }

    private var resourceRiskSummary: String {
        let risks = projectAnalysis?.resourceIssues ?? []
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
