import XCTest
import SwiftData
@testable import MPPViewer

final class PerformanceHelpersTests: XCTestCase {
    @MainActor
    func testPortfolioProjectSynchronizerPersistsSamplePlan() throws {
        let nativePlan = try loadSampleNativePlan()
        let container = try makeInMemoryPortfolioContainer()
        let context = ModelContext(container)

        let persistedPlan = try PortfolioProjectSynchronizer.upsert(nativePlan: nativePlan, in: context)
        let storedPlans = try context.fetch(FetchDescriptor<PortfolioProjectPlan>())

        XCTAssertEqual(storedPlans.count, 1)
        XCTAssertEqual(persistedPlan.portfolioID, nativePlan.portfolioID)
        XCTAssertEqual(persistedPlan.tasks.count, nativePlan.tasks.count)
        XCTAssertEqual(persistedPlan.resources.count, nativePlan.resources.count)
        XCTAssertEqual(persistedPlan.calendars.count, nativePlan.calendars.count)
        XCTAssertEqual(persistedPlan.sprints.count, nativePlan.sprints.count)
        XCTAssertEqual(persistedPlan.statusSnapshots.count, nativePlan.statusSnapshots.count)
        XCTAssertEqual(persistedPlan.workflowColumns.count, nativePlan.workflowColumns.count)
        XCTAssertEqual(persistedPlan.isArchived, false)
        XCTAssertTrue(persistedPlan.resources.allSatisfy { $0.accrueAt == $0.accrueAtValue })
    }

    @MainActor
    func testPortfolioProjectSynchronizerPersistsPortfolioMetadata() throws {
        var nativePlan = NativeProjectPlan.empty()
        nativePlan.title = "Portfolio Metadata"
        nativePlan.portfolioWorkspace = "PMO Workspace"
        nativePlan.portfolioProgram = "Modernization"
        nativePlan.portfolioSponsor = "Executive Sponsor"
        nativePlan.portfolioStage = "Delivery"
        nativePlan.portfolioHealth = "Amber"
        nativePlan.portfolioPriorityBand = "High"
        nativePlan.portfolioApprovalState = "Approved"
        nativePlan.portfolioStrategicAlignment = 80
        nativePlan.portfolioRiskScore = 35
        nativePlan.portfolioObjective = "Reduce schedule risk"
        nativePlan.portfolioReviewDate = Date(timeIntervalSince1970: 1_750_000_000)
        nativePlan.portfolioReviewCadenceDays = 30
        nativePlan.portfolioArchiveReason = "Funding review"

        let container = try makeInMemoryPortfolioContainer()
        let context = ModelContext(container)

        let persistedPlan = try PortfolioProjectSynchronizer.upsert(nativePlan: nativePlan, in: context)
        let projection = persistedPlan.asNativePlan()

        XCTAssertEqual(persistedPlan.portfolioWorkspace, "PMO Workspace")
        XCTAssertEqual(persistedPlan.portfolioProgram, "Modernization")
        XCTAssertEqual(persistedPlan.portfolioSponsor, "Executive Sponsor")
        XCTAssertEqual(persistedPlan.portfolioStage, "Delivery")
        XCTAssertEqual(persistedPlan.portfolioHealth, "Amber")
        XCTAssertEqual(persistedPlan.portfolioPriorityBand, "High")
        XCTAssertEqual(persistedPlan.portfolioApprovalState, "Approved")
        XCTAssertEqual(persistedPlan.portfolioStrategicAlignment, 80)
        XCTAssertEqual(persistedPlan.portfolioRiskScore, 35)
        XCTAssertEqual(persistedPlan.portfolioObjective, "Reduce schedule risk")
        XCTAssertEqual(persistedPlan.portfolioReviewDate, nativePlan.portfolioReviewDate)
        XCTAssertEqual(persistedPlan.portfolioReviewCadenceDays, 30)
        XCTAssertEqual(persistedPlan.portfolioArchiveReason, "Funding review")
        XCTAssertEqual(projection.portfolioWorkspace, nativePlan.portfolioWorkspace)
        XCTAssertEqual(projection.portfolioProgram, nativePlan.portfolioProgram)
        XCTAssertEqual(projection.portfolioSponsor, nativePlan.portfolioSponsor)
        XCTAssertEqual(projection.portfolioStage, nativePlan.portfolioStage)
        XCTAssertEqual(projection.portfolioHealth, nativePlan.portfolioHealth)
        XCTAssertEqual(projection.portfolioPriorityBand, nativePlan.portfolioPriorityBand)
        XCTAssertEqual(projection.portfolioApprovalState, nativePlan.portfolioApprovalState)
        XCTAssertEqual(projection.portfolioStrategicAlignment, nativePlan.portfolioStrategicAlignment)
        XCTAssertEqual(projection.portfolioRiskScore, nativePlan.portfolioRiskScore)
        XCTAssertEqual(projection.portfolioObjective, nativePlan.portfolioObjective)
        XCTAssertEqual(projection.portfolioReviewDate, nativePlan.portfolioReviewDate)
        XCTAssertEqual(projection.portfolioReviewCadenceDays, nativePlan.portfolioReviewCadenceDays)
        XCTAssertEqual(projection.portfolioArchiveReason, nativePlan.portfolioArchiveReason)
    }

