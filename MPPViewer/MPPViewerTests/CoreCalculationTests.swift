import XCTest
@testable import MPPViewer

final class CoreCalculationTests: XCTestCase {

    // MARK: - Helpers

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        return Calendar.current.startOfDay(for: Calendar.current.date(from: components)!)
    }

    private func makeProjectModel(tasks: [ProjectTask], finishDate: String? = nil) -> ProjectModel {
        let properties = ProjectProperties(
            projectTitle: "Test", author: nil, lastAuthor: nil, manager: nil,
            company: nil, startDate: nil, finishDate: finishDate, statusDate: nil,
            creationDate: nil, lastSaved: nil, currencySymbol: nil,
            currencyCode: nil, comments: nil, subject: nil, category: nil,
            keywords: nil, defaultCalendarUniqueId: nil,
            shortApplicationName: nil, fullApplicationName: nil
        )
        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.uniqueID, $0) })
        return ProjectModel(
            properties: properties,
            tasks: tasks,
            resources: [],
            assignments: [],
            calendars: [],
            rootTasks: tasks,
            tasksByID: tasksByID
        )
    }

    // MARK: - EVMMetrics derived values

    func testEVMMetricsDerivedValues() {
        let metrics = EVMMetrics(bac: 1000, pv: 500, ev: 400, ac: 500)

        XCTAssertEqual(metrics.cv, -100, accuracy: 0.001)
        XCTAssertEqual(metrics.sv, -100, accuracy: 0.001)
        XCTAssertEqual(metrics.cpi, 0.8, accuracy: 0.001)
        XCTAssertEqual(metrics.spi, 0.8, accuracy: 0.001)
        XCTAssertEqual(metrics.eac, 1250, accuracy: 0.001)
        XCTAssertEqual(metrics.etc, 750, accuracy: 0.001)
        XCTAssertEqual(metrics.vac, -250, accuracy: 0.001)
        XCTAssertEqual(metrics.tcpi, 600.0 / 500.0, accuracy: 0.001)
    }

    func testEVMMetricsZeroGuards() {
        let zeroActuals = EVMMetrics(bac: 1000, pv: 0, ev: 100, ac: 0)
        XCTAssertEqual(zeroActuals.cpi, 0)
        XCTAssertEqual(zeroActuals.spi, 0)
        XCTAssertEqual(zeroActuals.eac, 0)

        let overspent = EVMMetrics(bac: 1000, pv: 1000, ev: 500, ac: 1200)
        XCTAssertEqual(overspent.tcpi, 0, "TCPI must be 0 when remaining budget is negative")

        let allZero = EVMMetrics.zero
        XCTAssertEqual(allZero.cpi, 0)
        XCTAssertEqual(allZero.spi, 0)
        XCTAssertEqual(allZero.eac, 0)
        XCTAssertEqual(allZero.tcpi, 0)
    }

    // MARK: - EVMCalculator.compute

    func testComputeUsesMPXJValuesWhenPresent() {
        let task = ProjectTask(
            uniqueID: 1,
            name: "MPXJ Task",
            cost: 900,
            baselineCost: 1000,
            bcws: 600,
            bcwp: 550,
            acwp: 580
        )
        let metrics = EVMCalculator.compute(for: task, statusDate: Date())
        XCTAssertEqual(metrics.bac, 1000, accuracy: 0.001)
        XCTAssertEqual(metrics.pv, 600, accuracy: 0.001)
        XCTAssertEqual(metrics.ev, 550, accuracy: 0.001)
        XCTAssertEqual(metrics.ac, 580, accuracy: 0.001)
    }

    func testComputeFallbackFromBaselineAndProgress() {
        // Baseline: Jan 5 - Jan 14 (10 calendar days), status halfway.
        let task = ProjectTask(
            uniqueID: 2,
            name: "Fallback Task",
            percentComplete: 40,
            cost: 800,
            baselineStart: "2026-01-05",
            baselineFinish: "2026-01-15",
            baselineCost: 1000
        )
        let statusDate = day(2026, 1, 10)
        let metrics = EVMCalculator.compute(for: task, statusDate: statusDate)

        XCTAssertEqual(metrics.bac, 1000, accuracy: 0.001)
        XCTAssertEqual(metrics.pv, 500, accuracy: 0.5, "PV should be linearly interpolated to ~50%")
        XCTAssertEqual(metrics.ev, 400, accuracy: 0.001)
        // No actualCost: AC falls back to cost * earned percent.
        XCTAssertEqual(metrics.ac, 800 * 0.4, accuracy: 0.001)
    }

    func testComputeReturnsZeroWithoutBudget() {
        let task = ProjectTask(uniqueID: 3, name: "No Budget")
        let metrics = EVMCalculator.compute(for: task, statusDate: Date())
        XCTAssertEqual(metrics.bac, 0)
        XCTAssertEqual(metrics.pv, 0)
        XCTAssertEqual(metrics.ev, 0)
        XCTAssertEqual(metrics.ac, 0)
    }

    func testComputePlannedPercentBounds() {
        let start = day(2026, 1, 5)
        let finish = day(2026, 1, 15)

        XCTAssertEqual(EVMCalculator.computePlannedPercent(baselineStart: start, baselineFinish: finish, statusDate: day(2026, 1, 1)), 0)
        XCTAssertEqual(EVMCalculator.computePlannedPercent(baselineStart: start, baselineFinish: finish, statusDate: day(2026, 2, 1)), 1.0)
        XCTAssertEqual(EVMCalculator.computePlannedPercent(baselineStart: start, baselineFinish: finish, statusDate: day(2026, 1, 10)), 0.5, accuracy: 0.001)
        // Zero-duration baseline: complete once the status date reaches it.
        XCTAssertEqual(EVMCalculator.computePlannedPercent(baselineStart: start, baselineFinish: start, statusDate: day(2026, 1, 6)), 1.0)
        XCTAssertEqual(EVMCalculator.computePlannedPercent(baselineStart: start, baselineFinish: start, statusDate: day(2026, 1, 1)), 0)
        XCTAssertEqual(EVMCalculator.computePlannedPercent(baselineStart: nil, baselineFinish: finish, statusDate: day(2026, 1, 10)), 0)
    }

    func testProjectMetricsExcludesSummaryTasks() {
        let summary = ProjectTask(
            uniqueID: 10,
            name: "Summary",
            summary: true,
            baselineStart: "2026-01-05",
            baselineFinish: "2026-01-15",
            baselineCost: 99999
        )
        let childA = ProjectTask(
            uniqueID: 11,
            name: "A",
            percentComplete: 100,
            baselineStart: "2026-01-05",
            baselineFinish: "2026-01-15",
            baselineCost: 400,
            actualCost: 450
        )
        let childB = ProjectTask(
            uniqueID: 12,
            name: "B",
            percentComplete: 0,
            baselineStart: "2026-01-05",
            baselineFinish: "2026-01-15",
            baselineCost: 600,
            actualCost: 0
        )
        let metrics = EVMCalculator.projectMetrics(tasks: [summary, childA, childB], statusDate: day(2026, 2, 1))

        XCTAssertEqual(metrics.bac, 1000, accuracy: 0.001, "Summary task budget must not be double counted")
        XCTAssertEqual(metrics.ev, 400, accuracy: 0.001)
        XCTAssertEqual(metrics.ac, 450, accuracy: 0.001)
        XCTAssertEqual(metrics.pv, 1000, accuracy: 0.001)
    }

    // MARK: - ProjectDiffCalculator

    func testDiffDetectsAddedAndRemovedTasks() {
        let shared = ProjectTask(uniqueID: 1, name: "Shared", cost: 100)
        let removed = ProjectTask(uniqueID: 2, name: "Removed", critical: true, cost: 250)
        let added = ProjectTask(uniqueID: 3, name: "Added", critical: true, cost: 300)

        let baseline = makeProjectModel(tasks: [shared, removed])
        let current = makeProjectModel(tasks: [shared, added])

        let analysis = ProjectDiffCalculator.analyze(baseline: baseline, current: current)

        let addedDiff = analysis.diffs.first { $0.changeType == .added }
        let removedDiff = analysis.diffs.first { $0.changeType == .removed }

        XCTAssertEqual(analysis.diffs.count, 2)
        XCTAssertEqual(addedDiff?.taskName, "Added")
        XCTAssertEqual(addedDiff?.costDelta, 300)
        XCTAssertEqual(addedDiff?.criticalityDelta, .entered)
        XCTAssertEqual(removedDiff?.taskName, "Removed")
        XCTAssertEqual(removedDiff?.costDelta, -250)
        XCTAssertEqual(removedDiff?.criticalityDelta, .exited)
        XCTAssertEqual(analysis.summary.criticalAddedCount, 1)
        XCTAssertEqual(analysis.summary.criticalRemovedCount, 1)
    }

    func testDiffDetectsFinishSlipAndCostDelta() {
        let baselineTask = ProjectTask(
            uniqueID: 1,
            name: "Build",
            finish: "2026-01-10",
            critical: false,
            cost: 100
        )
        let slippedTask = ProjectTask(
            uniqueID: 1,
            name: "Build",
            finish: "2026-01-15",
            critical: true,
            cost: 180
        )

        let analysis = ProjectDiffCalculator.analyze(
            baseline: makeProjectModel(tasks: [baselineTask]),
            current: makeProjectModel(tasks: [slippedTask])
        )

        XCTAssertEqual(analysis.diffs.count, 1)
        let diff = analysis.diffs[0]
        XCTAssertEqual(diff.changeType, .modified)
        XCTAssertEqual(diff.finishDeltaDays, 5)
        XCTAssertEqual(diff.costDelta ?? 0, 80, accuracy: 0.001)
        XCTAssertEqual(diff.criticalityDelta, .entered)
        XCTAssertEqual(analysis.summary.finishMovedLaterCount, 1)
        XCTAssertEqual(analysis.summary.largestFinishSlip?.deltaDays, 5)
        XCTAssertEqual(analysis.summary.totalCostDelta, 80, accuracy: 0.001)
        XCTAssertEqual(analysis.summary.projectFinishDeltaDays, 5)
    }

    func testDiffReportsNoChangesForIdenticalProjects() {
        let task = ProjectTask(uniqueID: 1, name: "Stable", finish: "2026-01-10", cost: 100)
        let analysis = ProjectDiffCalculator.analyze(
            baseline: makeProjectModel(tasks: [task]),
            current: makeProjectModel(tasks: [task])
        )
        XCTAssertTrue(analysis.diffs.isEmpty)
        XCTAssertEqual(analysis.summary.totalCostDelta, 0)
        XCTAssertEqual(analysis.summary.finishMovedLaterCount, 0)
    }

    // MARK: - PlanScheduler

    private func makePlan(tasks: (inout NativeProjectPlan) -> [NativePlanTask]) -> NativeProjectPlan {
        var plan = NativeProjectPlan.empty()
        plan.statusDate = day(2026, 1, 5)
        plan.tasks = tasks(&plan)
        return plan
    }

    func testSchedulerRespectsDependencyChain() {
        let plan = makePlan { plan in
            var taskA = plan.makeTask(name: "A", anchoredTo: self.day(2026, 1, 5))
            taskA.id = 1
            taskA.durationDays = 2

            var taskB = plan.makeTask(name: "B", anchoredTo: self.day(2026, 1, 5))
            taskB.id = 2
            taskB.durationDays = 3
            taskB.predecessorTaskIDs = [1]
            return [taskA, taskB]
        }

        let result = PlanScheduler.scheduleSync(plan)
        let scheduledA = result.tasks.first { $0.id == 1 }!
        let scheduledB = result.tasks.first { $0.id == 2 }!

        // Mon Jan 5 2026 + 2 working days => finish Tue Jan 6.
        XCTAssertEqual(scheduledA.startDate, day(2026, 1, 5))
        XCTAssertEqual(scheduledA.finishDate, day(2026, 1, 6))
        // B starts the next working day and runs 3 working days: Wed 7 - Fri 9.
        XCTAssertEqual(scheduledB.startDate, day(2026, 1, 7))
        XCTAssertEqual(scheduledB.finishDate, day(2026, 1, 9))
    }

    func testSchedulerSkipsWeekends() {
        let plan = makePlan { plan in
            var task = plan.makeTask(name: "Weekend Spanner", anchoredTo: self.day(2026, 1, 9))
            task.id = 1
            task.durationDays = 2
            return [task]
        }

        let result = PlanScheduler.scheduleSync(plan)
        let scheduled = result.tasks[0]

        // Fri Jan 9 + 2 working days => finish Mon Jan 12 (weekend skipped).
        XCTAssertEqual(scheduled.startDate, day(2026, 1, 9))
        XCTAssertEqual(scheduled.finishDate, day(2026, 1, 12))
    }

    func testSchedulerStartsOnNextWorkingDayWhenSeededOnWeekend() {
        let plan = makePlan { plan in
            var task = plan.makeTask(name: "Weekend Start", anchoredTo: self.day(2026, 1, 10))
            task.id = 1
            task.durationDays = 1
            return [task]
        }

        let result = PlanScheduler.scheduleSync(plan)
        // Sat Jan 10 rolls forward to Mon Jan 12.
        XCTAssertEqual(result.tasks[0].startDate, day(2026, 1, 12))
    }

    func testSchedulerHonorsStartNoEarlierThanConstraint() {
        let plan = makePlan { plan in
            var task = plan.makeTask(name: "SNET", anchoredTo: self.day(2026, 1, 5))
            task.id = 1
            task.durationDays = 1
            task.constraintType = "SNET"
            task.constraintDate = self.day(2026, 1, 14)
            return [task]
        }

        let result = PlanScheduler.scheduleSync(plan)
        XCTAssertEqual(result.tasks[0].startDate, day(2026, 1, 14))
    }

    func testSchedulerSurvivesDependencyCycle() {
        let plan = makePlan { plan in
            var taskA = plan.makeTask(name: "A", anchoredTo: self.day(2026, 1, 5))
            taskA.id = 1
            taskA.predecessorTaskIDs = [2]
            var taskB = plan.makeTask(name: "B", anchoredTo: self.day(2026, 1, 5))
            taskB.id = 2
            taskB.predecessorTaskIDs = [1]
            return [taskA, taskB]
        }

        let result = PlanScheduler.scheduleSync(plan)
        XCTAssertEqual(result.tasks.count, 2, "Cyclic dependencies must not hang or drop tasks")
    }

    func testSchedulerIdentifiesCriticalChainAndSlack() {
        let plan = makePlan { plan in
            var taskA = plan.makeTask(name: "A", anchoredTo: self.day(2026, 1, 5))
            taskA.id = 1
            taskA.durationDays = 2
            var taskB = plan.makeTask(name: "B", anchoredTo: self.day(2026, 1, 5))
            taskB.id = 2
            taskB.durationDays = 3
            taskB.predecessorTaskIDs = [1]
            var taskC = plan.makeTask(name: "C", anchoredTo: self.day(2026, 1, 5))
            taskC.id = 3
            taskC.durationDays = 1
            return [taskA, taskB, taskC]
        }

        let result = PlanScheduler.scheduleSync(plan)

        XCTAssertTrue(result.criticalTaskIDs.contains(1))
        XCTAssertTrue(result.criticalTaskIDs.contains(2))
        XCTAssertFalse(result.criticalTaskIDs.contains(3), "Short independent task should have slack")
        XCTAssertGreaterThan(result.totalSlackSecondsByTaskID[3] ?? 0, 0)
        XCTAssertEqual(result.totalSlackSecondsByTaskID[2], 0)
    }

    func testSchedulerMilestoneFinishesOnStartDay() {
        let plan = makePlan { plan in
            var milestone = plan.makeTask(name: "Milestone", anchoredTo: self.day(2026, 1, 7))
            milestone.id = 1
            milestone.isMilestone = true
            milestone.durationDays = 5
            return [milestone]
        }

        let result = PlanScheduler.scheduleSync(plan)
        let scheduled = result.tasks[0]
        XCTAssertEqual(scheduled.startDate, scheduled.finishDate)
        XCTAssertEqual(scheduled.durationDays, 1)
    }

    func testSchedulerHandlesEmptyPlan() {
        let result = PlanScheduler.scheduleSync(NativeProjectPlan.empty())
        XCTAssertTrue(result.tasks.isEmpty)
        XCTAssertTrue(result.criticalTaskIDs.isEmpty)
    }
}

