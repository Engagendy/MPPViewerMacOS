import Foundation

// MARK: - Leveling Models

/// One task the leveler moved, either by delaying it directly or because a
/// delayed predecessor pushed it through the scheduler.
struct ResourceLevelingMove: Identifiable, Hashable {
    let taskID: Int
    let taskName: String
    let oldStart: Date
    let oldFinish: Date
    let newStart: Date
    let newFinish: Date
    /// True when the leveler delayed this task itself; false when the move is
    /// ripple from rescheduling successors.
    let isDirectDelay: Bool

    var id: Int { taskID }

    var delayDays: Int {
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: oldStart),
            to: calendar.startOfDay(for: newStart)
        ).day ?? 0
    }
}

struct ResourceLevelingOverAllocation: Identifiable, Hashable {
    let resourceID: Int
    let resourceName: String
    let weekStart: Date
    let totalHours: Double
    let capacity: Double

    var id: String { "\(resourceID)-\(Int(weekStart.timeIntervalSince1970))" }
}

struct ResourceLevelingResult: Identifiable {
    let id = UUID()
    let leveledPlan: NativeProjectPlan
    let moves: [ResourceLevelingMove]
    let initialOverAllocations: [ResourceLevelingOverAllocation]
    let remainingOverAllocations: [ResourceLevelingOverAllocation]

    var resolvedOverAllocationCount: Int {
        max(0, initialOverAllocations.count - remainingOverAllocations.count)
    }
}

// MARK: - Resource Leveling Engine

/// Smooths resource over-allocations by delaying low-priority, non-critical
/// tasks within their available slack. The engine works on a value snapshot of
/// the plan; the caller decides whether to apply the leveled plan.
enum ResourceLevelingEngine {

    /// Upper bound on individual delay moves per run, so pathological plans
    /// cannot spin forever.
    private static let maxMoves = 200

    static func level(plan: NativeProjectPlan) -> ResourceLevelingResult {
        var workingPlan = plan
        var schedule = PlanScheduler.scheduleSync(workingPlan)
        workingPlan.tasks = schedule.tasks

        let initialTasksByID = Dictionary(nonThrowingUniquePairs: schedule.tasks.map { ($0.id, $0) })
        let initialOverAllocations = overAllocations(in: workingPlan, schedule: schedule)
        guard !initialOverAllocations.isEmpty else {
            return ResourceLevelingResult(
                leveledPlan: workingPlan,
                moves: [],
                initialOverAllocations: [],
                remainingOverAllocations: []
            )
        }

        // Leveling must never extend the project: every trial move is rejected
        // when the rescheduled finish lands after this baseline.
        let baselineProjectFinish = schedule.tasks.map(\.finishDate).max() ?? plan.statusDate
        let calendar = Calendar.current
        var attemptedMoves: Set<String> = []
        var directlyDelayedTaskIDs: Set<Int> = []

        for _ in 0 ..< maxMoves {
            let overWeeks = overAllocations(in: workingPlan, schedule: schedule)
            guard !overWeeks.isEmpty else { break }

            let summaryTaskIDs = workingPlan.summaryParentTaskIDs()
            let tasksByID = Dictionary(nonThrowingUniquePairs: workingPlan.tasks.map { ($0.id, $0) })
            var appliedMove = false

            overWeekLoop: for overWeek in overWeeks {
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: overWeek.weekStart) ?? overWeek.weekStart

                let candidates = delayCandidates(
                    in: workingPlan,
                    schedule: schedule,
                    tasksByID: tasksByID,
                    summaryTaskIDs: summaryTaskIDs,
                    resourceID: overWeek.resourceID,
                    weekStart: overWeek.weekStart,
                    weekEnd: weekEnd
                )

                for candidate in candidates {
                    let moveKey = "\(overWeek.resourceID)|\(Int(overWeek.weekStart.timeIntervalSince1970))|\(candidate.id)"
                    guard !attemptedMoves.contains(moveKey) else { continue }
                    attemptedMoves.insert(moveKey)

                    guard let index = workingPlan.tasks.firstIndex(where: { $0.id == candidate.id }) else { continue }

                    // Delay the task so it starts after the over-allocated week.
                    // Auto-scheduled tasks reseed from their own startDate, so
                    // moving the seed is enough; the scheduler recomputes the
                    // finish and clamps to predecessors/constraints. Manual
                    // tasks keep their stored dates, so shift both ends.
                    var delayedTask = workingPlan.tasks[index]
                    let oldStartDay = calendar.startOfDay(for: delayedTask.startDate)
                    let newStartDay = calendar.startOfDay(for: weekEnd)
                    guard newStartDay > oldStartDay else { continue }
                    if delayedTask.manuallyScheduled {
                        let dayDelta = calendar.dateComponents([.day], from: oldStartDay, to: newStartDay).day ?? 0
                        delayedTask.finishDate = calendar.date(byAdding: .day, value: dayDelta, to: delayedTask.finishDate) ?? delayedTask.finishDate
                    }
                    delayedTask.startDate = newStartDay

                    var trialPlan = workingPlan
                    trialPlan.tasks[index] = delayedTask
                    let trialSchedule = PlanScheduler.scheduleSync(trialPlan)
                    let trialFinish = trialSchedule.tasks.map(\.finishDate).max() ?? baselineProjectFinish

                    // Reject moves that consume more than the available slack
                    // (project finish grows) or that the scheduler snapped back
                    // into the same week.
                    guard trialFinish <= baselineProjectFinish,
                          let rescheduled = trialSchedule.tasks.first(where: { $0.id == candidate.id }),
                          calendar.startOfDay(for: rescheduled.startDate) >= newStartDay else {
                        continue
                    }

                    trialPlan.tasks = trialSchedule.tasks
                    workingPlan = trialPlan
                    schedule = trialSchedule
                    directlyDelayedTaskIDs.insert(candidate.id)
                    appliedMove = true
                    break overWeekLoop
                }
            }

            guard appliedMove else { break }
        }

