import SwiftUI
import SwiftData
import Combine
import AppKit
import UniformTypeIdentifiers

struct PortfolioDashboardView: View {
    private enum RegistryScope: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case archived = "Archived"

        var id: String { rawValue }
    }

    private enum HealthScope: String, CaseIterable, Identifiable {
        case all = "All Health"
        case atRisk = "At Risk"
        case healthy = "Healthy"

        var id: String { rawValue }
    }

    private enum ApprovalScope: String, CaseIterable, Identifiable {
        case all = "All Decisions"
        case approved = "Approved"
        case intake = "Intake"
        case paused = "Paused"

        var id: String { rawValue }
    }

    private enum RegistryGrouping: String, CaseIterable, Identifiable {
        case none = "No Group"
        case workspace = "Workspace"
        case program = "Program"
        case health = "Health"
        case approval = "Approval"

        var id: String { rawValue }
    }

    private struct TaskSnapshot: Identifiable, Hashable {
        let id: String
        let planID: UUID
        let planTitle: String
        let name: String
        let boardStatus: String
        let finishDate: Date
        let isActive: Bool
        let percentComplete: Double
    }

    private struct PlanGroup: Identifiable {
        let title: String
        let plans: [PortfolioProjectPlan]

        var id: String { title }
    }

    private struct PortfolioDerivedContent {
        let visiblePlans: [PortfolioProjectPlan]
        let groupedVisiblePlans: [PlanGroup]
        let archivedCount: Int
        let activeCount: Int
        let workspaceCount: Int
        let programCount: Int
        let atRiskProjectCount: Int
        let totalPortfolioBudget: Double
        let totalPortfolioActualCost: Double
        let activeTasks: [TaskSnapshot]
        let overdueTaskCount: Int
        let executiveSummary: PortfolioExecutiveSummary
        let governanceSummary: PortfolioGovernanceSummary
        let programRoadmapSummary: PortfolioProgramRoadmapSummary
        let dependencySummary: PortfolioDependencySummary
        let executiveInsightsByPlanID: [UUID: PortfolioExecutiveSummary.ProjectInsight]
        let governanceInsightsByPlanID: [UUID: PortfolioGovernanceSummary.ProjectInsight]

        var budgetVariance: Double {
            totalPortfolioBudget - totalPortfolioActualCost
        }

        static let empty = PortfolioDerivedContent(
            visiblePlans: [],
            groupedVisiblePlans: [],
            archivedCount: 0,
            activeCount: 0,
            workspaceCount: 0,
            programCount: 0,
            atRiskProjectCount: 0,
            totalPortfolioBudget: 0,
            totalPortfolioActualCost: 0,
            activeTasks: [],
            overdueTaskCount: 0,
            executiveSummary: PortfolioExecutiveSummary(
                projectInsights: [],
                rankedProjects: [],
                topCostVarianceProjects: [],
                topScheduleSlipProjects: [],
                attentionFeed: [],
                upcomingMilestones: [],
                slippedMilestones: [],
                healthyCount: 0,
                watchCount: 0,
                atRiskCount: 0,
                reviewDueCount: 0,
                slippedMilestoneCount: 0,
                upcomingMilestoneCount: 0
            ),
            governanceSummary: PortfolioGovernanceSummary(
                projectInsights: [],
                rankedProjects: [],
                approvedCount: 0,
                intakeCount: 0,
                onHoldCount: 0,
                cancelledCount: 0,
                reviewDueCount: 0,
                averageGovernanceScore: 0,
                averageStrategicAlignment: 0,
                averageRiskScore: 0
            ),
            programRoadmapSummary: PortfolioProgramRoadmapSummary(
                programs: [],
                timelineEvents: [],
                slippedMilestoneCount: 0,
                overdueReviewCount: 0
            ),
            dependencySummary: PortfolioDependencySummary(
                dependencies: [],
                blockedCount: 0,
                highSeverityCount: 0,
                dueSoonCount: 0,
                crossProgramCount: 0
            ),
            executiveInsightsByPlanID: [:],
            governanceInsightsByPlanID: [:]
        )
    }

    private static let portfolioStageOptions = [
        "Planning",
        "Proposed",
        "Approved",
        "Delivery",
        "On Hold",
        "Completed"
    ]

    private static let portfolioHealthOptions = [
        "Green",
        "Amber",
        "Red",
        "On Hold"
    ]

    private static let portfolioPriorityOptions = [
        "Low",
        "Medium",
        "High",
        "Critical"
    ]

    private static let portfolioApprovalOptions = [
        "Proposed",
        "Intake Review",
        "Approved",
        "On Hold",
        "Cancelled"
    ]

    private static let dependencyRelationOptions = ["FS", "SS", "FF", "SF"]

    private static let reviewCadenceOptions = [7, 14, 30, 60, 90]

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\PortfolioProjectPlan.updatedAt, order: .reverse)])
    private var plans: [PortfolioProjectPlan]
    @Query(sort: [SortDescriptor(\PortfolioCrossProjectDependency.updatedAt, order: .reverse)])
    private var crossProjectDependencies: [PortfolioCrossProjectDependency]
    @Query(sort: [SortDescriptor(\PortfolioReviewPreset.updatedAt, order: .reverse)])
    private var reviewPresets: [PortfolioReviewPreset]
    @Query(sort: [SortDescriptor(\PortfolioReviewSnapshot.createdAt, order: .reverse)])
    private var reviewSnapshots: [PortfolioReviewSnapshot]
    @Binding var activePortfolioID: UUID?

    @State private var selectedPlanID: UUID?
    @State private var registryScope: RegistryScope = .active
    @State private var healthScope: HealthScope = .all
    @State private var approvalScope: ApprovalScope = .all
    @State private var registryGrouping: RegistryGrouping = .none
    @State private var searchText = ""
    @State private var showImportPicker = false
    @State private var importStatusMessage: String?
    @State private var importErrorMessage: String?
    @State private var isImporting = false
    @State private var selectedDependencySourceTaskID: UUID?
    @State private var selectedDependencyTargetPlanID: UUID?
    @State private var selectedDependencyTargetTaskID: UUID?
    @State private var dependencyRelationType = "FS"
    @State private var dependencyLagDays = 0
    @State private var dependencyNote = ""
    @State private var selectedReviewPresetID: UUID?
    @State private var selectedReviewSnapshotID: UUID?
    @State private var reviewPresetName = ""
    @State private var reviewPresetCadenceDays = 14
    @State private var reviewSnapshotTitle = ""
    @State private var derivedContent = PortfolioDerivedContent.empty
    @State private var resourceCapacitySummary = PortfolioResourceCapacitySummary(
        resources: [],
        overloadedResources: [],
        sharedResources: [],
        alerts: [],
        uniqueResourceCount: 0,
        overloadedResourceCount: 0,
        sharedResourceCount: 0,
        overloadedWeekCount: 0,
        doubleBookedWeekCount: 0
    )
    @State private var isPortfolioDerivedContentLoading = true
    @State private var isResourceCapacityLoading = true
    @State private var resourceCapacityGeneration = 0
    @State private var portfolioDerivedRefreshWorkItem: DispatchWorkItem?
    @State private var portfolioDerivedGeneration = 0
    @State private var resourceCapacityRefreshWorkItem: DispatchWorkItem?

    private var filteredPlans: [PortfolioProjectPlan] {
        plans.filter { plan in
            scopeMatches(plan) && healthMatches(plan) && approvalMatches(plan) && searchMatches(plan)
        }
    }

    private var selectedPlan: PortfolioProjectPlan? {
        if let selectedPlanID, let plan = plans.first(where: { $0.portfolioID == selectedPlanID }) {
            return plan
        }
        if let activePortfolioID, let plan = plans.first(where: { $0.portfolioID == activePortfolioID }) {
            return plan
        }
        return derivedContent.visiblePlans.first ?? filteredPlans.first ?? plans.first
    }

    private var selectedPlanTitle: String {
        trimmedOrFallback(selectedPlan?.title ?? "", fallback: "No plan selected")
    }

    private var workspacePlan: PortfolioProjectPlan? {
        guard let activePortfolioID else { return nil }
        return plans.first(where: { $0.portfolioID == activePortfolioID })
    }

    private var watchlistTasks: [TaskSnapshot] {
        derivedContent.activeTasks
    }

    private var visiblePlans: [PortfolioProjectPlan] {
        derivedContent.visiblePlans
    }

    private var groupedVisiblePlans: [PlanGroup] {
        derivedContent.groupedVisiblePlans
    }

    private var archivedCount: Int {
        derivedContent.archivedCount
    }

    private var activeCount: Int {
        derivedContent.activeCount
    }

    private var workspaceCount: Int {
        derivedContent.workspaceCount
    }

    private var programCount: Int {
        derivedContent.programCount
    }

    private var atRiskProjectCount: Int {
        derivedContent.atRiskProjectCount
    }

    private var totalPortfolioBudget: Double {
        derivedContent.totalPortfolioBudget
    }

    private var totalPortfolioActualCost: Double {
        derivedContent.totalPortfolioActualCost
    }

    private var budgetVariance: Double {
        derivedContent.budgetVariance
    }

    private var overdueTaskCount: Int {
        derivedContent.overdueTaskCount
    }

    private var selectedPlanTasks: [TaskSnapshot] {
        guard let selectedPlan else { return [] }
        return taskSnapshots(for: selectedPlan)
    }

    private var selectedActiveTasks: [TaskSnapshot] {
        selectedPlanTasks
            .filter { $0.isActive && $0.percentComplete < 100 }
            .sorted {
                if $0.finishDate != $1.finishDate {
                    return $0.finishDate < $1.finishDate
                }
                return $0.id < $1.id
            }
    }

    private var executiveSummary: PortfolioExecutiveSummary {
        derivedContent.executiveSummary
    }

    private var governanceSummary: PortfolioGovernanceSummary {
        derivedContent.governanceSummary
    }

    private var programRoadmapSummary: PortfolioProgramRoadmapSummary {
        derivedContent.programRoadmapSummary
    }

    private var dependencySummary: PortfolioDependencySummary {
        derivedContent.dependencySummary
    }

    private var currentReviewViewSettings: PortfolioReviewViewSettings {
        PortfolioReviewViewSettings(
            registryScope: registryScope.rawValue,
            healthScope: healthScope.rawValue,
            approvalScope: approvalScope.rawValue,
            grouping: registryGrouping.rawValue,
            searchText: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
            cadenceDays: max(7, reviewPresetCadenceDays)
        )
    }

    private var selectedReviewPreset: PortfolioReviewPreset? {
        guard let selectedReviewPresetID else { return nil }
        return reviewPresets.first(where: { $0.uniqueID == selectedReviewPresetID })
    }

    private var selectedReviewSnapshot: PortfolioReviewSnapshot? {
        guard let selectedReviewSnapshotID else { return nil }
        return reviewSnapshots.first(where: { $0.uniqueID == selectedReviewSnapshotID })
    }

    private var currentReviewPayload: PortfolioReviewSnapshotPayload {
        PortfolioReviewSnapshotPayload.build(
            title: reviewSnapshotTitle,
            presetName: selectedReviewPreset?.name,
            viewSettings: currentReviewViewSettings,
            plans: visiblePlans,
            executive: executiveSummary,
            governance: governanceSummary,
            roadmap: programRoadmapSummary,
            dependencies: dependencySummary,
            capacity: resourceCapacitySummary,
            overdueTaskCount: overdueTaskCount
        )
    }

    private var selectedReviewDelta: PortfolioReviewDelta? {
        guard let selectedReviewSnapshot else { return nil }
        return PortfolioReviewDelta.build(current: currentReviewPayload, baseline: selectedReviewSnapshot.payload)
    }

    private var selectedPresetNextReviewDate: Date? {
        guard let selectedReviewPreset else { return nil }
        let latestSnapshot = reviewSnapshots
            .filter { $0.presetID == selectedReviewPreset.uniqueID }
            .max { $0.createdAt < $1.createdAt }
        return latestSnapshot.map {
            Calendar.current.date(byAdding: .day, value: max(7, selectedReviewPreset.cadenceDays), to: $0.createdAt) ?? $0.createdAt
        }
    }

    private var selectedProgramRoadmapInsight: PortfolioProgramRoadmapSummary.ProgramInsight? {
        guard let selectedPlan else { return nil }
        let selectedProgram = trimmedOrFallback(selectedPlan.portfolioProgram ?? "", fallback: "Unassigned Program")
        return programRoadmapSummary.programs.first {
            $0.program.caseInsensitiveCompare(selectedProgram) == .orderedSame
        }
    }

    private var selectedPlanInsight: PortfolioExecutiveSummary.ProjectInsight? {
        guard let selectedPlan else { return nil }
        return derivedContent.executiveInsightsByPlanID[selectedPlan.portfolioID]
    }

    private var selectedPlanGovernanceInsight: PortfolioGovernanceSummary.ProjectInsight? {
        guard let selectedPlan else { return nil }
        return derivedContent.governanceInsightsByPlanID[selectedPlan.portfolioID]
    }

    private var dependencySourceTaskOptions: [PortfolioPlanTask] {
        guard let selectedPlan else { return [] }
        return selectedPlan.orderedTaskRows
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var dependencyTargetPlanOptions: [PortfolioProjectPlan] {
        guard let selectedPlan else { return [] }
        return plans
            .filter { $0.portfolioID != selectedPlan.portfolioID }
            .sorted {
                trimmedOrFallback($0.title, fallback: "Untitled Plan")
                    .localizedCaseInsensitiveCompare(trimmedOrFallback($1.title, fallback: "Untitled Plan")) == .orderedAscending
            }
    }

    private var selectedDependencyTargetPlan: PortfolioProjectPlan? {
        guard let selectedDependencyTargetPlanID else { return nil }
        return dependencyTargetPlanOptions.first(where: { $0.portfolioID == selectedDependencyTargetPlanID })
    }

    private var dependencyTargetTaskOptions: [PortfolioPlanTask] {
        guard let selectedDependencyTargetPlan else { return [] }
        return selectedDependencyTargetPlan.orderedTaskRows
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var selectedPlanOutgoingDependencies: [PortfolioDependencySummary.DependencyInsight] {
        guard let selectedPlan else { return [] }
        return dependencySummary.dependencies.filter { $0.sourcePlanID == selectedPlan.portfolioID }
    }

    private var selectedPlanIncomingDependencies: [PortfolioDependencySummary.DependencyInsight] {
        guard let selectedPlan else { return [] }
        return dependencySummary.dependencies.filter { $0.targetPlanID == selectedPlan.portfolioID }
    }

    var body: some View {
        let executive = executiveSummary
        let governance = governanceSummary
        let roadmap = programRoadmapSummary
        let dependencies = dependencySummary
        let capacity = resourceCapacitySummary

        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if isPortfolioDerivedContentLoading || isResourceCapacityLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(isPortfolioDerivedContentLoading ? "Refreshing portfolio analytics…" : "Refreshing cross-project capacity…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        metricCard(title: "Visible", value: "\(visiblePlans.count)", tint: .blue)
                        metricCard(title: "Active", value: "\(activeCount)", tint: .teal)
                        metricCard(title: "Archived", value: "\(archivedCount)", tint: .secondary)
                        metricCard(title: "Workspaces", value: "\(workspaceCount)", tint: .indigo)
                        metricCard(title: "Programs", value: "\(programCount)", tint: .purple)
                        metricCard(title: "At Risk", value: "\(atRiskProjectCount)", tint: atRiskProjectCount == 0 ? .green : .red)
                        metricCard(title: "Approved", value: "\(governance.approvedCount)", tint: .blue)
                        metricCard(title: "Intake", value: "\(governance.intakeCount)", tint: .orange)
                        metricCard(title: "On Hold", value: "\(governance.onHoldCount)", tint: governance.onHoldCount == 0 ? .secondary : .red)
                        metricCard(title: "Gov Score", value: "\(governance.averageGovernanceScore)", tint: governanceScoreColor(score: governance.averageGovernanceScore))
                        metricCard(title: "Programs With Roadmaps", value: "\(roadmap.programs.count)", tint: .purple)
                        metricCard(title: "Cross-Project Links", value: "\(dependencies.dependencies.count)", tint: .indigo)
                        metricCard(title: "Blocked Links", value: "\(dependencies.blockedCount)", tint: dependencies.blockedCount == 0 ? .green : .red)
                        metricCard(title: "Review Presets", value: "\(reviewPresets.count)", tint: .blue)
                        metricCard(title: "Review Snapshots", value: "\(reviewSnapshots.count)", tint: .orange)
                        metricCard(title: "Portfolio Budget", value: CurrencyFormatting.string(from: totalPortfolioBudget), tint: .green)
                        metricCard(title: "Actual Cost", value: CurrencyFormatting.string(from: totalPortfolioActualCost), tint: .orange)
                        metricCard(title: "Budget Remaining", value: CurrencyFormatting.string(from: budgetVariance), tint: budgetVariance >= 0 ? .green : .red)
                        metricCard(title: "Overdue Work", value: "\(overdueTaskCount)", tint: .red)
                    }

                    GroupBox("Registry") {
                        VStack(alignment: .leading, spacing: 12) {
                            // Whole controls reflow to new lines on narrow
                            // windows instead of hyphenating or truncating.
                            FlowLayout(spacing: 12, lineSpacing: 10) {
                                TextField("Search registry", text: $searchText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 220)

                                Picker("Scope", selection: $registryScope) {
                                    ForEach(RegistryScope.allCases) { scope in
                                        Text(scope.rawValue).tag(scope)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 240)

                                Picker("Health", selection: $healthScope) {
                                    ForEach(HealthScope.allCases) { scope in
                                        Text(scope.rawValue).tag(scope)
                                    }
                                }
                                .pickerStyle(.menu)
                                .fixedSize()

                                Picker("Approval", selection: $approvalScope) {
                                    ForEach(ApprovalScope.allCases) { scope in
                                        Text(scope.rawValue).tag(scope)
                                    }
                                }
                                .pickerStyle(.menu)
                                .fixedSize()

                                Picker("Group", selection: $registryGrouping) {
                                    ForEach(RegistryGrouping.allCases) { grouping in
                                        Text(grouping.rawValue).tag(grouping)
                                    }
                                }
                                .pickerStyle(.menu)
                                .fixedSize()

                                Button {
                                    showImportPicker = true
                                } label: {
                                    Label("Import Plan(s)", systemImage: "square.and.arrow.down")
                                        .fixedSize()
                                }
                                .buttonStyle(.borderedProminent)
                                .hoverHighlight()

                                Button {
                                    createBlankPortfolioPlan()
                                } label: {
                                    Label("New Blank Plan", systemImage: "doc.badge.plus")
                                        .fixedSize()
                                }
                                .buttonStyle(.bordered)
                                .hoverHighlight()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if visiblePlans.isEmpty {
                                if isPortfolioDerivedContentLoading && !plans.isEmpty {
                                    VStack(spacing: 10) {
                                        ProgressView()
                                        Text("Preparing the portfolio registry.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 220)
                                } else {
                                ContentUnavailableView(
                                    "No Matching Projects",
                                    systemImage: "tray",
                                    description: Text("Import `.mpp` or `.mppplan` files, create a blank plan, or change the registry scope.")
                                )
                                .frame(maxWidth: .infinity, minHeight: 220)
                                }
                            } else {
                                LazyVStack(alignment: .leading, spacing: 14) {
                                    if registryGrouping == .none {
                                        ForEach(visiblePlans) { plan in
                                            portfolioRow(for: plan, governance: derivedContent.governanceInsightsByPlanID[plan.portfolioID])
                                        }
                                    } else {
                                        ForEach(groupedVisiblePlans) { group in
                                            VStack(alignment: .leading, spacing: 10) {
                                                HStack {
                                                    Text(group.title)
                                                        .font(.headline)
                                                    Spacer()
                                                    Text("\(group.plans.count) projects")
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(.secondary)
                                                }

                                                ForEach(group.plans) { plan in
                                                    portfolioRow(for: plan, governance: derivedContent.governanceInsightsByPlanID[plan.portfolioID])
                                                }
                                            }
                                            .padding(14)
                                            .background(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .fill(Color(nsColor: .underPageBackgroundColor))
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    portfolioTimelineSection

                    reviewPresetSection

                    reviewHistorySection

                    executiveSummarySection(summary: executive)

                    executiveRankingsSection(summary: executive)

                    milestoneRollupSection(summary: executive)

                    executiveAttentionSection(summary: executive)

                    governanceSummarySection(summary: governance)

                    programRoadmapSection(summary: roadmap)

                    programTimelineSection(summary: roadmap)

                    crossProjectDependencySection(summary: dependencies)

                    resourceCapacitySection(summary: capacity)

                    resourceConflictSection(summary: capacity)

                    GroupBox("Cross-Portfolio Watchlist") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(watchlistTasks.prefix(12)) { task in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.name)
                                            .font(.body.weight(.medium))
                                        Text(task.planTitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(task.finishDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Calendar.current.startOfDay(for: task.finishDate) < Calendar.current.startOfDay(for: Date()) ? .red : .secondary)
                                }
                                Divider()
                            }
                            if watchlistTasks.isEmpty {
                                Text("No active work in the current registry scope.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 560, idealWidth: 760, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            detailPane
                .frame(minWidth: 420, idealWidth: 540, maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.mpp, .mppplan],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    await importPortfolioPlans(from: urls)
                }
            case .failure(let error):
                importErrorMessage = error.localizedDescription
            }
        }
        .onAppear {
            syncSelectedPlan()
            normalizeArchiveFlags()
            normalizeCrossProjectDependencies()
            syncDependencySelections()
            syncReviewSelections()
            schedulePortfolioDerivedContentRefresh(delay: 0)
            scheduleResourceCapacityRefresh(delay: 0.08)
        }
        .onChange(of: plans.map(\.updatedAt)) { _, _ in
            syncSelectedPlan()
            normalizeCrossProjectDependencies()
            syncDependencySelections()
            syncReviewSelections()
            schedulePortfolioDerivedContentRefresh(delay: 0.02)
            scheduleResourceCapacityRefresh(delay: 0.12)
        }
        .onChange(of: registryScope) { _, _ in
            syncSelectedPlan()
            schedulePortfolioDerivedContentRefresh(delay: 0.12)
            scheduleResourceCapacityRefresh(delay: 0.18)
        }
        .onChange(of: searchText) { _, _ in
            syncSelectedPlan()
            schedulePortfolioDerivedContentRefresh(delay: 0.16)
            scheduleResourceCapacityRefresh(delay: 0.22)
        }
        .onChange(of: healthScope) { _, _ in
            syncSelectedPlan()
            schedulePortfolioDerivedContentRefresh(delay: 0.12)
            scheduleResourceCapacityRefresh(delay: 0.18)
        }
        .onChange(of: approvalScope) { _, _ in
            syncSelectedPlan()
            schedulePortfolioDerivedContentRefresh(delay: 0.12)
            scheduleResourceCapacityRefresh(delay: 0.18)
        }
        .onChange(of: registryGrouping) { _, _ in
            schedulePortfolioDerivedContentRefresh(delay: 0.04)
        }
        .onChange(of: activePortfolioID) { _, newValue in
            if selectedPlanID != newValue {
                selectedPlanID = newValue
            }
        }
        .onChange(of: selectedPlanID) { _, _ in
            syncDependencySelections()
        }
        .onChange(of: selectedDependencyTargetPlanID) { _, _ in
            syncDependencySelections()
        }
        .onChange(of: crossProjectDependencies.map(\.uniqueID)) { _, _ in
            syncDependencySelections()
            schedulePortfolioDerivedContentRefresh(delay: 0.02)
        }
        .onChange(of: reviewPresets.map(\.uniqueID)) { _, _ in
            syncReviewSelections()
        }
        .onChange(of: reviewSnapshots.map(\.uniqueID)) { _, _ in
            syncReviewSelections()
        }
        .alert("Import Error", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "Unknown error")
        }
        .overlay(alignment: .bottomLeading) {
            if let importStatusMessage {
                Text(importStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.leading, 20)
                    .padding(.bottom, 18)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Portfolio Workspace")
                    .font(.largeTitle.bold())
                Text("Register multiple projects, open one into the live workspace, archive or remove inactive work, and inspect portfolio health from one place.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text("Workspace")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(selectedPlanTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let selectedPlan {
                    Text([
                        normalizedMetadata(selectedPlan.portfolioWorkspace),
                        normalizedMetadata(selectedPlan.portfolioProgram)
                    ]
                    .compactMap { $0 }
                    .joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
                if let workspacePlan {
                    Label(workspacePlan.isArchivedValue ? "Archived" : "Active", systemImage: workspacePlan.isArchivedValue ? "archivebox" : "checkmark.seal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(workspacePlan.isArchivedValue ? Color.secondary : Color.accentColor)
                }
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selected = selectedPlan {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(trimmedOrFallback(selected.title, fallback: "Untitled Plan"))
                        .font(.title2.bold())

                    HStack(spacing: 8) {
                        Label(selected.isArchivedValue ? "Archived" : "Active", systemImage: selected.isArchivedValue ? "archivebox" : "checkmark.seal")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.semibold))
                        portfolioMetadataBadge(
                            normalizedMetadata(selected.portfolioHealth) ?? "Health Not Set",
                            tint: healthColor(for: selected.portfolioHealth)
                        )
                        portfolioMetadataBadge(
                            normalizedMetadata(selected.portfolioStage) ?? "Stage Not Set",
                            tint: .secondary
                        )
                        portfolioMetadataBadge(
                            normalizedMetadata(selected.portfolioApprovalState) ?? "Intake Review",
                            tint: approvalStateColor(for: selected.portfolioApprovalState)
                        )
                        Label("Updated \(selected.updatedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                            .font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                        metricCard(title: "Tasks", value: "\(selected.taskCount)", tint: .blue)
                        metricCard(title: "BAC", value: CurrencyFormatting.string(from: selected.portfolioBudget), tint: .green)
                        metricCard(title: "Actual", value: CurrencyFormatting.string(from: selected.portfolioActualCost), tint: .orange)
                        metricCard(title: "Variance", value: CurrencyFormatting.string(from: selected.portfolioBudget - selected.portfolioActualCost), tint: selected.portfolioBudget >= selected.portfolioActualCost ? .green : .red)
                    }

                    GroupBox("Portfolio Metadata") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                TextField("Workspace", text: metadataTextBinding(\.portfolioWorkspace))
                                    .textFieldStyle(.roundedBorder)
                                TextField("Program", text: metadataTextBinding(\.portfolioProgram))
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack(spacing: 12) {
                                TextField("Sponsor", text: metadataTextBinding(\.portfolioSponsor))
                                    .textFieldStyle(.roundedBorder)
                                TextField("Objective", text: metadataTextBinding(\.portfolioObjective))
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack(spacing: 12) {
                                Picker("Health", selection: metadataSelectionBinding(\.portfolioHealth)) {
                                    Text("Not Set").tag("")
                                    ForEach(Self.portfolioHealthOptions, id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                                .pickerStyle(.menu)

                                Picker("Stage", selection: metadataSelectionBinding(\.portfolioStage)) {
                                    Text("Not Set").tag("")
                                    ForEach(Self.portfolioStageOptions, id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                                .pickerStyle(.menu)

                                Picker("Priority", selection: metadataSelectionBinding(\.portfolioPriorityBand)) {
                                    Text("Not Set").tag("")
                                    ForEach(Self.portfolioPriorityOptions, id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            HStack(spacing: 12) {
                                CalendarDatePicker(title: "Review Date", date: metadataDateBinding(\.portfolioReviewDate))
                                Button("Clear Review Date") {
                                    updateMetadataDate(\.portfolioReviewDate, value: nil)
                                }
                                .buttonStyle(.bordered)
                                .hoverHighlight()
                                .disabled(selected.portfolioReviewDate == nil)
                                Spacer()
                            }
                        }
                    }

                    GroupBox("Governance") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Picker("Approval", selection: metadataSelectionBinding(\.portfolioApprovalState)) {
                                    Text("Not Set").tag("")
                                    ForEach(Self.portfolioApprovalOptions, id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                                .pickerStyle(.menu)

                                Picker("Review Cadence", selection: metadataOptionalIntBinding(\.portfolioReviewCadenceDays, defaultValue: 14)) {
                                    ForEach(Self.reviewCadenceOptions, id: \.self) { days in
                                        Text("\(days) days").tag(days)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            HStack(spacing: 16) {
                                Stepper(value: metadataOptionalIntBinding(\.portfolioStrategicAlignment, defaultValue: 50), in: 0...100, step: 5) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Strategic Alignment")
                                        Text("\(selected.portfolioStrategicAlignment ?? 50)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Stepper(value: metadataOptionalIntBinding(\.portfolioRiskScore, defaultValue: 40), in: 0...100, step: 5) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Risk Score")
                                        Text("\(selected.portfolioRiskScore ?? 40)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            TextField("Archive / Hold Reason", text: metadataTextBinding(\.portfolioArchiveReason))
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    GroupBox("Plan Details") {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow(label: "Owner", value: trimmedOrFallback(selected.manager, fallback: "Unassigned"))
                            detailRow(label: "Company", value: trimmedOrFallback(selected.company, fallback: "No company"))
                            detailRow(label: "Workspace", value: trimmedOrFallback(selected.portfolioWorkspace ?? "", fallback: "Unassigned"))
                            detailRow(label: "Program", value: trimmedOrFallback(selected.portfolioProgram ?? "", fallback: "Unassigned"))
                            detailRow(label: "Sponsor", value: trimmedOrFallback(selected.portfolioSponsor ?? "", fallback: "Unassigned"))
                            detailRow(label: "Health", value: trimmedOrFallback(selected.portfolioHealth ?? "", fallback: "Not Set"))
                            detailRow(label: "Stage", value: trimmedOrFallback(selected.portfolioStage ?? "", fallback: "Not Set"))
                            detailRow(label: "Approval", value: trimmedOrFallback(selected.portfolioApprovalState ?? "", fallback: "Intake Review"))
                            detailRow(label: "Priority", value: trimmedOrFallback(selected.portfolioPriorityBand ?? "", fallback: "Not Set"))
                            detailRow(label: "Strategic Alignment", value: "\(selected.portfolioStrategicAlignment ?? 50)")
                            detailRow(label: "Risk Score", value: "\(selected.portfolioRiskScore ?? 40)")
                            detailRow(label: "Status Date", value: selected.statusDate.formatted(date: .abbreviated, time: .omitted))
                            detailRow(label: "Review Cadence", value: "\((selected.portfolioReviewCadenceDays ?? 14)) days")
                            detailRow(label: "Resources", value: "\(selected.resources.count)")
                            detailRow(label: "Calendars", value: "\(selected.calendars.count)")
                            detailRow(label: "Sprints", value: "\(selected.sprints.count)")
                            detailRow(label: "Snapshots", value: "\(selected.statusSnapshots.count)")
                            detailRow(label: "Workflow Columns", value: "\(selected.workflowColumns.count)")
                            detailRow(label: "Type Workflows", value: "\(selected.typeWorkflowOverrides.count)")
                            if let archiveReason = normalizedMetadata(selected.portfolioArchiveReason) {
                                detailRow(label: "Archive Reason", value: archiveReason)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let insight = selectedPlanInsight {
                        GroupBox("Executive Signals") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    executiveStatusBadge(title: insight.riskBand, tint: executiveRiskColor(for: insight.riskBand))
                                    executiveStatusBadge(title: "\(insight.score) / 100", tint: executiveScoreColor(score: insight.score))
                                    executiveStatusBadge(title: insight.manualHealth, tint: healthColor(for: insight.manualHealth))
                                    Spacer()
                                }

                                detailRow(label: "Overdue Active Tasks", value: "\(insight.overdueTaskCount)")
                                detailRow(label: "Slipped Tasks", value: "\(insight.slippedTaskCount)")
                                detailRow(label: "Slipped Milestones", value: "\(insight.slippedMilestoneCount)")
                                detailRow(label: "Upcoming Milestones", value: "\(insight.upcomingMilestoneCount)")
                                detailRow(label: "Max Schedule Slip", value: "\(insight.maxScheduleSlipDays)d")
                                detailRow(label: "Completion", value: "\(Int(insight.completionPercent.rounded()))%")
                                detailRow(label: "Next Milestone", value: insight.nextMilestoneDate?.formatted(date: .abbreviated, time: .omitted) ?? "None")
                                detailRow(label: "Review Date", value: insight.reviewDate?.formatted(date: .abbreviated, time: .omitted) ?? "Not scheduled")

                                Divider()

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Attention Drivers")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    ForEach(insight.attentionReasons, id: \.self) { reason in
                                        Text(reason)
                                            .font(.caption)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let programInsight = selectedProgramRoadmapInsight {
                        GroupBox("Program Roadmap") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    executiveStatusBadge(title: programInsight.program, tint: .purple)
                                    executiveStatusBadge(title: "\(programInsight.projectCount) projects", tint: .blue)
                                    if programInsight.slippedMilestoneCount > 0 {
                                        executiveStatusBadge(title: "\(programInsight.slippedMilestoneCount) slipped", tint: .red)
                                    }
                                    if programInsight.reviewDueCount > 0 {
                                        executiveStatusBadge(title: "\(programInsight.reviewDueCount) reviews due", tint: .orange)
                                    }
                                    Spacer()
                                }

                                detailRow(label: "Workspaces", value: programInsight.workspaceNames.joined(separator: ", "))
                                detailRow(label: "Budget", value: CurrencyFormatting.string(from: programInsight.totalBudget))
                                detailRow(label: "Actual", value: CurrencyFormatting.string(from: programInsight.totalActualCost))
                                detailRow(label: "Next Milestone", value: programInsight.nextMilestoneDate?.formatted(date: .abbreviated, time: .omitted) ?? "None")

                                if !programInsight.timelineEvents.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Upcoming Program Events")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        ForEach(programInsight.timelineEvents.prefix(6)) { event in
                                            roadmapTimelineRow(event)
                                            if event.id != programInsight.timelineEvents.prefix(6).last?.id {
                                                Divider()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    GroupBox("Cross-Project Dependencies") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Register cross-project handoffs directly at the portfolio layer. The dependency feed scores each link by successor timing, predecessor progress, and cross-program exposure.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if dependencyTargetPlanOptions.isEmpty {
                                Text("Import or create at least two plans to add cross-project dependencies.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if dependencySourceTaskOptions.isEmpty || dependencyTargetTaskOptions.isEmpty {
                                Text("Select plans with task data before creating a dependency.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                HStack(alignment: .top, spacing: 12) {
                                    Picker("From Task", selection: $selectedDependencySourceTaskID) {
                                        Text("Select task").tag(Optional<UUID>.none)
                                        ForEach(dependencySourceTaskOptions) { task in
                                            Text(task.name).tag(Optional(task.uniqueID))
                                        }
                                    }
                                    .pickerStyle(.menu)

                                    Picker("To Plan", selection: $selectedDependencyTargetPlanID) {
                                        Text("Select plan").tag(Optional<UUID>.none)
                                        ForEach(dependencyTargetPlanOptions) { plan in
                                            Text(trimmedOrFallback(plan.title, fallback: "Untitled Plan")).tag(Optional(plan.portfolioID))
                                        }
                                    }
                                    .pickerStyle(.menu)

                                    Picker("To Task", selection: $selectedDependencyTargetTaskID) {
                                        Text("Select task").tag(Optional<UUID>.none)
                                        ForEach(dependencyTargetTaskOptions) { task in
                                            Text(task.name).tag(Optional(task.uniqueID))
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }

                                HStack(alignment: .center, spacing: 12) {
                                    Picker("Type", selection: $dependencyRelationType) {
                                        ForEach(Self.dependencyRelationOptions, id: \.self) { relation in
                                            Text(relation).tag(relation)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 220)

                                    Stepper("Lag \(dependencyLagDays)d", value: $dependencyLagDays, in: -30...30)
                                        .frame(maxWidth: 180)

                                    TextField("Dependency note", text: $dependencyNote)
                                        .textFieldStyle(.roundedBorder)

                                    Button {
                                        createCrossProjectDependency()
                                    } label: {
                                        Label("Add Link", systemImage: "link.badge.plus")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .hoverHighlight()
                                    .disabled(!canCreateDependency)
                                }
                            }

                            if !selectedPlanOutgoingDependencies.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Outgoing")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    ForEach(selectedPlanOutgoingDependencies.prefix(8)) { dependency in
                                        portfolioDependencyRow(dependency)
                                        if dependency.id != selectedPlanOutgoingDependencies.prefix(8).last?.id {
                                            Divider()
                                        }
                                    }
                                }
                            }

                            if !selectedPlanIncomingDependencies.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Incoming")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    ForEach(selectedPlanIncomingDependencies.prefix(8)) { dependency in
                                        portfolioDependencyRow(dependency)
                                        if dependency.id != selectedPlanIncomingDependencies.prefix(8).last?.id {
                                            Divider()
                                        }
                                    }
                                }
                            }

                            if selectedPlanOutgoingDependencies.isEmpty && selectedPlanIncomingDependencies.isEmpty {
                                Text("No cross-project dependencies registered for this project.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    GroupBox("Actions") {
                        HStack(spacing: 10) {
                            Button {
                                openPlanInWorkspace(selected)
                            } label: {
                                Label("Open In Workspace", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.borderedProminent)
                            .hoverHighlight()
                            .disabled(activePortfolioID == selected.portfolioID)

                            Button(selected.isArchivedValue ? "Restore" : "Archive") {
                                toggleArchive(for: selected)
                            }
                            .buttonStyle(.bordered)
                            .hoverHighlight()

                            Button(role: .destructive) {
                                deletePortfolioPlan(selected)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Spacer()
                        }
                    }

                    GroupBox("Active Work") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(selectedActiveTasks.prefix(12)) { task in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.name)
                                            .font(.body.weight(.medium))
                                        Text(task.boardStatus)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(task.finishDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Calendar.current.startOfDay(for: task.finishDate) < Calendar.current.startOfDay(for: Date()) ? .red : .secondary)
                                }
                                Divider()
                            }
                            if selectedPlanTasks.isEmpty {
                                Text("No tasks stored in this project yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let governance = selectedPlanGovernanceInsight {
                        GroupBox("Governance Signals") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    executiveStatusBadge(title: governance.approvalState, tint: approvalStateColor(for: governance.approvalState))
                                    executiveStatusBadge(title: "\(governance.governanceScore) / 100", tint: governanceScoreColor(score: governance.governanceScore))
                                    executiveStatusBadge(title: "Align \(governance.strategicAlignment)", tint: .blue)
                                    executiveStatusBadge(title: "Risk \(governance.riskScore)", tint: governanceRiskColor(score: governance.riskScore))
                                    Spacer()
                                }

                                detailRow(label: "Review Cadence", value: "\(governance.reviewCadenceDays) days")
                                detailRow(label: "Next Review", value: governance.nextReviewDate?.formatted(date: .abbreviated, time: .omitted) ?? "Not scheduled")
                                detailRow(label: "Workspace", value: governance.workspace)
                                detailRow(label: "Program", value: governance.program)
                                if let archiveReason = governance.archiveReason {
                                    detailRow(label: "Reason", value: archiveReason)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            ContentUnavailableView(
                "No Plan Selected",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Select a project from the portfolio registry to inspect or open it in the workspace.")
            )
            .topAlignedEmptyState()
        }
    }

    private func executiveSummarySection(summary: PortfolioExecutiveSummary) -> some View {
        GroupBox("Executive Health") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Portfolio scoring combines manual health, overdue work, milestone slippage, budget variance, and review cadence into one executive signal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    metricCard(title: "Healthy Projects", value: "\(summary.healthyCount)", tint: .green)
                    metricCard(title: "Watch Projects", value: "\(summary.watchCount)", tint: .orange)
                    metricCard(title: "At Risk Projects", value: "\(summary.atRiskCount)", tint: summary.atRiskCount == 0 ? .green : .red)
                    metricCard(title: "Reviews Due", value: "\(summary.reviewDueCount)", tint: summary.reviewDueCount == 0 ? .secondary : .orange)
                    metricCard(title: "Upcoming Milestones", value: "\(summary.upcomingMilestoneCount)", tint: .blue)
                    metricCard(title: "Slipped Milestones", value: "\(summary.slippedMilestoneCount)", tint: summary.slippedMilestoneCount == 0 ? .green : .red)
                }
            }
        }
    }

    private func executiveRankingsSection(summary: PortfolioExecutiveSummary) -> some View {
        GroupBox("Project Rankings") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Executive Risk Ranking")
                        .font(.headline)
                    if summary.rankedProjects.isEmpty {
                        Text("No visible projects to rank.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(summary.rankedProjects.prefix(6)) { insight in
                            executiveProjectRankingRow(insight: insight)
                            if insight.id != summary.rankedProjects.prefix(6).last?.id {
                                Divider()
                            }
                        }
                    }
                }

                Divider()

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Largest Cost Variances")
                            .font(.headline)
                        ForEach(Array(summary.topCostVarianceProjects.prefix(4)), id: \.id) { insight in
                            compactExecutiveSignalRow(
                                title: insight.title,
                                value: CurrencyFormatting.string(from: insight.costOverrun),
                                subtitle: "\(Int(insight.costVariancePercent.rounded()))% over budget"
                            )
                        }
                        if summary.topCostVarianceProjects.prefix(4).allSatisfy({ $0.costOverrun == 0 }) {
                            Text("No cost overruns in the current scope.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Largest Schedule Slips")
                            .font(.headline)
                        ForEach(Array(summary.topScheduleSlipProjects.prefix(4)), id: \.id) { insight in
                            compactExecutiveSignalRow(
                                title: insight.title,
                                value: "\(insight.maxScheduleSlipDays)d",
                                subtitle: "\(insight.slippedMilestoneCount) slipped milestones"
                            )
                        }
                        if summary.topScheduleSlipProjects.prefix(4).allSatisfy({ $0.maxScheduleSlipDays == 0 }) {
                            Text("No baseline finish slippage in the current scope.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func milestoneRollupSection(summary: PortfolioExecutiveSummary) -> some View {
        GroupBox("Milestone Rollup") {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Upcoming Across Portfolio")
                        .font(.headline)
                    if summary.upcomingMilestones.isEmpty {
                        Text("No upcoming milestones in the next 30 days.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(summary.upcomingMilestones.prefix(8)), id: \.id) { milestone in
                            milestoneRow(milestone, highlight: .blue)
                            if milestone.id != summary.upcomingMilestones.prefix(8).last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Most Slipped Milestones")
                        .font(.headline)
                    if summary.slippedMilestones.isEmpty {
                        Text("No slipped milestones in the current scope.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(summary.slippedMilestones.prefix(8)), id: \.id) { milestone in
                            milestoneRow(milestone, highlight: .red)
                            if milestone.id != summary.slippedMilestones.prefix(8).last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func executiveAttentionSection(summary: PortfolioExecutiveSummary) -> some View {
        GroupBox("Attention Feed") {
            VStack(alignment: .leading, spacing: 10) {
                if summary.attentionFeed.isEmpty {
                    Text("No executive alerts in the current portfolio scope.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(summary.attentionFeed.prefix(12)), id: \.id) { item in
                        HStack(alignment: .top, spacing: 12) {
                            executiveStatusBadge(title: item.severity, tint: executiveRiskColor(for: item.severity == "High" ? "At Risk" : "Watch"))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.headline)
                                    .font(.body.weight(.semibold))
                                Text(item.planTitle)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        if item.id != summary.attentionFeed.prefix(12).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func governanceSummarySection(summary: PortfolioGovernanceSummary) -> some View {
        GroupBox("Governance and Intake") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Use approval state, strategic alignment, risk score, and review cadence to separate candidate work from approved delivery and paused initiatives.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    metricCard(title: "Approved", value: "\(summary.approvedCount)", tint: .blue)
                    metricCard(title: "Intake", value: "\(summary.intakeCount)", tint: .orange)
                    metricCard(title: "On Hold", value: "\(summary.onHoldCount)", tint: summary.onHoldCount == 0 ? .secondary : .red)
                    metricCard(title: "Cancelled", value: "\(summary.cancelledCount)", tint: summary.cancelledCount == 0 ? .secondary : .secondary)
                    metricCard(title: "Reviews Due", value: "\(summary.reviewDueCount)", tint: summary.reviewDueCount == 0 ? .green : .orange)
                    metricCard(title: "Avg Gov Score", value: "\(summary.averageGovernanceScore)", tint: governanceScoreColor(score: summary.averageGovernanceScore))
                    metricCard(title: "Avg Alignment", value: "\(summary.averageStrategicAlignment)", tint: .blue)
                    metricCard(title: "Avg Risk", value: "\(summary.averageRiskScore)", tint: governanceRiskColor(score: summary.averageRiskScore))
                }

                if summary.rankedProjects.isEmpty {
                    Text("No governance data exists in the current scope.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Governance Ranking")
                            .font(.headline)

                        ForEach(summary.rankedProjects.prefix(8)) { insight in
                            governanceProjectRow(insight: insight)
                            if insight.id != summary.rankedProjects.prefix(8).last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func programRoadmapSection(summary: PortfolioProgramRoadmapSummary) -> some View {
        GroupBox("Program Roadmap") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Group projects by program so PMO reviews can see milestone drift, review cadence, and budget posture without opening each plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    metricCard(title: "Programs", value: "\(summary.programs.count)", tint: .purple)
                    metricCard(title: "Timeline Events", value: "\(summary.timelineEvents.count)", tint: .blue)
                    metricCard(title: "Slipped Milestones", value: "\(summary.slippedMilestoneCount)", tint: summary.slippedMilestoneCount == 0 ? .green : .red)
                    metricCard(title: "Reviews Due", value: "\(summary.overdueReviewCount)", tint: summary.overdueReviewCount == 0 ? .green : .orange)
                }

                if summary.programs.isEmpty {
                    Text("Assign projects to programs to build a program roadmap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.programs.prefix(8)) { insight in
                        roadmapProgramRow(insight)
                        if insight.id != summary.programs.prefix(8).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var portfolioTimelineSection: some View {
        GroupBox("Portfolio Timeline") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Each project in the current registry scope is drawn as a summary bar colored by governance health, with milestones and cross-project dependency links.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                PortfolioTimelineView(
                    plans: visiblePlans,
                    dependencies: crossProjectDependencies,
                    selectedPlanID: $selectedPlanID
                )
            }
        }
    }

    private func programTimelineSection(summary: PortfolioProgramRoadmapSummary) -> some View {
        GroupBox("Program Review Timeline") {
            VStack(alignment: .leading, spacing: 10) {
                if summary.timelineEvents.isEmpty {
                    Text("No roadmap milestones or review checkpoints are scheduled in the current scope.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.timelineEvents.prefix(12)) { event in
                        roadmapTimelineRow(event)
                        if event.id != summary.timelineEvents.prefix(12).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func crossProjectDependencySection(summary: PortfolioDependencySummary) -> some View {
        GroupBox("Cross-Project Dependencies") {
            VStack(alignment: .leading, spacing: 14) {
                Text("These links track portfolio-level handoffs across plans and surface where successors are approaching or already past their dependency window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    metricCard(title: "Registered Links", value: "\(summary.dependencies.count)", tint: .indigo)
                    metricCard(title: "Blocked", value: "\(summary.blockedCount)", tint: summary.blockedCount == 0 ? .green : .red)
                    metricCard(title: "High Severity", value: "\(summary.highSeverityCount)", tint: summary.highSeverityCount == 0 ? .green : .red)
                    metricCard(title: "Cross-Program", value: "\(summary.crossProgramCount)", tint: summary.crossProgramCount == 0 ? .secondary : .purple)
                    metricCard(title: "Due Soon", value: "\(summary.dueSoonCount)", tint: summary.dueSoonCount == 0 ? .green : .orange)
                }

                if summary.dependencies.isEmpty {
                    Text("No cross-project dependencies have been registered yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.dependencies.prefix(10)) { dependency in
                        portfolioDependencyRow(dependency)
                        if dependency.id != summary.dependencies.prefix(10).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var reviewPresetSection: some View {
        GroupBox("Review Presets") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Saved presets store portfolio filters, grouping, search, and review cadence so recurring PMO reviews can reopen the same scope instantly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 12, lineSpacing: 10) {
                    TextField("Preset name", text: $reviewPresetName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)

                    Picker("Cadence", selection: $reviewPresetCadenceDays) {
                        ForEach(Self.reviewCadenceOptions, id: \.self) { days in
                            Text("\(days) days").tag(days)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()

                    Button(selectedReviewPreset == nil ? "Save Preset" : "Update Preset") {
                        saveOrUpdateReviewPreset()
                    }
                    .buttonStyle(.borderedProminent)
                    .hoverHighlight()

                    Button("Apply Preset") {
                        applySelectedReviewPreset()
                    }
                    .buttonStyle(.bordered)
                    .hoverHighlight()
                    .disabled(selectedReviewPreset == nil)

                    Button("Capture Review") {
                        captureCurrentPortfolioReview()
                    }
                    .buttonStyle(.bordered)
                    .hoverHighlight()

                    Button("Export Review Pack") {
                        exportPortfolioReviewPack(currentReviewPayload)
                    }
                    .buttonStyle(.bordered)
                    .hoverHighlight()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let selectedReviewPreset {
                    FlowLayout(spacing: 10, lineSpacing: 6) {
                        detailChip("Selected", selectedReviewPreset.name)
                        detailChip("Cadence", "\(selectedReviewPreset.cadenceDays)d")
                        detailChip("Scope", selectedReviewPreset.registryScope)
                        if let selectedPresetNextReviewDate {
                            detailChip("Next Review", selectedPresetNextReviewDate.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                }

                if reviewPresets.isEmpty {
                    Text("No saved review presets yet. Save the current filters as your first recurring portfolio review.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(reviewPresets.prefix(8)) { preset in
                        reviewPresetRow(preset)
                        if preset.id != reviewPresets.prefix(8).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var reviewHistorySection: some View {
        GroupBox("Portfolio Review History") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Capture a dated portfolio review snapshot, reopen it later, compare it against the live portfolio, and export a markdown review pack or delta report.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    TextField("Review title", text: $reviewSnapshotTitle)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)

                    Button("Capture Snapshot") {
                        captureCurrentPortfolioReview()
                    }
                    .buttonStyle(.borderedProminent)
                    .hoverHighlight()

                    if let selectedReviewSnapshot {
                        Button("Apply Snapshot Scope") {
                            applyReviewSnapshot(selectedReviewSnapshot)
                        }
                        .buttonStyle(.bordered)
                        .hoverHighlight()

                        Button("Export Snapshot") {
                            exportPortfolioReviewPack(selectedReviewSnapshot.payload, snapshotTitleOverride: selectedReviewSnapshot.title)
                        }
                        .buttonStyle(.bordered)
                        .hoverHighlight()
                    }

                    if let delta = selectedReviewDelta {
                        Button("Export Delta") {
                            exportPortfolioReviewDelta(delta, baselineTitle: selectedReviewSnapshot?.title ?? "Baseline Review")
                        }
                        .buttonStyle(.bordered)
                        .hoverHighlight()
                    }

                    Spacer()
                }

                if let selectedReviewSnapshot {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            executiveStatusBadge(title: selectedReviewSnapshot.title, tint: .orange)
                            if let presetName = selectedReviewSnapshot.presetName {
                                executiveStatusBadge(title: presetName, tint: .blue)
                            }
                            Text(selectedReviewSnapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                deleteReviewSnapshot(selectedReviewSnapshot)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .hoverHighlight()
                        }

                        HStack(spacing: 10) {
                            detailChip("Projects", "\(selectedReviewSnapshot.visibleProjectCount)")
                            detailChip("At Risk", "\(selectedReviewSnapshot.atRiskProjectCount)")
                            detailChip("Blocked", "\(selectedReviewSnapshot.blockedDependencyCount)")
                            detailChip("Slip", "\(selectedReviewSnapshot.slippedMilestoneCount)")
                            detailChip("Overloaded", "\(selectedReviewSnapshot.overloadedResourceCount)")
                        }

                        if let delta = selectedReviewDelta {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Current vs Snapshot")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    reviewDeltaPill("Projects", delta.visibleProjectDelta, accent: .blue)
                                    reviewDeltaPill("At Risk", delta.atRiskProjectDelta, accent: .red)
                                    reviewDeltaPill("Blocked", delta.blockedDependencyDelta, accent: .orange)
                                    reviewDeltaPill("Reviews", delta.reviewDueDelta, accent: .orange)
                                    reviewDeltaPill("Slip", delta.slippedMilestoneDelta, accent: .red)
                                }
                                HStack(spacing: 8) {
                                    reviewDeltaPill("Overload", delta.overloadedResourceDelta, accent: .red)
                                    reviewDeltaPill("Overdue", delta.overdueTaskDelta, accent: .red)
                                    reviewCurrencyDeltaPill("Budget", delta.budgetDelta, positiveIsGood: true)
                                    reviewCurrencyDeltaPill("Actual", delta.actualCostDelta, positiveIsGood: false)
                                }
                            }
                        }
                    }
                }

                if reviewSnapshots.isEmpty {
                    Text("No review snapshots captured yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(reviewSnapshots.prefix(10)) { snapshot in
                        reviewSnapshotRow(snapshot)
                        if snapshot.id != reviewSnapshots.prefix(10).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func resourceCapacitySection(summary: PortfolioResourceCapacitySummary) -> some View {
        GroupBox("Resource Capacity") {
            VStack(alignment: .leading, spacing: 14) {
                Text("This rollup merges matching resources across projects, compares weekly demand against one capacity baseline per person, and surfaces multi-project load conflicts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    metricCard(title: "Unique Resources", value: "\(summary.uniqueResourceCount)", tint: .blue)
                    metricCard(title: "Shared Resources", value: "\(summary.sharedResourceCount)", tint: summary.sharedResourceCount == 0 ? .secondary : .indigo)
                    metricCard(title: "Overloaded Resources", value: "\(summary.overloadedResourceCount)", tint: summary.overloadedResourceCount == 0 ? .green : .red)
                    metricCard(title: "Overloaded Weeks", value: "\(summary.overloadedWeekCount)", tint: summary.overloadedWeekCount == 0 ? .green : .red)
                    metricCard(title: "Double-Booked Weeks", value: "\(summary.doubleBookedWeekCount)", tint: summary.doubleBookedWeekCount == 0 ? .green : .orange)
                }

                if summary.resources.isEmpty {
                    Text("No resource assignments exist in the current portfolio scope.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Top Capacity Risks")
                            .font(.headline)

                        ForEach(summary.resources.prefix(8)) { resource in
                            portfolioResourceRow(resource)
                            if resource.id != summary.resources.prefix(8).last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func roadmapProgramRow(_ insight: PortfolioProgramRoadmapSummary.ProgramInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(insight.program)
                            .font(.headline)
                        if insight.slippedMilestoneCount > 0 {
                            executiveStatusBadge(title: "\(insight.slippedMilestoneCount) slipped", tint: .red)
                        }
                        if insight.reviewDueCount > 0 {
                            executiveStatusBadge(title: "\(insight.reviewDueCount) reviews", tint: .orange)
                        }
                    }
                    Text(insight.workspaceNames.joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(insight.nextMilestoneDate?.formatted(date: .abbreviated, time: .omitted) ?? "No milestone")
                        .font(.caption.monospacedDigit())
                    Text("\(insight.projectCount) projects")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                detailChip("At Risk", "\(insight.atRiskProjectCount)")
                detailChip("Budget", CurrencyFormatting.string(from: insight.totalBudget))
                detailChip("Actual", CurrencyFormatting.string(from: insight.totalActualCost))
            }
        }
    }

    private func roadmapTimelineRow(_ event: PortfolioProgramRoadmapSummary.TimelineEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            executiveStatusBadge(title: event.kind, tint: timelineEventColor(for: event))

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.body.weight(.medium))
                Text("\(event.program) • \(event.planTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if event.isLate && event.slipDays > 0 {
                    Text("Slipped \(event.slipDays)d from baseline.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            Text(event.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption.monospacedDigit())
                .foregroundStyle(event.isLate ? .red : .secondary)
        }
    }

    private func governanceProjectRow(insight: PortfolioGovernanceSummary.ProjectInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(insight.title)
                            .font(.headline)
                        executiveStatusBadge(title: insight.approvalState, tint: approvalStateColor(for: insight.approvalState))
                        executiveStatusBadge(title: "\(insight.governanceScore)", tint: governanceScoreColor(score: insight.governanceScore))
                    }
                    Text("\(insight.workspace) • \(insight.program)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(insight.stage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(insight.nextReviewDate?.formatted(date: .abbreviated, time: .omitted) ?? "No next review")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(insight.reviewOverdue ? .red : (insight.reviewDueSoon ? .orange : .secondary))
                }
            }

            HStack(spacing: 8) {
                detailChip("Align", "\(insight.strategicAlignment)")
                detailChip("Risk", "\(insight.riskScore)")
                detailChip("Cadence", "\(insight.reviewCadenceDays)d")
                if let archiveReason = insight.archiveReason {
                    detailChip("Reason", archiveReason)
                }
            }
        }
    }

    private func portfolioDependencyRow(_ dependency: PortfolioDependencySummary.DependencyInsight) -> some View {
        HStack(alignment: .top, spacing: 12) {
            executiveStatusBadge(title: dependency.severity, tint: dependencySeverityColor(dependency.severity))

            VStack(alignment: .leading, spacing: 4) {
                Text("\(dependency.sourceTaskName) -> \(dependency.targetTaskName)")
                    .font(.body.weight(.medium))
                Text("\(dependency.sourcePlanTitle) -> \(dependency.targetPlanTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(dependency.blockerReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    detailChip("Type", dependency.relationType)
                    detailChip("Lag", "\(dependency.lagDays)d")
                    if dependency.isCrossProgram {
                        detailChip("Programs", "\(dependency.sourceProgram) -> \(dependency.targetProgram)")
                    }
                }
                if let note = dependency.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(dependency.targetDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(dependency.severity == "High" ? .red : .secondary)
                Text("Need by \(dependency.requiredDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    deleteCrossProjectDependency(id: dependency.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.accessoryBar)
                .accessibilityLabel("Delete cross-project dependency")
            }
        }
    }

    private func reviewPresetRow(_ preset: PortfolioReviewPreset) -> some View {
        let selected = selectedReviewPresetID == preset.uniqueID
        let nextReviewDate = reviewSnapshots
            .filter { $0.presetID == preset.uniqueID }
            .max { $0.createdAt < $1.createdAt }
            .flatMap { Calendar.current.date(byAdding: .day, value: max(7, preset.cadenceDays), to: $0.createdAt) }

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(preset.name)
                        .font(.headline)
                    if selected {
                        executiveStatusBadge(title: "Selected", tint: .blue)
                    }
                }
                Text("\(preset.registryScope) • \(preset.healthScope) • \(preset.approvalScope) • \(preset.grouping)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    detailChip("Cadence", "\(preset.cadenceDays)d")
                    if !preset.searchText.isEmpty {
                        detailChip("Search", preset.searchText)
                    }
                    if let nextReviewDate {
                        detailChip("Next", nextReviewDate.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Select") {
                    selectReviewPreset(preset)
                }
                .buttonStyle(.bordered)
                .hoverHighlight()

                Button("Apply") {
                    applyReviewPreset(preset)
                }
                .buttonStyle(.bordered)
                .hoverHighlight()

                Button(role: .destructive) {
                    deleteReviewPreset(preset)
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete review preset")
                .buttonStyle(.bordered)
                .hoverHighlight()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
        )
    }

    private func reviewSnapshotRow(_ snapshot: PortfolioReviewSnapshot) -> some View {
        let selected = selectedReviewSnapshotID == snapshot.uniqueID
        return Button {
            selectedReviewSnapshotID = snapshot.uniqueID
            reviewSnapshotTitle = snapshot.title
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(snapshot.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let presetName = snapshot.presetName {
                            executiveStatusBadge(title: presetName, tint: .blue)
                        }
                    }
                    Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        detailChip("Projects", "\(snapshot.visibleProjectCount)")
                        detailChip("At Risk", "\(snapshot.atRiskProjectCount)")
                        detailChip("Blocked", "\(snapshot.blockedDependencyCount)")
                        detailChip("Slip", "\(snapshot.slippedMilestoneCount)")
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(CurrencyFormatting.string(from: snapshot.budgetTotal))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatting.string(from: snapshot.actualCostTotal))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.orange.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
        .hoverHighlight()
    }

    private func reviewDeltaPill(_ title: String, _ delta: Int, accent: Color) -> some View {
        let color: Color = delta > 0 ? accent : delta < 0 ? .green : .secondary
        return Text("\(title) \(signedDeltaText(delta))")
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func reviewCurrencyDeltaPill(_ title: String, _ delta: Double, positiveIsGood: Bool) -> some View {
        let rounded = delta.rounded()
        let color: Color
        if rounded == 0 {
            color = .secondary
        } else if positiveIsGood {
            color = rounded > 0 ? .green : .red
        } else {
            color = rounded > 0 ? .red : .green
        }

        let text = "\(title) \(rounded >= 0 ? "+" : "")\(CurrencyFormatting.string(from: rounded))"
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func resourceConflictSection(summary: PortfolioResourceCapacitySummary) -> some View {
        GroupBox("Resource Conflict Feed") {
            VStack(alignment: .leading, spacing: 10) {
                if summary.alerts.isEmpty {
                    Text("No cross-project overload or double-booking alerts in the current scope.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.alerts.prefix(12)) { alert in
                        HStack(alignment: .top, spacing: 12) {
                            executiveStatusBadge(
                                title: alert.severity,
                                tint: alert.severity == "High" ? .red : .orange
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(alert.resourceName)
                                    .font(.body.weight(.semibold))
                                Text(alert.headline)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(alert.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(alert.contributingPlans.joined(separator: " • "))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                        if alert.id != summary.alerts.prefix(12).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func portfolioResourceRow(_ resource: PortfolioResourceCapacitySummary.ResourceInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(resource.displayName)
                            .font(.headline)
                        if resource.overloadedWeekCount > 0 {
                            executiveStatusBadge(title: "Overloaded", tint: .red)
                        } else if resource.doubleBookedWeekCount > 0 {
                            executiveStatusBadge(title: "Shared", tint: .orange)
                        }
                    }

                    Text(resource.emailAddress ?? resource.group ?? "No contact metadata")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(resource.peakAllocationPercent.rounded()))% peak")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(resource.peakAllocationPercent > 100 ? .red : .primary)
                    Text("\(resource.projectCount) projects")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                detailChip("Overloaded", "\(resource.overloadedWeekCount) weeks")
                detailChip("Double-booked", "\(resource.doubleBookedWeekCount) weeks")
                detailChip("Current", "\(Int(resource.currentAllocationPercent.rounded()))%")
                detailChip("Overload", hoursText(resource.overloadHours))
            }

            if let peakWeek = resource.peakWeek {
                Text("Peak week \(peakWeek.weekStart.formatted(date: .abbreviated, time: .omitted)) • \(Int(peakWeek.totalHours.rounded()))h / \(Int(peakWeek.capacityHours.rounded()))h • \(peakWeek.contributingPlans.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let weeks = resource.weeklyDemand
                .filter { $0.totalHours > 0.01 }
                .prefix(6)

            if !weeks.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(weeks), id: \.id) { week in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(week.weekStart.formatted(date: .numeric, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(Int(week.allocationPercent.rounded()))%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(week.isOverloaded ? .red : (week.isDoubleBooked ? .orange : .primary))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    week.isOverloaded
                                        ? Color.red.opacity(0.12)
                                        : (week.isDoubleBooked ? Color.orange.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                                )
                        )
                    }
                }
            }
        }
    }

    private func executiveProjectRankingRow(insight: PortfolioExecutiveSummary.ProjectInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(insight.title)
                            .font(.headline)
                        executiveStatusBadge(title: insight.riskBand, tint: executiveRiskColor(for: insight.riskBand))
                        executiveStatusBadge(title: "\(insight.score)", tint: executiveScoreColor(score: insight.score))
                    }

                    Text("\(insight.workspace) • \(insight.program)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(CurrencyFormatting.string(from: insight.costOverrun))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(insight.costOverrun > 0 ? .red : .secondary)
                    Text(insight.costOverrun > 0 ? "over budget" : "within budget")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                detailChip("Active", "\(insight.activeTaskCount)")
                detailChip("Overdue", "\(insight.overdueTaskCount)")
                detailChip("Slip", "\(insight.maxScheduleSlipDays)d")
                detailChip("Milestones", "\(insight.upcomingMilestoneCount) upcoming")
                detailChip("Done", "\(Int(insight.completionPercent.rounded()))%")
            }

            Text(insight.attentionReasons.joined(separator: " • "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func compactExecutiveSignalRow(title: String, value: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func hoursText(_ hours: Double) -> String {
        "\(Int(hours.rounded()))h"
    }

    private func milestoneRow(_ milestone: PortfolioExecutiveSummary.MilestoneRollup, highlight: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.taskName)
                    .font(.body.weight(.medium))
                Text(milestone.planTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(milestone.finishDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption.monospacedDigit())
                if milestone.slipDays > 0 {
                    Text("+\(milestone.slipDays)d")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(highlight)
                }
            }
        }
    }

    private func portfolioRow(for plan: PortfolioProjectPlan, governance: PortfolioGovernanceSummary.ProjectInsight?) -> some View {
        let selected = selectedPlanID == plan.portfolioID
        let planTaskSnapshots = taskSnapshots(for: plan)
        let activeTaskCount = planTaskSnapshots.filter { $0.isActive && $0.percentComplete < 100 }.count
        let overdueTaskCount = planTaskSnapshots.filter {
            $0.isActive
                && $0.percentComplete < 100
                && Calendar.current.startOfDay(for: $0.finishDate) < Calendar.current.startOfDay(for: Date())
        }.count
        let budgetVariance = plan.portfolioBudget - plan.portfolioActualCost

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(trimmedOrFallback(plan.title, fallback: "Untitled Plan"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if plan.isArchivedValue {
                            Text("Archived")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.thinMaterial, in: Capsule())
                        }
                        if activePortfolioID == plan.portfolioID {
                            Text("Workspace")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                        if let health = normalizedMetadata(plan.portfolioHealth) {
                            portfolioMetadataBadge(health, tint: healthColor(for: plan.portfolioHealth))
                        }
                        if let approval = normalizedMetadata(plan.portfolioApprovalState) {
                            portfolioMetadataBadge(approval, tint: approvalStateColor(for: approval))
                        }
                    }

                    Text(trimmedOrFallback(plan.company, fallback: trimmedOrFallback(plan.manager, fallback: "No owner")))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    FlowLayout(spacing: 8, lineSpacing: 6) {
                        detailChip("Workspace", trimmedOrFallback(plan.portfolioWorkspace ?? "", fallback: "Unassigned"))
                        detailChip("Program", trimmedOrFallback(plan.portfolioProgram ?? "", fallback: "Unassigned"))
                        if let priority = normalizedMetadata(plan.portfolioPriorityBand) {
                            detailChip("Priority", priority)
                        }
                        if let governance {
                            detailChip("Gov", "\(governance.governanceScore)")
                        }
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    Text("Updated \(plan.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button {
                            openPlanInWorkspace(plan)
                        } label: {
                            Label("Open", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.borderedProminent)
                        .hoverHighlight()
                        .disabled(activePortfolioID == plan.portfolioID)

                        Button {
                            toggleArchive(for: plan)
                        } label: {
                            Label(plan.isArchivedValue ? "Restore" : "Archive", systemImage: plan.isArchivedValue ? "archivebox.badge.plus" : "archivebox")
                        }
                        .buttonStyle(.bordered)
                        .hoverHighlight()

                        Button(role: .destructive) {
                            deletePortfolioPlan(plan)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete plan")
                        .buttonStyle(.bordered)
                        .hoverHighlight()
                    }
                }
            }

            FlowLayout(spacing: 10, lineSpacing: 6) {
                Label("\(plan.taskCount) tasks", systemImage: "list.bullet")
                Label("\(activeTaskCount) active", systemImage: "play.circle")
                Label("\(overdueTaskCount) overdue", systemImage: "exclamationmark.triangle")
                Label(CurrencyFormatting.string(from: plan.portfolioBudget), systemImage: "dollarsign.circle")
                Label(CurrencyFormatting.string(from: plan.portfolioActualCost), systemImage: "chart.line.uptrend.xyaxis")
                Label(CurrencyFormatting.string(from: budgetVariance), systemImage: budgetVariance >= 0 ? "arrow.down.right.circle" : "arrow.up.right.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            FlowLayout(spacing: 10, lineSpacing: 6) {
                detailChip("Resources", "\(plan.resources.count)")
                detailChip("Calendars", "\(plan.calendars.count)")
                detailChip("Sprints", "\(plan.sprints.count)")
                detailChip("Snapshots", "\(plan.statusSnapshots.count)")
                detailChip("Workflows", "\(plan.workflowColumns.count)")
                if let stage = normalizedMetadata(plan.portfolioStage) {
                    detailChip("Stage", stage)
                }
                if let governance {
                    detailChip("Align", "\(governance.strategicAlignment)")
                    detailChip("Risk", "\(governance.riskScore)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedPlanID = plan.portfolioID
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private func detailChip(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(value)
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
    }

    private func executiveStatusBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func portfolioMetadataBadge(_ value: String, tint: Color) -> some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func normalizedMetadata(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func executiveRiskColor(for riskBand: String) -> Color {
        switch riskBand.lowercased() {
        case "healthy":
            return .green
        case "watch":
            return .orange
        case "at risk":
            return .red
        default:
            return .secondary
        }
    }

    private func executiveScoreColor(score: Int) -> Color {
        switch score {
        case 80...100:
            return .green
        case 60..<80:
            return .orange
        default:
            return .red
        }
    }

    private func healthColor(for rawHealth: String?) -> Color {
        switch normalizedMetadata(rawHealth)?.lowercased() {
        case "green":
            return .green
        case "amber":
            return .orange
        case "red":
            return .red
        case "on hold":
            return .secondary
        default:
            return .secondary
        }
    }

    private func approvalStateColor(for rawApprovalState: String?) -> Color {
        switch normalizedMetadata(rawApprovalState)?.lowercased() {
        case "approved":
            return .blue
        case "intake review":
            return .orange
        case "proposed":
            return .yellow
        case "on hold":
            return .red
        case "cancelled":
            return .secondary
        default:
            return .secondary
        }
    }

    private func governanceScoreColor(score: Int) -> Color {
        switch score {
        case 75...100:
            return .green
        case 55..<75:
            return .orange
        default:
            return .red
        }
    }

    private func governanceRiskColor(score: Int) -> Color {
        switch score {
        case 0..<35:
            return .green
        case 35..<65:
            return .orange
        default:
            return .red
        }
    }

    private func dependencySeverityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "high":
            return .red
        case "medium":
            return .orange
        case "low":
            return .blue
        case "resolved":
            return .green
        default:
            return .secondary
        }
    }

    private func timelineEventColor(for event: PortfolioProgramRoadmapSummary.TimelineEvent) -> Color {
        if event.isLate {
            return .red
        }
        if event.isReview {
            return .orange
        }
        return .blue
    }

    private var canCreateDependency: Bool {
        guard let selectedPlan else { return false }
        guard let sourceTaskID = selectedDependencySourceTaskID,
              let targetPlanID = selectedDependencyTargetPlanID,
              let targetTaskID = selectedDependencyTargetTaskID else {
            return false
        }
        guard selectedPlan.portfolioID != targetPlanID else { return false }
        return sourceTaskID != targetTaskID
    }

    private func signedDeltaText(_ delta: Int) -> String {
        delta > 0 ? "+\(delta)" : "\(delta)"
    }

    private func registryScopeValue(from rawValue: String) -> RegistryScope {
        RegistryScope(rawValue: rawValue) ?? .active
    }

    private func healthScopeValue(from rawValue: String) -> HealthScope {
        HealthScope(rawValue: rawValue) ?? .all
    }

    private func approvalScopeValue(from rawValue: String) -> ApprovalScope {
        ApprovalScope(rawValue: rawValue) ?? .all
    }

    private func groupingValue(from rawValue: String) -> RegistryGrouping {
        RegistryGrouping(rawValue: rawValue) ?? .none
    }

    private func applyViewSettings(_ settings: PortfolioReviewViewSettings) {
        registryScope = registryScopeValue(from: settings.registryScope)
        healthScope = healthScopeValue(from: settings.healthScope)
        approvalScope = approvalScopeValue(from: settings.approvalScope)
        registryGrouping = groupingValue(from: settings.grouping)
        searchText = settings.searchText
        reviewPresetCadenceDays = max(7, settings.cadenceDays)
    }

    private func selectReviewPreset(_ preset: PortfolioReviewPreset) {
        selectedReviewPresetID = preset.uniqueID
        reviewPresetName = preset.name
        reviewPresetCadenceDays = max(7, preset.cadenceDays)
    }

    private func applyReviewPreset(_ preset: PortfolioReviewPreset) {
        selectReviewPreset(preset)
        applyViewSettings(preset.viewSettings)
    }

    private func applySelectedReviewPreset() {
        guard let selectedReviewPreset else { return }
        applyReviewPreset(selectedReviewPreset)
    }

    private func saveOrUpdateReviewPreset() {
        let name = reviewPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = currentReviewViewSettings
        if let selectedReviewPreset {
            selectedReviewPreset.update(name: name, viewSettings: settings)
            modelContext.saveReportingFailures()
            importStatusMessage = "Updated review preset \(selectedReviewPreset.name)."
        } else {
            let preset = PortfolioReviewPreset(name: name, viewSettings: settings)
            modelContext.insert(preset)
            modelContext.saveReportingFailures()
            selectedReviewPresetID = preset.uniqueID
            reviewPresetName = preset.name
            importStatusMessage = "Saved review preset \(preset.name)."
        }
        syncReviewSelections()
    }

    private func captureCurrentPortfolioReview() {
        let payload = currentReviewPayload
        let title = reviewSnapshotTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = PortfolioReviewSnapshot(title: title, preset: selectedReviewPreset, payload: payload)
        modelContext.insert(snapshot)
        modelContext.saveReportingFailures()
        selectedReviewSnapshotID = snapshot.uniqueID
        reviewSnapshotTitle = snapshot.title
        importStatusMessage = "Captured portfolio review \(snapshot.title)."
    }

    private func applyReviewSnapshot(_ snapshot: PortfolioReviewSnapshot) {
        selectedReviewSnapshotID = snapshot.uniqueID
        reviewSnapshotTitle = snapshot.title
        applyViewSettings(snapshot.viewSettings)
        if let presetID = snapshot.presetID, let preset = reviewPresets.first(where: { $0.uniqueID == presetID }) {
            selectReviewPreset(preset)
        }
    }

    private func deleteReviewSnapshot(_ snapshot: PortfolioReviewSnapshot) {
        let deletedID = snapshot.uniqueID
        modelContext.delete(snapshot)
        modelContext.saveReportingFailures()
        if selectedReviewSnapshotID == deletedID {
            selectedReviewSnapshotID = reviewSnapshots.first(where: { $0.uniqueID != deletedID })?.uniqueID
        }
        syncReviewSelections()
    }

    private func deleteReviewPreset(_ preset: PortfolioReviewPreset) {
        let deletedID = preset.uniqueID
        modelContext.delete(preset)
        modelContext.saveReportingFailures()
        if selectedReviewPresetID == deletedID {
            selectedReviewPresetID = reviewPresets.first(where: { $0.uniqueID != deletedID })?.uniqueID
        }
        syncReviewSelections()
    }

    private func exportPortfolioReviewPack(_ payload: PortfolioReviewSnapshotPayload, snapshotTitleOverride: String? = nil) {
        let markdown = portfolioReviewMarkdown(payload, snapshotTitleOverride: snapshotTitleOverride)
        let panel = NSSavePanel()
        let fileTitle = (snapshotTitleOverride ?? payload.title).trimmingCharacters(in: .whitespacesAndNewlines)
        panel.nameFieldStringValue = "\(fileTitle.isEmpty ? "Portfolio Review" : fileTitle) \(PDFExporter.fileNameTimestamp).md"
        panel.allowedContentTypes = [UTType.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func exportPortfolioReviewDelta(_ delta: PortfolioReviewDelta, baselineTitle: String) {
        let markdown = portfolioReviewDeltaMarkdown(delta, baselineTitle: baselineTitle)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Portfolio Review Delta \(PDFExporter.fileNameTimestamp).md"
        panel.allowedContentTypes = [UTType.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func portfolioReviewMarkdown(_ payload: PortfolioReviewSnapshotPayload, snapshotTitleOverride: String? = nil) -> String {
        let trimmedTitle = (snapshotTitleOverride ?? payload.title).trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? "Portfolio Review" : trimmedTitle
        var lines: [String] = [
            "# \(title)",
            "",
            "Generated: \(ISO8601DateFormatter().string(from: payload.capturedAt))",
            "",
            "## Review Scope",
            "- Preset: \(payload.presetName ?? "Ad hoc")",
            "- Registry scope: \(payload.viewSettings.registryScope)",
            "- Health scope: \(payload.viewSettings.healthScope)",
            "- Approval scope: \(payload.viewSettings.approvalScope)",
            "- Grouping: \(payload.viewSettings.grouping)",
            "- Search: \(payload.viewSettings.searchText.isEmpty ? "None" : payload.viewSettings.searchText)",
            "- Review cadence: \(payload.viewSettings.cadenceDays) days",
            "",
            "## Portfolio Totals",
            "- Visible projects: \(payload.visibleProjectCount)",
            "- Active projects: \(payload.activeProjectCount)",
            "- Archived projects: \(payload.archivedProjectCount)",
            "- Workspaces: \(payload.workspaceCount)",
            "- Programs: \(payload.programCount)",
            "- At-risk projects: \(payload.atRiskProjectCount)",
            "- Review items due: \(payload.reviewDueCount)",
            "- Overdue work items: \(payload.overdueTaskCount)",
            "- Blocked cross-project dependencies: \(payload.blockedDependencyCount)",
            "- High-severity dependency links: \(payload.highDependencyCount)",
            "- Cross-program dependency links: \(payload.crossProgramDependencyCount)",
            "- Slipped milestones: \(payload.slippedMilestoneCount)",
            "- Overloaded resources: \(payload.overloadedResourceCount)",
            "- Portfolio budget: \(CurrencyFormatting.string(from: payload.budgetTotal))",
            "- Portfolio actual cost: \(CurrencyFormatting.string(from: payload.actualCostTotal))"
        ]

        lines.append("")
        lines.append("## Governance")
        lines.append("- Approved: \(payload.approvedCount)")
        lines.append("- Intake: \(payload.intakeCount)")
        lines.append("- On hold: \(payload.onHoldCount)")

        lines.append("")
        lines.append("## Executive Risk Ranking")
        lines.append(contentsOf: payload.projectSummaries.map { summary in
            "- \(summary.title) [\(summary.riskBand), \(summary.score)/100] • \(summary.workspace) / \(summary.program) • overdue \(summary.overdueTaskCount) • slipped milestones \(summary.slippedMilestoneCount) • overrun \(CurrencyFormatting.string(from: summary.costOverrun)) • completion \(Int(summary.completionPercent.rounded()))%"
        })

        lines.append("")
        lines.append("## Attention Feed")
        if payload.attentionItems.isEmpty {
            lines.append("- No portfolio attention items")
        } else {
            lines.append(contentsOf: payload.attentionItems.map { item in
                "- [\(item.severity)] \(item.planTitle): \(item.headline) — \(item.detail)"
            })
        }

        lines.append("")
        lines.append("## Program Roadmap")
        if payload.programItems.isEmpty {
            lines.append("- No program roadmap items")
        } else {
            lines.append(contentsOf: payload.programItems.map { item in
                "- \(item.program): \(item.projectCount) projects, \(item.atRiskProjectCount) at risk, \(item.reviewDueCount) reviews due, \(item.slippedMilestoneCount) slipped milestones, next milestone \(item.nextMilestoneDate?.formatted(date: .abbreviated, time: .omitted) ?? "None")"
            })
        }

        lines.append("")
        lines.append("## Cross-Project Dependencies")
        if payload.dependencyItems.isEmpty {
            lines.append("- No cross-project dependencies")
        } else {
            lines.append(contentsOf: payload.dependencyItems.map { item in
                "- [\(item.severity)] \(item.sourcePlanTitle): \(item.sourceTaskName) -> \(item.targetPlanTitle): \(item.targetTaskName) (\(item.relationType), lag \(item.lagDays)d, target \(item.targetDate.formatted(date: .abbreviated, time: .omitted))) — \(item.blockerReason)"
            })
        }

        return lines.joined(separator: "\n")
    }

    private func portfolioReviewDeltaMarkdown(_ delta: PortfolioReviewDelta, baselineTitle: String) -> String {
        var lines: [String] = [
            "# Portfolio Review Delta",
            "",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "",
            "## Review Pair",
            "- Current: \(delta.current.title)",
            "- Baseline: \(baselineTitle)",
            "",
            "## Metric Deltas",
            "- Visible projects: \(delta.current.visibleProjectCount) (\(signedDeltaText(delta.visibleProjectDelta)))",
            "- At-risk projects: \(delta.current.atRiskProjectCount) (\(signedDeltaText(delta.atRiskProjectDelta)))",
            "- Blocked dependencies: \(delta.current.blockedDependencyCount) (\(signedDeltaText(delta.blockedDependencyDelta)))",
            "- High-severity dependencies: \(delta.current.highDependencyCount) (\(signedDeltaText(delta.highDependencyDelta)))",
            "- Reviews due: \(delta.current.reviewDueCount) (\(signedDeltaText(delta.reviewDueDelta)))",
            "- Slipped milestones: \(delta.current.slippedMilestoneCount) (\(signedDeltaText(delta.slippedMilestoneDelta)))",
            "- Overloaded resources: \(delta.current.overloadedResourceCount) (\(signedDeltaText(delta.overloadedResourceDelta)))",
            "- Overdue work items: \(delta.current.overdueTaskCount) (\(signedDeltaText(delta.overdueTaskDelta)))",
            "- Portfolio budget: \(CurrencyFormatting.string(from: delta.current.budgetTotal)) (\(delta.budgetDelta >= 0 ? "+" : "")\(CurrencyFormatting.string(from: delta.budgetDelta)))",
            "- Portfolio actual cost: \(CurrencyFormatting.string(from: delta.current.actualCostTotal)) (\(delta.actualCostDelta >= 0 ? "+" : "")\(CurrencyFormatting.string(from: delta.actualCostDelta)))",
            "",
            "## New Attention Items"
        ]

        if delta.newAttentionHeadlines.isEmpty {
            lines.append("- None")
        } else {
            lines.append(contentsOf: delta.newAttentionHeadlines.map { "- \($0.replacingOccurrences(of: "|", with: ": "))" })
        }

        lines.append("")
        lines.append("## Resolved Attention Items")
        if delta.resolvedAttentionHeadlines.isEmpty {
            lines.append("- None")
        } else {
            lines.append(contentsOf: delta.resolvedAttentionHeadlines.map { "- \($0.replacingOccurrences(of: "|", with: ": "))" })
        }

        lines.append("")
        lines.append("## New Blocked Dependencies")
        if delta.newBlockedDependencies.isEmpty {
            lines.append("- None")
        } else {
            lines.append(contentsOf: delta.newBlockedDependencies.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private func syncReviewSelections() {
        if !reviewPresets.contains(where: { $0.uniqueID == selectedReviewPresetID }) {
            selectedReviewPresetID = reviewPresets.first?.uniqueID
        }
        if let selectedReviewPreset {
            reviewPresetName = selectedReviewPreset.name
            reviewPresetCadenceDays = max(7, selectedReviewPreset.cadenceDays)
        } else if reviewPresetName.isEmpty {
            reviewPresetCadenceDays = 14
        }

        if !reviewSnapshots.contains(where: { $0.uniqueID == selectedReviewSnapshotID }) {
            selectedReviewSnapshotID = reviewSnapshots.first?.uniqueID
        }
        if let selectedReviewSnapshot, reviewSnapshotTitle.isEmpty {
            reviewSnapshotTitle = selectedReviewSnapshot.title
        }
    }

    private func healthMatches(_ plan: PortfolioProjectPlan) -> Bool {
        switch healthScope {
        case .all:
            return true
        case .atRisk:
            return isAtRisk(plan)
        case .healthy:
            return !isAtRisk(plan)
        }
    }

    private func isAtRisk(_ plan: PortfolioProjectPlan) -> Bool {
        if let health = normalizedMetadata(plan.portfolioHealth)?.lowercased(),
           health == "amber" || health == "red" || health == "on hold" {
            return true
        }

        let today = Calendar.current.startOfDay(for: Date())
        let hasOverdueTask = plan.tasks.contains {
            $0.isActive
                && $0.percentComplete < 100
                && Calendar.current.startOfDay(for: $0.finishDate) < today
        }
        if hasOverdueTask {
            return true
        }

        return plan.portfolioBudget > 0 && plan.portfolioActualCost > plan.portfolioBudget
    }

    private func approvalMatches(_ plan: PortfolioProjectPlan) -> Bool {
        let approval = normalizedMetadata(plan.portfolioApprovalState)?.lowercased()
        switch approvalScope {
        case .all:
            return true
        case .approved:
            return approval == "approved"
        case .intake:
            return approval == "proposed" || approval == "intake review" || approval == nil
        case .paused:
            return approval == "on hold" || approval == "cancelled" || plan.isArchivedValue
        }
    }

    private func metadataTextBinding(_ keyPath: ReferenceWritableKeyPath<PortfolioProjectPlan, String?>) -> Binding<String> {
        Binding(
            get: { selectedPlan?[keyPath: keyPath] ?? "" },
            set: { newValue in
                updateMetadata(keyPath, value: normalizedMetadata(newValue))
            }
        )
    }

    private func metadataSelectionBinding(_ keyPath: ReferenceWritableKeyPath<PortfolioProjectPlan, String?>) -> Binding<String> {
        Binding(
            get: { selectedPlan?[keyPath: keyPath] ?? "" },
            set: { newValue in
                updateMetadata(keyPath, value: normalizedMetadata(newValue))
            }
        )
    }

    private func metadataDateBinding(_ keyPath: ReferenceWritableKeyPath<PortfolioProjectPlan, Date?>) -> Binding<Date> {
        Binding(
            get: { selectedPlan?[keyPath: keyPath] ?? Calendar.current.startOfDay(for: Date()) },
            set: { newValue in
                updateMetadataDate(keyPath, value: Calendar.current.startOfDay(for: newValue))
            }
        )
    }

    private func metadataOptionalIntBinding(_ keyPath: ReferenceWritableKeyPath<PortfolioProjectPlan, Int?>, defaultValue: Int) -> Binding<Int> {
        Binding(
            get: { selectedPlan?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                updateMetadataInt(keyPath, value: newValue)
            }
        )
    }

    private func updateMetadata(_ keyPath: ReferenceWritableKeyPath<PortfolioProjectPlan, String?>, value: String?) {
        guard let selectedPlan else { return }
        guard selectedPlan[keyPath: keyPath] != value else { return }
        selectedPlan[keyPath: keyPath] = value
        selectedPlan.updatedAt = Date()
        modelContext.saveReportingFailures()
    }

    private func updateMetadataDate(_ keyPath: ReferenceWritableKeyPath<PortfolioProjectPlan, Date?>, value: Date?) {
        guard let selectedPlan else { return }
        guard selectedPlan[keyPath: keyPath] != value else { return }
        selectedPlan[keyPath: keyPath] = value
        selectedPlan.updatedAt = Date()
        modelContext.saveReportingFailures()
    }

    private func updateMetadataInt(_ keyPath: ReferenceWritableKeyPath<PortfolioProjectPlan, Int?>, value: Int?) {
        guard let selectedPlan else { return }
        guard selectedPlan[keyPath: keyPath] != value else { return }
        selectedPlan[keyPath: keyPath] = value
        selectedPlan.updatedAt = Date()
        modelContext.saveReportingFailures()
    }

    private func scopeMatches(_ plan: PortfolioProjectPlan) -> Bool {
        switch registryScope {
        case .all:
            return true
        case .active:
            return !plan.isArchivedValue
        case .archived:
            return plan.isArchivedValue
        }
    }

    private func normalizeArchiveFlags() {
        for plan in plans where plan.isArchived == nil {
            plan.isArchived = false
        }
        modelContext.saveReportingFailures()
    }

    private func searchMatches(_ plan: PortfolioProjectPlan) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        let textFields: [String] = [
            plan.title,
            plan.company,
            plan.manager,
            plan.portfolioWorkspace ?? "",
            plan.portfolioProgram ?? "",
            plan.portfolioSponsor ?? "",
            plan.portfolioStage ?? "",
            plan.portfolioHealth ?? "",
            plan.portfolioPriorityBand ?? "",
            plan.portfolioApprovalState ?? "",
            plan.portfolioArchiveReason ?? "",
            plan.portfolioObjective ?? ""
        ]
        let numericFields: [String] = [
            String(plan.portfolioStrategicAlignment ?? 0),
            String(plan.portfolioRiskScore ?? 0),
            String(plan.portfolioReviewCadenceDays ?? 0)
        ]
        let boardColumns = plan.boardColumns.joined(separator: " ")
        let haystack = (textFields + numericFields + [boardColumns])
            .joined(separator: " ")
            .lowercased()
        return haystack.contains(query)
    }

    private func buildGroupedVisiblePlans(from visiblePlans: [PortfolioProjectPlan]) -> [PlanGroup] {
        guard registryGrouping != .none else { return [] }

        let grouped = Dictionary(grouping: visiblePlans) { plan in
            switch registryGrouping {
            case .none:
                return ""
            case .workspace:
                return normalizedMetadata(plan.portfolioWorkspace) ?? "Unassigned Workspace"
            case .program:
                return normalizedMetadata(plan.portfolioProgram) ?? "Unassigned Program"
            case .health:
                return normalizedMetadata(plan.portfolioHealth) ?? "Health Not Set"
            case .approval:
                return normalizedMetadata(plan.portfolioApprovalState) ?? "Intake Review"
            }
        }

        return grouped
            .map { key, plans in
                PlanGroup(
                    title: key,
                    plans: plans.sorted { lhs, rhs in
                        trimmedOrFallback(lhs.title, fallback: "Untitled Plan")
                            .localizedCaseInsensitiveCompare(trimmedOrFallback(rhs.title, fallback: "Untitled Plan")) == .orderedAscending
                    }
                )
            }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private func refreshPortfolioDerivedContent() {
        // Everything the UI needs as live SwiftData objects plus the cheap
        // metadata rollups stays on the main actor.
        let visiblePlans = filteredPlans
        let groupedVisiblePlans = buildGroupedVisiblePlans(from: visiblePlans)
        let archivedCount = plans.filter(\.isArchivedValue).count
        let activeCount = plans.count - archivedCount
        let workspaceCount = Set(visiblePlans.compactMap { normalizedMetadata($0.portfolioWorkspace) }).count
        let programCount = Set(visiblePlans.compactMap { normalizedMetadata($0.portfolioProgram) }).count
        let atRiskProjectCount = visiblePlans.filter(isAtRisk).count
        let totalPortfolioBudget = visiblePlans.reduce(0) { $0 + $1.portfolioBudget }
        let totalPortfolioActualCost = visiblePlans.reduce(0) { $0 + $1.portfolioActualCost }

        // Snapshot the fields the summary builders read so the heavy
        // per-task analysis can run off the main thread.
        let planSnapshots = visiblePlans.map { $0.analyticsSnapshot() }
        let dependencySnapshots = crossProjectDependencies.map { $0.analyticsSnapshot() }

        portfolioDerivedGeneration += 1
        let generation = portfolioDerivedGeneration

        Task.detached(priority: .userInitiated) {
            let executive = PortfolioExecutiveSummary.build(snapshots: planSnapshots)
            let governance = PortfolioGovernanceSummary.build(snapshots: planSnapshots)
            let roadmap = PortfolioProgramRoadmapSummary.build(snapshots: planSnapshots)
            let dependencies = PortfolioDependencySummary.build(
                snapshots: planSnapshots,
                dependencySnapshots: dependencySnapshots
            )
            let today = Calendar.current.startOfDay(for: Date())
            func trimmedOrFallbackOffMain(_ value: String, fallback: String) -> String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? fallback : trimmed
            }
            let activeTasks = planSnapshots
                .flatMap { plan in
                    plan.tasks.map { task in
                        TaskSnapshot(
                            id: "\(plan.portfolioID.uuidString)-\(task.legacyID)",
                            planID: plan.portfolioID,
                            planTitle: trimmedOrFallbackOffMain(plan.title, fallback: "Untitled Plan"),
                            name: trimmedOrFallbackOffMain(task.name, fallback: "Untitled Task"),
                            boardStatus: task.boardStatus,
                            finishDate: max(task.startDate, task.finishDate),
                            isActive: task.isActive,
                            percentComplete: task.percentComplete
                        )
                    }
                }
                .filter { $0.isActive && $0.percentComplete < 100 }
                .sorted {
                    if $0.finishDate != $1.finishDate {
                        return $0.finishDate < $1.finishDate
                    }
                    return $0.id < $1.id
                }
            let overdueTaskCount = activeTasks.filter { Calendar.current.startOfDay(for: $0.finishDate) < today }.count

            await MainActor.run {
                guard generation == portfolioDerivedGeneration else { return }
                derivedContent = PortfolioDerivedContent(
                    visiblePlans: visiblePlans,
                    groupedVisiblePlans: groupedVisiblePlans,
                    archivedCount: archivedCount,
                    activeCount: activeCount,
                    workspaceCount: workspaceCount,
                    programCount: programCount,
                    atRiskProjectCount: atRiskProjectCount,
                    totalPortfolioBudget: totalPortfolioBudget,
                    totalPortfolioActualCost: totalPortfolioActualCost,
                    activeTasks: activeTasks,
                    overdueTaskCount: overdueTaskCount,
                    executiveSummary: executive,
                    governanceSummary: governance,
                    programRoadmapSummary: roadmap,
                    dependencySummary: dependencies,
                    executiveInsightsByPlanID: Dictionary(uniqueKeysWithValues: executive.projectInsights.map { ($0.planID, $0) }),
                    governanceInsightsByPlanID: Dictionary(uniqueKeysWithValues: governance.projectInsights.map { ($0.planID, $0) })
                )
                isPortfolioDerivedContentLoading = false
            }
        }
    }

    private func schedulePortfolioDerivedContentRefresh(delay: TimeInterval = 0.08) {
        portfolioDerivedRefreshWorkItem?.cancel()
        isPortfolioDerivedContentLoading = true
        let workItem = DispatchWorkItem {
            refreshPortfolioDerivedContent()
        }
        portfolioDerivedRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func refreshResourceCapacitySummary() {
        // Snapshot SwiftData plans into value types on the main actor, then run
        // the schedule + workload computation off the main thread so the
        // portfolio UI stays responsive.
        resourceCapacityGeneration += 1
        let generation = resourceCapacityGeneration
        let projections = PortfolioResourceCapacitySummary.projections(for: filteredPlans)

        Task.detached(priority: .userInitiated) {
            let summary = PortfolioResourceCapacitySummary.build(projections: projections)
            await MainActor.run {
                guard generation == resourceCapacityGeneration else { return }
                resourceCapacitySummary = summary
                isResourceCapacityLoading = false
            }
        }
    }

    private func scheduleResourceCapacityRefresh(delay: TimeInterval = 0.12) {
        resourceCapacityRefreshWorkItem?.cancel()
        isResourceCapacityLoading = true
        let workItem = DispatchWorkItem {
            refreshResourceCapacitySummary()
        }
        resourceCapacityRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func syncSelectedPlan() {
        if let activePortfolioID, plans.contains(where: { $0.portfolioID == activePortfolioID }) {
            selectedPlanID = activePortfolioID
            return
        }

        if let selectedPlanID, plans.contains(where: { $0.portfolioID == selectedPlanID }) {
            return
        }

        selectedPlanID = filteredPlans.first?.portfolioID ?? plans.first?.portfolioID
    }

    private func openPlanInWorkspace(_ plan: PortfolioProjectPlan) {
        activePortfolioID = plan.portfolioID
        selectedPlanID = plan.portfolioID
    }

    private func toggleArchive(for plan: PortfolioProjectPlan) {
        plan.isArchived = !(plan.isArchivedValue)
        plan.updatedAt = Date()
        modelContext.saveReportingFailures()
        if plan.isArchivedValue, activePortfolioID == plan.portfolioID {
            activePortfolioID = filteredPlans.first?.portfolioID
        }
        syncSelectedPlan()
    }

    private func deletePortfolioPlan(_ plan: PortfolioProjectPlan) {
        let deletedID = plan.portfolioID
        removeCrossProjectDependencies(for: [deletedID])
        modelContext.delete(plan)
        modelContext.saveReportingFailures()
        if activePortfolioID == deletedID {
            activePortfolioID = filteredPlans.first(where: { $0.portfolioID != deletedID })?.portfolioID
        }
        selectedPlanID = filteredPlans.first?.portfolioID
        syncDependencySelections()
    }

    private func createBlankPortfolioPlan() {
        let nativePlan = NativeProjectPlan.empty()
        do {
            try PortfolioProjectSynchronizer.upsert(nativePlan: nativePlan, in: modelContext)
            activePortfolioID = nativePlan.portfolioID
            selectedPlanID = nativePlan.portfolioID
            importStatusMessage = "Created new portfolio plan."
            syncDependencySelections()
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func importPortfolioPlans(from urls: [URL]) async {
        guard !urls.isEmpty else { return }
        await MainActor.run {
            isImporting = true
            importErrorMessage = nil
            importStatusMessage = "Importing \(urls.count) plan(s)..."
        }

        let converter = MPPConverterService()
        var importedTitles: [String] = []
        var failedNames: [String] = []

        for url in urls {
            do {
                var nativePlan = try await loadNativePlan(from: url, converter: converter)
                if normalizedMetadata(nativePlan.portfolioWorkspace) == nil {
                    nativePlan.portfolioWorkspace = "Imported Plans"
                }
                if normalizedMetadata(nativePlan.portfolioStage) == nil {
                    nativePlan.portfolioStage = "Delivery"
                }
                if normalizedMetadata(nativePlan.portfolioHealth) == nil {
                    nativePlan.portfolioHealth = "Green"
                }
                if normalizedMetadata(nativePlan.portfolioPriorityBand) == nil {
                    nativePlan.portfolioPriorityBand = "Medium"
                }
                if normalizedMetadata(nativePlan.portfolioApprovalState) == nil {
                    nativePlan.portfolioApprovalState = "Approved"
                }
                if nativePlan.portfolioStrategicAlignment == nil {
                    nativePlan.portfolioStrategicAlignment = 60
                }
                if nativePlan.portfolioRiskScore == nil {
                    switch normalizedMetadata(nativePlan.portfolioHealth)?.lowercased() {
                    case "red":
                        nativePlan.portfolioRiskScore = 80
                    case "amber":
                        nativePlan.portfolioRiskScore = 55
                    case "on hold":
                        nativePlan.portfolioRiskScore = 65
                    case "green":
                        nativePlan.portfolioRiskScore = 25
                    default:
                        nativePlan.portfolioRiskScore = 40
                    }
                }
                if nativePlan.portfolioReviewCadenceDays == nil {
                    nativePlan.portfolioReviewCadenceDays = 14
                }
                try await MainActor.run {
                    try PortfolioProjectSynchronizer.upsert(nativePlan: nativePlan, in: modelContext)
                    activePortfolioID = nativePlan.portfolioID
                    selectedPlanID = nativePlan.portfolioID
                    importedTitles.append(trimmedOrFallback(nativePlan.title, fallback: url.lastPathComponent))
                    normalizeCrossProjectDependencies()
                    syncDependencySelections()
                }
            } catch {
                failedNames.append(url.lastPathComponent)
            }
        }

        await MainActor.run {
            isImporting = false
            if !failedNames.isEmpty {
                importErrorMessage = "Some files failed to import: \(failedNames.joined(separator: ", "))"
            } else if importedTitles.isEmpty {
                importErrorMessage = "No plans were imported."
            } else {
                importStatusMessage = "Imported \(importedTitles.count) plan(s): \(importedTitles.joined(separator: ", "))"
            }
        }
    }

    private func loadNativePlan(from url: URL, converter: MPPConverterService) async throws -> NativeProjectPlan {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let extensionLower = url.pathExtension.lowercased()
        if extensionLower == "mppplan" || extensionLower == "json" || extensionLower == "nativeplan" {
            do {
                let data = try Data(contentsOf: url)
                return try NativeProjectPlan.decode(from: data)
            } catch {
                // If this file is actually an MPP file with one of these extensions,
                // fall through to converter path.
            }
        }

        let data = try await converter.convert(mppFileURL: url)
        let projectModel = try await JSONProjectParser.parseDetached(jsonData: data)
        return NativeProjectPlan(projectModel: projectModel)
    }

    private func metricCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func trimmedOrFallback(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func taskSnapshots(for plan: PortfolioProjectPlan) -> [TaskSnapshot] {
        let planTitle = trimmedOrFallback(plan.title, fallback: "Untitled Plan")
        return plan.nativeTasksForUI.map { task in
            TaskSnapshot(
                id: "\(plan.portfolioID.uuidString)-\(task.id)",
                planID: plan.portfolioID,
                planTitle: planTitle,
                name: trimmedOrFallback(task.name, fallback: "Untitled Task"),
                boardStatus: task.boardStatus,
                finishDate: task.normalizedFinishDate,
                isActive: task.isActive,
                percentComplete: task.percentComplete
            )
        }
    }

    private func syncDependencySelections() {
        if selectedPlan == nil {
            selectedDependencySourceTaskID = nil
            selectedDependencyTargetPlanID = nil
            selectedDependencyTargetTaskID = nil
            return
        }

        if !dependencySourceTaskOptions.contains(where: { $0.uniqueID == selectedDependencySourceTaskID }) {
            selectedDependencySourceTaskID = dependencySourceTaskOptions.first?.uniqueID
        }

        if !dependencyTargetPlanOptions.contains(where: { $0.portfolioID == selectedDependencyTargetPlanID }) {
            selectedDependencyTargetPlanID = dependencyTargetPlanOptions.first?.portfolioID
        }

        if !dependencyTargetTaskOptions.contains(where: { $0.uniqueID == selectedDependencyTargetTaskID }) {
            selectedDependencyTargetTaskID = dependencyTargetTaskOptions.first?.uniqueID
        }
    }

    private func createCrossProjectDependency() {
        guard let selectedPlan else { return }
        guard let sourceTaskID = selectedDependencySourceTaskID,
              let targetPlan = selectedDependencyTargetPlan,
              let targetTaskID = selectedDependencyTargetTaskID,
              let sourceTask = dependencySourceTaskOptions.first(where: { $0.uniqueID == sourceTaskID }),
              let targetTask = dependencyTargetTaskOptions.first(where: { $0.uniqueID == targetTaskID }) else {
            return
        }

        let normalizedNote = dependencyNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let duplicateDescriptor = FetchDescriptor<PortfolioCrossProjectDependency>()
        if let duplicates = try? modelContext.fetch(duplicateDescriptor),
           duplicates.contains(where: {
               $0.sourcePlanID == selectedPlan.portfolioID
                   && $0.sourceTaskUniqueID == sourceTask.uniqueID
                   && $0.targetPlanID == targetPlan.portfolioID
                   && $0.targetTaskUniqueID == targetTask.uniqueID
                   && $0.relationType == dependencyRelationType
                   && $0.lagDays == dependencyLagDays
           }) {
            importErrorMessage = "This cross-project dependency already exists."
            return
        }

        let dependency = PortfolioCrossProjectDependency(
            sourcePlan: selectedPlan,
            sourceTask: sourceTask,
            targetPlan: targetPlan,
            targetTask: targetTask,
            relationType: dependencyRelationType,
            lagDays: dependencyLagDays,
            note: normalizedNote
        )
        modelContext.insert(dependency)
        modelContext.saveReportingFailures()
        dependencyNote = ""
        importStatusMessage = "Added dependency \(sourceTask.name) -> \(targetTask.name)."
    }

    private func deleteCrossProjectDependency(id: UUID) {
        guard let dependency = crossProjectDependencies.first(where: { $0.uniqueID == id }) else { return }
        modelContext.delete(dependency)
        modelContext.saveReportingFailures()
    }

    private func removeCrossProjectDependencies(for planIDs: [UUID]) {
        let identifiers = Set(planIDs)
        guard !identifiers.isEmpty else { return }
        for dependency in crossProjectDependencies where identifiers.contains(dependency.sourcePlanID) || identifiers.contains(dependency.targetPlanID) {
            modelContext.delete(dependency)
        }
        modelContext.saveReportingFailures()
    }

    private func normalizeCrossProjectDependencies() {
        let planByID = Dictionary(nonThrowingUniquePairs: plans.map { ($0.portfolioID, $0) })
        let taskByPlanAndID: [UUID: [UUID: PortfolioPlanTask]] = Dictionary(
            uniqueKeysWithValues: plans.map { plan in
                (plan.portfolioID, Dictionary(uniqueKeysWithValues: plan.tasks.map { ($0.uniqueID, $0) }))
            }
        )

        var didChange = false
        for dependency in crossProjectDependencies {
            guard let sourcePlan = planByID[dependency.sourcePlanID],
                  let targetPlan = planByID[dependency.targetPlanID],
                  let sourceTask = taskByPlanAndID[dependency.sourcePlanID]?[dependency.sourceTaskUniqueID],
                  let targetTask = taskByPlanAndID[dependency.targetPlanID]?[dependency.targetTaskUniqueID] else {
                modelContext.delete(dependency)
                didChange = true
                continue
            }

            if dependency.refresh(
                sourcePlan: sourcePlan,
                sourceTask: sourceTask,
                targetPlan: targetPlan,
                targetTask: targetTask
            ) {
                didChange = true
            }
        }

        if didChange {
            modelContext.saveReportingFailures()
        }
    }
}