    func testNativeProjectPlanMetadataRoundTripsThroughEncoding() throws {
        var nativePlan = NativeProjectPlan.empty()
        nativePlan.portfolioWorkspace = "Shared Services"
        nativePlan.portfolioProgram = "ERP"
        nativePlan.portfolioSponsor = "CFO"
        nativePlan.portfolioStage = "Approved"
        nativePlan.portfolioHealth = "Green"
        nativePlan.portfolioPriorityBand = "Critical"
        nativePlan.portfolioApprovalState = "Approved"
        nativePlan.portfolioStrategicAlignment = 90
        nativePlan.portfolioRiskScore = 20
        nativePlan.portfolioObjective = "Consolidate finance systems"
        nativePlan.portfolioReviewDate = Date(timeIntervalSince1970: 1_760_000_000)
        nativePlan.portfolioReviewCadenceDays = 14
        nativePlan.portfolioArchiveReason = "Merged into strategic portfolio"

        let data = try nativePlan.encodedData()
        let decoded = try NativeProjectPlan.decode(from: data)

        XCTAssertEqual(decoded.portfolioWorkspace, nativePlan.portfolioWorkspace)
        XCTAssertEqual(decoded.portfolioProgram, nativePlan.portfolioProgram)
        XCTAssertEqual(decoded.portfolioSponsor, nativePlan.portfolioSponsor)
        XCTAssertEqual(decoded.portfolioStage, nativePlan.portfolioStage)
        XCTAssertEqual(decoded.portfolioHealth, nativePlan.portfolioHealth)
        XCTAssertEqual(decoded.portfolioPriorityBand, nativePlan.portfolioPriorityBand)
        XCTAssertEqual(decoded.portfolioApprovalState, nativePlan.portfolioApprovalState)
        XCTAssertEqual(decoded.portfolioStrategicAlignment, nativePlan.portfolioStrategicAlignment)
        XCTAssertEqual(decoded.portfolioRiskScore, nativePlan.portfolioRiskScore)
        XCTAssertEqual(decoded.portfolioObjective, nativePlan.portfolioObjective)
        XCTAssertEqual(decoded.portfolioReviewDate, nativePlan.portfolioReviewDate)
        XCTAssertEqual(decoded.portfolioReviewCadenceDays, nativePlan.portfolioReviewCadenceDays)
        XCTAssertEqual(decoded.portfolioArchiveReason, nativePlan.portfolioArchiveReason)
    }