        // Report every task whose dates changed against the initial schedule,
        // including successors the scheduler pushed along.
        var moves: [ResourceLevelingMove] = []
        for task in workingPlan.tasks {
            guard let original = initialTasksByID[task.id] else { continue }
            guard original.startDate != task.startDate || original.finishDate != task.finishDate else { continue }
            moves.append(ResourceLevelingMove(
                taskID: task.id,
                taskName: task.name,
                oldStart: original.startDate,
                oldFinish: original.finishDate,
                newStart: task.startDate,
                newFinish: task.finishDate,
                isDirectDelay: directlyDelayedTaskIDs.contains(task.id)
            ))
        }
        moves.sort { lhs, rhs in
            if lhs.oldStart != rhs.oldStart { return lhs.oldStart < rhs.oldStart }
            return lhs.taskID < rhs.taskID
        }

        return ResourceLevelingResult(
            leveledPlan: workingPlan,
            moves: moves,
            initialOverAllocations: initialOverAllocations,
            remainingOverAllocations: overAllocations(in: workingPlan, schedule: schedule)
        )
    }

    // MARK: - Candidate Selection

    /// Tasks assigned to the resource that contribute work to the given week
    /// and are safe to delay: leaf, active, unstarted, non-critical, with
    /// positive slack, and not pinned by MSO/MFO constraints. Sorted so the
    /// lowest-priority task with the most slack is tried first.
    private static func delayCandidates(
        in plan: NativeProjectPlan,
        schedule: PlanScheduleResult,
        tasksByID: [Int: NativePlanTask],
        summaryTaskIDs: Set<Int>,
        resourceID: Int,
        weekStart: Date,
        weekEnd: Date
    ) -> [NativePlanTask] {
        var candidates: [NativePlanTask] = []
        var seenTaskIDs: Set<Int> = []

        for assignment in plan.assignments where assignment.resourceID == resourceID {
            guard let task = tasksByID[assignment.taskID], !seenTaskIDs.contains(task.id) else { continue }
            seenTaskIDs.insert(task.id)

            guard !summaryTaskIDs.contains(task.id) else { continue }
            guard task.isActive else { continue }
            guard task.percentComplete <= 0, task.actualStartDate == nil else { continue }
            guard !schedule.criticalTaskIDs.contains(task.id) else { continue }
            guard (schedule.totalSlackSecondsByTaskID[task.id] ?? 0) > 0 else { continue }

            let constraint = normalizedConstraint(task.constraintType)
            guard constraint != "MSO", constraint != "MFO" else { continue }

            // Overlaps the over-allocated week and can actually leave it.
            guard task.startDate < weekEnd, task.normalizedFinishDate >= weekStart else { continue }

            candidates.append(task)
        }

        return candidates.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            let lhsSlack = schedule.totalSlackSecondsByTaskID[lhs.id] ?? 0
            let rhsSlack = schedule.totalSlackSecondsByTaskID[rhs.id] ?? 0
            if lhsSlack != rhsSlack {
                return lhsSlack > rhsSlack
            }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Over-Allocation Detection

    /// Reuses WorkloadCalculator on the scheduled plan projection and returns
    /// every over-allocated resource-week, earliest week first.
    private static func overAllocations(
        in plan: NativeProjectPlan,
        schedule: PlanScheduleResult
    ) -> [ResourceLevelingOverAllocation] {
        let project = plan.asProjectModel(scheduleResult: schedule)
        let range = GanttDateHelpers.dateRange(for: project.tasks)
        let workloads = WorkloadCalculator.compute(
            resources: project.resources,
            assignments: project.assignments,
            tasks: project.tasks,
            calendars: project.calendars,
            defaultCalendarID: project.properties.defaultCalendarUniqueId,
            dateRange: range
        )

        var result: [ResourceLevelingOverAllocation] = []
        for workload in workloads {
            guard let resourceID = workload.resource.uniqueID else { continue }
            for load in workload.weeklyLoads where load.totalHours > load.capacity + 0.01 {
                result.append(ResourceLevelingOverAllocation(
                    resourceID: resourceID,
                    resourceName: workload.resource.name ?? "Resource \(resourceID)",
                    weekStart: load.weekStart,
                    totalHours: load.totalHours,
                    capacity: load.capacity
                ))
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.weekStart != rhs.weekStart { return lhs.weekStart < rhs.weekStart }
            return lhs.resourceID < rhs.resourceID
        }
    }

    // MARK: - Constraint Normalization

    private static func normalizedConstraint(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        switch normalized {
        case "MSO", "MUSTSTARTON":
            return "MSO"
        case "MFO", "MUSTFINISHON":
            return "MFO"
        case "SNET", "STARTNOEARLIERTHAN":
            return "SNET"
        case "FNET", "FINISHNOEARLIERTHAN":
            return "FNET"
        default:
            return "ASAP"
        }
    }
}