// MARK: - Incremental scheduling equivalence

final class IncrementalSchedulerTests: XCTestCase {

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        return Calendar.current.startOfDay(for: Calendar.current.date(from: components)!)
    }

    /// A phase with a chain of children plus an independent branch, so the test
    /// covers summaries, successors, and untouched tasks.
    private func makePlan() -> NativeProjectPlan {
        var plan = NativeProjectPlan.empty()
        func task(_ id: Int, _ name: String, level: Int, duration: Int, preds: [Int] = []) -> NativePlanTask {
            var t = plan.makeTask(name: name, anchoredTo: day(2026, 3, 2))
            t.id = id
            t.outlineLevel = level
            t.durationDays = duration
            t.predecessorTaskIDs = preds
            return t
        }
        plan.tasks = [
            task(1, "Phase", level: 1, duration: 1),
            task(2, "Design", level: 2, duration: 5),
            task(3, "Build", level: 2, duration: 10, preds: [2]),
            task(4, "Test", level: 2, duration: 4, preds: [3]),
            task(5, "Docs", level: 1, duration: 3),
        ]
        plan.reschedule()
        return plan
    }

    func testIncrementalMatchesFullAfterDurationChange() {
        var plan = makePlan()
        // Change Design's duration; Build/Test/Phase must move identically in
        // both modes while Docs stays frozen.
        let index = plan.tasks.firstIndex(where: { $0.id == 2 })!
        plan.tasks[index].durationDays = 9

        let full = PlanScheduler.scheduleSync(plan).tasks
        let incremental = PlanScheduler.scheduleSync(plan, changedTaskIDs: [2]).tasks

        XCTAssertEqual(full.count, incremental.count)
        for (fullTask, incrementalTask) in zip(full, incremental) {
            XCTAssertEqual(fullTask.id, incrementalTask.id)
            XCTAssertEqual(fullTask.startDate, incrementalTask.startDate, "start mismatch for \(fullTask.name)")
            XCTAssertEqual(fullTask.finishDate, incrementalTask.finishDate, "finish mismatch for \(fullTask.name)")
            XCTAssertEqual(fullTask.durationDays, incrementalTask.durationDays, "duration mismatch for \(fullTask.name)")
        }
    }

    func testIncrementalMatchesFullAfterPredecessorChange() {
        var plan = makePlan()
        // Link Docs after Test — the changed task is Docs itself.
        let index = plan.tasks.firstIndex(where: { $0.id == 5 })!
        plan.tasks[index].predecessorTaskIDs = [4]

        let full = PlanScheduler.scheduleSync(plan).tasks
        let incremental = PlanScheduler.scheduleSync(plan, changedTaskIDs: [5]).tasks

        for (fullTask, incrementalTask) in zip(full, incremental) {
            XCTAssertEqual(fullTask.startDate, incrementalTask.startDate, "start mismatch for \(fullTask.name)")
            XCTAssertEqual(fullTask.finishDate, incrementalTask.finishDate, "finish mismatch for \(fullTask.name)")
        }
    }

    func testIncrementalFallsBackWhenChangedIDMissing() {
        let plan = makePlan()
        // Unknown ID must not crash and must behave like a full pass.
        let full = PlanScheduler.scheduleSync(plan).tasks
        let incremental = PlanScheduler.scheduleSync(plan, changedTaskIDs: [999]).tasks
        XCTAssertEqual(full.map(\.startDate), incremental.map(\.startDate))
    }
}