    @MainActor
    func testPortfolioExecutiveSummaryRanksRiskAndMilestones() throws {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))

        var riskyPlan = NativeProjectPlan.empty()
        riskyPlan.title = "Risky Program"
        riskyPlan.portfolioWorkspace = "PMO"
        riskyPlan.portfolioProgram = "Transformation"
        riskyPlan.portfolioHealth = "Red"
        riskyPlan.portfolioReviewDate = calendar.date(byAdding: .day, value: -1, to: now)

        var riskyMilestone = riskyPlan.makeTask(name: "Cutover", anchoredTo: now)
        riskyMilestone.isMilestone = true
        riskyMilestone.finishDate = calendar.date(byAdding: .day, value: 10, to: now) ?? now
        riskyMilestone.baselineFinishDate = calendar.date(byAdding: .day, value: 4, to: now)
        riskyMilestone.baselineCost = 100
        riskyMilestone.actualCost = 145
        riskyMilestone.percentComplete = 30

        var riskyTask = riskyPlan.makeTask(name: "Late Work", anchoredTo: now)
        riskyTask.id = 2
        riskyTask.finishDate = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        riskyTask.baselineFinishDate = calendar.date(byAdding: .day, value: -5, to: now)
        riskyTask.baselineCost = 80
        riskyTask.actualCost = 120
        riskyTask.percentComplete = 40

        riskyPlan.tasks = [riskyMilestone, riskyTask]

        var healthyPlan = NativeProjectPlan.empty()
        healthyPlan.title = "Healthy Program"
        healthyPlan.portfolioWorkspace = "Delivery"
        healthyPlan.portfolioProgram = "Launch"
        healthyPlan.portfolioHealth = "Green"
        healthyPlan.portfolioReviewDate = calendar.date(byAdding: .day, value: 20, to: now)

        var healthyMilestone = healthyPlan.makeTask(name: "Go Live", anchoredTo: now)
        healthyMilestone.isMilestone = true
        healthyMilestone.finishDate = calendar.date(byAdding: .day, value: 8, to: now) ?? now
        healthyMilestone.baselineFinishDate = healthyMilestone.finishDate
        healthyMilestone.baselineCost = 75
        healthyMilestone.actualCost = 10

        var healthyTask = healthyPlan.makeTask(name: "Execution", anchoredTo: now)
        healthyTask.id = 2
        healthyTask.finishDate = calendar.date(byAdding: .day, value: 15, to: now) ?? now
        healthyTask.baselineFinishDate = healthyTask.finishDate
        healthyTask.baselineCost = 120
        healthyTask.actualCost = 45
        healthyTask.percentComplete = 55

        healthyPlan.tasks = [healthyMilestone, healthyTask]

        let container = try makeInMemoryPortfolioContainer()
        let context = ModelContext(container)
        _ = try PortfolioProjectSynchronizer.upsert(nativePlan: riskyPlan, in: context)
        _ = try PortfolioProjectSynchronizer.upsert(nativePlan: healthyPlan, in: context)

        let storedPlans = try context.fetch(FetchDescriptor<PortfolioProjectPlan>())
        let summary = PortfolioExecutiveSummary.build(plans: storedPlans, now: now)

        XCTAssertEqual(summary.atRiskCount, 1)
        XCTAssertEqual(summary.healthyCount, 1)
        XCTAssertEqual(summary.slippedMilestoneCount, 1)
        XCTAssertEqual(summary.upcomingMilestoneCount, 2)
        XCTAssertEqual(summary.rankedProjects.first?.title, "Risky Program")
        XCTAssertEqual(summary.slippedMilestones.first?.planTitle, "Risky Program")
        XCTAssertTrue(summary.attentionFeed.contains(where: { $0.planTitle == "Risky Program" }))
    }

    @MainActor
    func testPortfolioResourceCapacitySummaryMergesSharedResourcesAndDetectsConflict() throws {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))

        var planA = NativeProjectPlan.empty()
        planA.title = "Project A"
        var resourceA = planA.makeResource(name: "Alex Morgan")
        resourceA.emailAddress = "alex@example.com"
        resourceA.maxUnits = 100
        planA.resources = [resourceA]

        var taskA = planA.makeTask(name: "Execution A", anchoredTo: now)
        taskA.finishDate = calendar.date(byAdding: .day, value: 5, to: now) ?? now
        planA.tasks = [taskA]

        var assignmentA = planA.makeAssignment(taskID: taskA.id, resourceID: resourceA.id)
        assignmentA.workSeconds = 40 * 3600
        planA.assignments = [assignmentA]

        var planB = NativeProjectPlan.empty()
        planB.title = "Project B"
        var resourceB = planB.makeResource(name: "Alex Morgan")
        resourceB.emailAddress = "alex@example.com"
        resourceB.maxUnits = 100
        planB.resources = [resourceB]

        var taskB = planB.makeTask(name: "Execution B", anchoredTo: now)
        taskB.finishDate = calendar.date(byAdding: .day, value: 5, to: now) ?? now
        planB.tasks = [taskB]

        var assignmentB = planB.makeAssignment(taskID: taskB.id, resourceID: resourceB.id)
        assignmentB.workSeconds = 40 * 3600
        planB.assignments = [assignmentB]

        let container = try makeInMemoryPortfolioContainer()
        let context = ModelContext(container)
        _ = try PortfolioProjectSynchronizer.upsert(nativePlan: planA, in: context)
        _ = try PortfolioProjectSynchronizer.upsert(nativePlan: planB, in: context)

        let storedPlans = try context.fetch(FetchDescriptor<PortfolioProjectPlan>())
        let summary = PortfolioResourceCapacitySummary.build(plans: storedPlans, now: now)

        XCTAssertEqual(summary.uniqueResourceCount, 1)
        XCTAssertEqual(summary.sharedResourceCount, 1)
        XCTAssertEqual(summary.overloadedResourceCount, 1)
        XCTAssertGreaterThan(summary.overloadedWeekCount, 0)
        XCTAssertGreaterThan(summary.doubleBookedWeekCount, 0)
        XCTAssertEqual(summary.resources.first?.displayName, "Alex Morgan")
        XCTAssertEqual(summary.resources.first?.projectCount, 2)
        XCTAssertTrue(summary.alerts.contains(where: { $0.resourceName == "Alex Morgan" }))
    }

    @MainActor
    func testPortfolioGovernanceSummaryTracksApprovalAndRanking() throws {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))

        var approvedPlan = NativeProjectPlan.empty()
        approvedPlan.title = "Approved Delivery"
        approvedPlan.portfolioApprovalState = "Approved"
        approvedPlan.portfolioStage = "Delivery"
        approvedPlan.portfolioStrategicAlignment = 85
        approvedPlan.portfolioRiskScore = 20
        approvedPlan.portfolioReviewDate = calendar.date(byAdding: .day, value: -3, to: now)
        approvedPlan.portfolioReviewCadenceDays = 14

        var intakePlan = NativeProjectPlan.empty()
        intakePlan.title = "Intake Initiative"
        intakePlan.portfolioApprovalState = "Proposed"
        intakePlan.portfolioStage = "Planning"
        intakePlan.portfolioStrategicAlignment = 70
        intakePlan.portfolioRiskScore = 35
        intakePlan.portfolioReviewDate = now
        intakePlan.portfolioReviewCadenceDays = 30

        var pausedPlan = NativeProjectPlan.empty()
        pausedPlan.title = "Paused Program"
        pausedPlan.portfolioApprovalState = "On Hold"
        pausedPlan.portfolioStage = "On Hold"
        pausedPlan.portfolioStrategicAlignment = 60
        pausedPlan.portfolioRiskScore = 75
        pausedPlan.portfolioReviewDate = calendar.date(byAdding: .day, value: -30, to: now)
        pausedPlan.portfolioReviewCadenceDays = 7
        pausedPlan.portfolioArchiveReason = "Awaiting steering committee decision"

        let container = try makeInMemoryPortfolioContainer()
        let context = ModelContext(container)
        _ = try PortfolioProjectSynchronizer.upsert(nativePlan: approvedPlan, in: context)
        _ = try PortfolioProjectSynchronizer.upsert(nativePlan: intakePlan, in: context)
        _ = try PortfolioProjectSynchronizer.upsert(nativePlan: pausedPlan, in: context)

        let storedPlans = try context.fetch(FetchDescriptor<PortfolioProjectPlan>())
        let summary = PortfolioGovernanceSummary.build(plans: storedPlans, now: now)

        XCTAssertEqual(summary.approvedCount, 1)
        XCTAssertEqual(summary.intakeCount, 1)
        XCTAssertEqual(summary.onHoldCount, 1)
        XCTAssertEqual(summary.cancelledCount, 0)
        XCTAssertEqual(summary.reviewDueCount, 2)
        XCTAssertEqual(summary.rankedProjects.first?.title, "Approved Delivery")
        XCTAssertEqual(summary.rankedProjects.last?.title, "Paused Program")
        XCTAssertEqual(summary.projectInsights.first(where: { $0.title == "Paused Program" })?.archiveReason, "Awaiting steering committee decision")
    }

    @MainActor
    func testPortfolioProgramRoadmapSummaryGroupsProgramsAndTimeline() throws {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))

        var planA = NativeProjectPlan.empty()
        planA.title = "Commerce Stream"
        planA.portfolioProgram = "Core Modernization"
        planA.portfolioWorkspace = "PMO"
        planA.portfolioReviewDate = calendar.date(byAdding: .day, value: -20, to: now)
        planA.portfolioReviewCadenceDays = 14
        var milestoneA = planA.makeTask(name: "Pilot Launch", anchoredTo: now)
        milestoneA.isMilestone = true
        milestoneA.finishDate = calendar.date(byAdding: .day, value: 12, to: now) ?? now
        milestoneA.baselineFinishDate = milestoneA.finishDate
        planA.tasks = [milestoneA]

        var planB = NativeProjectPlan.empty()
        planB.title = "ERP Stream"
        planB.portfolioProgram = "Core Modernization"
        planB.portfolioWorkspace = "PMO"
        var milestoneB = planB.makeTask(name: "Finance Cutover", anchoredTo: now)
        milestoneB.isMilestone = true
        milestoneB.finishDate = calendar.date(byAdding: .day, value: 18, to: now) ?? now
        milestoneB.baselineFinishDate = calendar.date(byAdding: .day, value: 14, to: now)
        planB.tasks = [milestoneB]

        var planC = NativeProjectPlan.empty()
        planC.title = "Analytics Stream"
        planC.portfolioProgram = "Data Foundation"
        planC.portfolioWorkspace = "Delivery"
        var milestoneC = planC.makeTask(name: "Data Migration", anchoredTo: now)
        milestoneC.isMilestone = true
        milestoneC.finishDate = calendar.date(byAdding: .day, value: 25, to: now) ?? now
        milestoneC.baselineFinishDate = milestoneC.finishDate
        planC.tasks = [milestoneC]

        let container = try makeInMemoryPortfolioContainer()
        let context = ModelContext(container)
        _ = try PortfolioProjectSynchronizer.upsert(nativePlan: planA, in: context)
        _ = try PortfolioProjectSynchronizer.upsert(nativePlan: planB, in: context)
        _ = try PortfolioProjectSynchronizer.upsert(nativePlan: planC, in: context)

        let storedPlans = try context.fetch(FetchDescriptor<PortfolioProjectPlan>())
        let summary = PortfolioProgramRoadmapSummary.build(plans: storedPlans, now: now)

        XCTAssertEqual(summary.programs.count, 2)
        XCTAssertEqual(summary.slippedMilestoneCount, 1)
        XCTAssertEqual(summary.overdueReviewCount, 1)
        let modernization = try XCTUnwrap(summary.programs.first(where: { $0.program == "Core Modernization" }))
        XCTAssertEqual(modernization.projectCount, 2)
        XCTAssertEqual(modernization.slippedMilestoneCount, 1)
        XCTAssertEqual(modernization.reviewDueCount, 1)
        XCTAssertTrue(modernization.timelineEvents.contains(where: { $0.kind == "Review" }))
        XCTAssertTrue(modernization.timelineEvents.contains(where: { $0.title == "Finance Cutover" }))
    }

    @MainActor
    func testPortfolioDependencySummaryFlagsCrossProjectBlockers() throws {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))

        var sourcePlan = NativeProjectPlan.empty()
        sourcePlan.title = "Source Delivery"
        sourcePlan.portfolioProgram = "Program A"
        var sourceTask = sourcePlan.makeTask(name: "Complete Integration", anchoredTo: now)
        sourceTask.finishDate = calendar.date(byAdding: .day, value: 5, to: now) ?? now
        sourceTask.percentComplete = 45
        sourcePlan.tasks = [sourceTask]

        var targetPlan = NativeProjectPlan.empty()
        targetPlan.title = "Target Rollout"
        targetPlan.portfolioProgram = "Program B"
        var targetTask = targetPlan.makeTask(name: "Start Rollout", anchoredTo: now)
        targetTask.startDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        targetTask.finishDate = calendar.date(byAdding: .day, value: 3, to: now) ?? now
        targetPlan.tasks = [targetTask]

        let container = try makeInMemoryPortfolioContainer()
        let context = ModelContext(container)
        let storedSource = try PortfolioProjectSynchronizer.upsert(nativePlan: sourcePlan, in: context)
        let storedTarget = try PortfolioProjectSynchronizer.upsert(nativePlan: targetPlan, in: context)

        let dependency = PortfolioCrossProjectDependency(
            sourcePlan: storedSource,
            sourceTask: storedSource.tasks[0],
            targetPlan: storedTarget,
            targetTask: storedTarget.tasks[0],
            relationType: "FS",
            lagDays: 0,
            note: "Rollout waits for integration"
        )
        context.insert(dependency)
        try context.save()

        let storedPlans = try context.fetch(FetchDescriptor<PortfolioProjectPlan>())
        let storedDependencies = try context.fetch(FetchDescriptor<PortfolioCrossProjectDependency>())
        let summary = PortfolioDependencySummary.build(plans: storedPlans, dependencies: storedDependencies, now: now)

        XCTAssertEqual(summary.dependencies.count, 1)
        XCTAssertEqual(summary.blockedCount, 1)
        XCTAssertEqual(summary.highSeverityCount, 1)
        XCTAssertEqual(summary.crossProgramCount, 1)
        XCTAssertEqual(summary.dueSoonCount, 1)
        XCTAssertEqual(summary.dependencies.first?.severity, "High")
        XCTAssertEqual(summary.dependencies.first?.relationType, "FS")
        XCTAssertTrue(summary.dependencies.first?.blockerReason.contains("opened") == true)
        XCTAssertEqual(summary.dependencies.first?.note, "Rollout waits for integration")
    }

    @MainActor
    func testPortfolioReviewPresetAndSnapshotPersistAndDecode() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        var plan = NativeProjectPlan.empty()
        plan.title = "Portfolio Review Plan"
        plan.portfolioProgram = "Modernization"
        plan.portfolioWorkspace = "PMO"

        let container = try makeInMemoryPortfolioContainer()
        let context = ModelContext(container)
        let storedPlan = try PortfolioProjectSynchronizer.upsert(nativePlan: plan, in: context)

        let settings = PortfolioReviewViewSettings(
            registryScope: "Active",
            healthScope: "All Health",
            approvalScope: "All Decisions",
            grouping: "Program",
            searchText: "modernization",
            cadenceDays: 14
        )
        let preset = PortfolioReviewPreset(name: "Weekly PMO Review", viewSettings: settings)
        context.insert(preset)

        let executive = PortfolioExecutiveSummary.build(plans: [storedPlan], now: now)
        let governance = PortfolioGovernanceSummary.build(plans: [storedPlan], now: now)
        let roadmap = PortfolioProgramRoadmapSummary.build(plans: [storedPlan], now: now)
        let dependencies = PortfolioDependencySummary.build(plans: [storedPlan], dependencies: [], now: now)
        let capacity = PortfolioResourceCapacitySummary.build(plans: [storedPlan], now: now)
        let payload = PortfolioReviewSnapshotPayload.build(
            title: "Weekly Review",
            presetName: preset.name,
            viewSettings: settings,
            plans: [storedPlan],
            executive: executive,
            governance: governance,
            roadmap: roadmap,
            dependencies: dependencies,
            capacity: capacity,
            overdueTaskCount: 0,
            now: now
        )

        let snapshot = PortfolioReviewSnapshot(title: "Weekly Review", preset: preset, payload: payload)
        context.insert(snapshot)
        try context.save()

        let storedPresets = try context.fetch(FetchDescriptor<PortfolioReviewPreset>())
        let storedSnapshots = try context.fetch(FetchDescriptor<PortfolioReviewSnapshot>())

        XCTAssertEqual(storedPresets.count, 1)
        XCTAssertEqual(storedSnapshots.count, 1)
        XCTAssertEqual(storedPresets.first?.name, "Weekly PMO Review")
        XCTAssertEqual(storedPresets.first?.viewSettings.searchText, "modernization")
        XCTAssertEqual(storedSnapshots.first?.presetID, preset.uniqueID)
        XCTAssertEqual(storedSnapshots.first?.payload.title, "Weekly Review")
        XCTAssertEqual(storedSnapshots.first?.payload.visibleProjectCount, 1)
        XCTAssertEqual(storedSnapshots.first?.payload.programItems.first?.program, "Modernization")
    }

    func testPortfolioReviewDeltaReportsMetricAndAttentionChanges() {
        let settings = PortfolioReviewViewSettings(
            registryScope: "Active",
            healthScope: "All Health",
            approvalScope: "All Decisions",
            grouping: "Program",
            searchText: "",
            cadenceDays: 14
        )

        let baseline = PortfolioReviewSnapshotPayload(
            title: "Baseline Review",
            presetName: "Weekly PMO Review",
            capturedAt: Date(timeIntervalSince1970: 1_760_000_000),
            viewSettings: settings,
            visibleProjectCount: 3,
            activeProjectCount: 3,
            archivedProjectCount: 0,
            workspaceCount: 1,
            programCount: 2,
            atRiskProjectCount: 1,
            approvedCount: 2,
            intakeCount: 1,
            onHoldCount: 0,
            reviewDueCount: 1,
            overdueTaskCount: 2,
            blockedDependencyCount: 1,
            highDependencyCount: 1,
            crossProgramDependencyCount: 1,
            slippedMilestoneCount: 1,
            roadmapProgramCount: 2,
            overloadedResourceCount: 1,
            budgetTotal: 1000,
            actualCostTotal: 800,
            projectSummaries: [],
            attentionItems: [
                .init(id: "a", severity: "High", headline: "Budget variance needs review", planTitle: "Project A", detail: "Overrun detected")
            ],
            programItems: [],
            dependencyItems: [
                .init(id: "d1", severity: "High", sourcePlanTitle: "Project A", sourceTaskName: "Finish Build", targetPlanTitle: "Project B", targetTaskName: "Start Deployment", relationType: "FS", lagDays: 0, blockerReason: "Successor opened early", targetDate: Date(timeIntervalSince1970: 1_760_086_400))
            ]
        )

        let current = PortfolioReviewSnapshotPayload(
            title: "Current Review",
            presetName: "Weekly PMO Review",
            capturedAt: Date(timeIntervalSince1970: 1_760_172_800),
            viewSettings: settings,
            visibleProjectCount: 4,
            activeProjectCount: 4,
            archivedProjectCount: 0,
            workspaceCount: 1,
            programCount: 2,
            atRiskProjectCount: 2,
            approvedCount: 2,
            intakeCount: 1,
            onHoldCount: 1,
            reviewDueCount: 2,
            overdueTaskCount: 3,
            blockedDependencyCount: 2,
            highDependencyCount: 2,
            crossProgramDependencyCount: 1,
            slippedMilestoneCount: 2,
            roadmapProgramCount: 2,
            overloadedResourceCount: 2,
            budgetTotal: 1200,
            actualCostTotal: 950,
            projectSummaries: [],
            attentionItems: [
                .init(id: "a2", severity: "High", headline: "Budget variance needs review", planTitle: "Project A", detail: "Overrun detected"),
                .init(id: "a3", severity: "Medium", headline: "Milestone slippage detected", planTitle: "Project C", detail: "Checkpoint moved")
            ],
            programItems: [],
            dependencyItems: [
                .init(id: "d1", severity: "High", sourcePlanTitle: "Project A", sourceTaskName: "Finish Build", targetPlanTitle: "Project B", targetTaskName: "Start Deployment", relationType: "FS", lagDays: 0, blockerReason: "Successor opened early", targetDate: Date(timeIntervalSince1970: 1_760_086_400)),
                .init(id: "d2", severity: "Medium", sourcePlanTitle: "Project C", sourceTaskName: "Approve Design", targetPlanTitle: "Project D", targetTaskName: "Start Delivery", relationType: "FS", lagDays: 2, blockerReason: "Dependency window compressed", targetDate: Date(timeIntervalSince1970: 1_760_259_200))
            ]
        )

        let delta = PortfolioReviewDelta.build(current: current, baseline: baseline)

        XCTAssertEqual(delta.visibleProjectDelta, 1)
        XCTAssertEqual(delta.atRiskProjectDelta, 1)
        XCTAssertEqual(delta.blockedDependencyDelta, 1)
        XCTAssertEqual(delta.highDependencyDelta, 1)
        XCTAssertEqual(delta.reviewDueDelta, 1)
        XCTAssertEqual(delta.slippedMilestoneDelta, 1)
        XCTAssertEqual(delta.overloadedResourceDelta, 1)
        XCTAssertEqual(delta.overdueTaskDelta, 1)
        XCTAssertEqual(delta.budgetDelta, 200)
        XCTAssertEqual(delta.actualCostDelta, 150)
        XCTAssertEqual(delta.newAttentionHeadlines, ["Project C|Milestone slippage detected"])
        XCTAssertEqual(delta.resolvedAttentionHeadlines, [])
        XCTAssertEqual(delta.newBlockedDependencies, ["Project C: Approve Design -> Project D: Start Delivery"])
    }

    @MainActor
    func testPortfolioProjectSynchronizerNormalizesDuplicateWorkflowColumnIDsAcrossOverrides() throws {
        var nativePlan = NativeProjectPlan.empty()
        nativePlan.typeWorkflowOverrides = [
            NativeBoardTypeWorkflow(
                id: UUID(),
                itemType: "Story",
                columns: nativePlan.workflowColumns
            )
        ]

        let container = try makeInMemoryPortfolioContainer()
        let context = ModelContext(container)
        let persistedPlan = try PortfolioProjectSynchronizer.upsert(nativePlan: nativePlan, in: context)

        let sharedIDs = Set(persistedPlan.workflowColumns.map(\.uniqueID))
        let overrideIDs = Set(
            persistedPlan.typeWorkflowOverrides
                .flatMap { $0.columns.map(\.uniqueID) }
        )

        XCTAssertEqual(persistedPlan.typeWorkflowOverrides.count, 1)
        XCTAssertEqual(sharedIDs.count, persistedPlan.workflowColumns.count)
        XCTAssertEqual(overrideIDs.count, persistedPlan.typeWorkflowOverrides.first?.columns.count ?? 0)
        XCTAssertTrue(sharedIDs.isDisjoint(with: overrideIDs))
    }

    @MainActor
    func testPortfolioProjectSynchronizerStoresMultiplePlans() throws {
        let samplePlan = try loadSampleNativePlan()
        var secondaryPlan = try loadSecondaryNativePlan()
        if secondaryPlan.portfolioID == samplePlan.portfolioID {
            secondaryPlan.portfolioID = UUID()
        }

        let container = try makeInMemoryPortfolioContainer()
        let context = ModelContext(container)

        _ = try PortfolioProjectSynchronizer.upsert(nativePlan: samplePlan, in: context)
        _ = try PortfolioProjectSynchronizer.upsert(nativePlan: secondaryPlan, in: context)

        let storedPlans = try context.fetch(FetchDescriptor<PortfolioProjectPlan>())
        XCTAssertEqual(storedPlans.count, 2)
        XCTAssertEqual(Set(storedPlans.map(\.portfolioID)).count, 2)
    }

    @MainActor
    func testLocalMPPImportSmokePersistsIntoPortfolioWhenFixtureAvailable() async throws {
        guard let mppURL = localMPPFixtureURL() else {
            throw XCTSkip("No local .mpp fixture available in Downloads.")
        }

        let converter = MPPConverterService()
        let jsonData = try await converter.convert(mppFileURL: mppURL)
        let project = try await JSONProjectParser.parseDetached(jsonData: jsonData)
        let nativePlan = NativeProjectPlan(projectModel: project)
        let container = try makeInMemoryPortfolioContainer()
        let context = ModelContext(container)

        let persistedPlan = try PortfolioProjectSynchronizer.upsert(nativePlan: nativePlan, in: context)

        XCTAssertFalse(persistedPlan.title.isEmpty)
        XCTAssertFalse(persistedPlan.tasks.isEmpty)
    }

    func testDownloadedAuroraPlanDecodesWhenFixtureAvailable() throws {
        let downloadsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("aurora-commerce-launch.mppplan")

        guard FileManager.default.fileExists(atPath: downloadsURL.path) else {
            throw XCTSkip("No downloaded aurora-commerce-launch.mppplan fixture available.")
        }

        let data = try Data(contentsOf: downloadsURL)
        let nativePlan = try NativeProjectPlan.decode(from: data)

        XCTAssertFalse(nativePlan.title.isEmpty)
        XCTAssertFalse(nativePlan.tasks.isEmpty)
        XCTAssertFalse(nativePlan.resources.isEmpty)
    }

    func testCurrencyFormattingUsesRequestedSymbol() {
        let formatted = CurrencyFormatting.string(
            from: 1234,
            currencyCode: "USD",
            currencySymbol: "$",
            maximumFractionDigits: 0,
            minimumFractionDigits: 0
        )

        XCTAssertFalse(formatted.isEmpty)
        XCTAssertTrue(formatted.contains("$"))
    }

    func testStatusCenterDerivedContentBuildsAttentionFilter() {
        var plan = NativeProjectPlan.empty()
        let calendar = Calendar.current
        let statusDate = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        plan.statusDate = statusDate

        var overdue = plan.makeTask(name: "Overdue Task", anchoredTo: statusDate)
        overdue.startDate = calendar.date(byAdding: .day, value: -10, to: statusDate) ?? statusDate
        overdue.finishDate = calendar.date(byAdding: .day, value: -3, to: statusDate) ?? statusDate
        overdue.manuallyScheduled = true
        overdue.percentComplete = 0

        var active = plan.makeTask(name: "Active Task", anchoredTo: statusDate)
        active.id = overdue.id + 1
        active.startDate = calendar.date(byAdding: .day, value: -2, to: statusDate) ?? statusDate
        active.finishDate = calendar.date(byAdding: .day, value: 5, to: statusDate) ?? statusDate
        active.manuallyScheduled = true
        active.percentComplete = 45
        active.baselineCost = 100
        active.actualCost = 150

        plan.tasks = [overdue, active]
        plan.reschedule()

        let project = plan.asProjectModel()
        let derived = StatusCenterDerivedContent.build(
            project: project,
            assignments: plan.assignments,
            resources: plan.resources,
            statusDate: plan.statusDate,
            snapshots: plan.statusSnapshots,
            filter: .attention,
            searchText: ""
        )

        XCTAssertEqual(derived.workTasks.count, 2)
        XCTAssertEqual(derived.overdueCount, 1)
        XCTAssertEqual(derived.missingActualCount, 0)
        XCTAssertTrue(derived.filteredTasks.contains { $0.uniqueID == overdue.id })
        XCTAssertTrue(derived.filteredTasks.contains { $0.uniqueID == active.id })
    }

    func testAgileBoardDerivedContentBuildsLaneGroupingAndSprintLookup() {
        var plan = NativeProjectPlan.empty()
        let sprint = plan.makeSprint(name: "Sprint 1")
        plan.sprints = [sprint]

        var story = plan.makeTask(name: "Story A")
        story.boardStatus = "Ready"
        story.storyPoints = 3
        story.sprintID = sprint.id

        var bug = plan.makeTask(name: "Bug B")
        bug.id = story.id + 1
        bug.boardStatus = "Done"
        bug.storyPoints = 2
        bug.percentComplete = 100

        plan.tasks = [story, bug]

        let derived = AgileBoardDerivedContent.build(
            tasks: plan.tasks,
            assignments: plan.assignments,
            resources: plan.resources,
            sprints: plan.sprints,
            boardColumns: plan.boardColumns,
            workflowColumns: plan.workflowColumns,
            typeWorkflowOverrides: plan.typeWorkflowOverrides,
            statusSnapshots: plan.statusSnapshots
        )

        XCTAssertEqual(derived.sprintNamesByID[sprint.id], "Sprint 1")
        XCTAssertEqual(derived.totalStoryPoints, 5)
        XCTAssertEqual(derived.completedCount, 1)
        XCTAssertEqual(derived.readyCount, 1)
        XCTAssertEqual(derived.tasksByLane.first(where: { $0.lane == "Ready" })?.tasks.count, 1)
        XCTAssertEqual(derived.tasksByLane.first(where: { $0.lane == "Done" })?.tasks.count, 1)
    }

    func testAgileBoardDerivedContentPerformance() {
        let plan = makeLargePlan(taskCount: 800)

        measure {
            _ = AgileBoardDerivedContent.build(
                tasks: plan.tasks,
                assignments: plan.assignments,
                resources: plan.resources,
                sprints: plan.sprints,
                boardColumns: plan.boardColumns,
                workflowColumns: plan.workflowColumns,
                typeWorkflowOverrides: plan.typeWorkflowOverrides,
                statusSnapshots: plan.statusSnapshots
            )
        }
    }

    private func makeLargePlan(taskCount: Int) -> NativeProjectPlan {
        var plan = NativeProjectPlan.empty()
        let sprint = plan.makeSprint(name: "Performance Sprint")
        plan.sprints = [sprint]

        let statuses = ["Backlog", "Ready", "In Progress", "Review", "Done"]
        let types = ["Story", "Bug", "Task", "Feature"]

        var tasks: [NativePlanTask] = []
        tasks.reserveCapacity(taskCount)

        for index in 0..<taskCount {
            var task = plan.makeTask(name: "Task \(index + 1)")
            task.id = index + 1
            task.boardStatus = statuses[index % statuses.count]
            task.agileType = types[index % types.count]
            task.storyPoints = (index % 8) + 1
            task.sprintID = index.isMultiple(of: 3) ? sprint.id : nil
            task.percentComplete = task.boardStatus == "Done" ? 100 : Double((index % 7) * 10)
            tasks.append(task)
        }

        plan.tasks = tasks
        return plan
    }

    @MainActor
    private func makeInMemoryPortfolioContainer() throws -> ModelContainer {
        let schema = Schema([
            PortfolioProjectPlan.self,
            PortfolioPlanTask.self,
            PortfolioPlanResource.self,
            PortfolioPlanAssignment.self,
            PortfolioCrossProjectDependency.self,
            PortfolioReviewPreset.self,
            PortfolioReviewSnapshot.self,
            PortfolioPlanCalendar.self,
            PortfolioPlanSprint.self,
            PortfolioWorkflowColumn.self,
            PortfolioTypeWorkflow.self,
            PortfolioStatusSnapshot.self,
            PortfolioSprintStatusSnapshot.self
        ])

        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func loadSampleNativePlan() throws -> NativeProjectPlan {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sampleURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/sample-plans/aurora-commerce-launch.mppplan")
        let data = try Data(contentsOf: sampleURL)
        return try NativeProjectPlan.decode(from: data)
    }

    private func loadSecondaryNativePlan() throws -> NativeProjectPlan {
        let downloadsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("tplan.mppplan")

        if FileManager.default.fileExists(atPath: downloadsURL.path) {
            let data = try Data(contentsOf: downloadsURL)
            return try NativeProjectPlan.decode(from: data)
        }

        var generatedPlan = NativeProjectPlan.empty()
        generatedPlan.portfolioID = UUID()
        generatedPlan.title = "Secondary Portfolio Sample"
        generatedPlan.manager = "Test Manager"
        return generatedPlan
    }

    private func localMPPFixtureURL() -> URL? {
        let downloadsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return files
            .filter { $0.pathExtension.lowercased() == "mpp" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .first
    }
}
