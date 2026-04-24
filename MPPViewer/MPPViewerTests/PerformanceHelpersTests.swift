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
