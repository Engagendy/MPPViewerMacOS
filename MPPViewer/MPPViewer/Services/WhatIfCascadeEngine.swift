import Foundation

// MARK: - What-If Models

/// A hypothetical edit to a single task: any combination of a new start date,
/// a new working-day duration, and a new percent complete.
struct WhatIfEdit: Hashable {
    var taskID: Int
    var newStartDate: Date?
    var newDurationDays: Int?
    var newPercentComplete: Double?

    var isEmpty: Bool {
        newStartDate == nil && newDurationDays == nil && newPercentComplete == nil
    }
}

/// One task the what-if edit moved — either the edited task itself or a
/// downstream task pushed through the dependency graph by the scheduler.
struct WhatIfTaskShift: Identifiable, Hashable {
    let taskID: Int
    let taskName: String
    let oldStart: Date
    let oldFinish: Date
    let newStart: Date
    let newFinish: Date
    let isSource: Bool
    let isSummary: Bool
    let isMilestone: Bool
    let isCritical: Bool

    var id: Int { taskID }

    var startDeltaDays: Int {
        WhatIfCascadeEngine.dayDelta(from: oldStart, to: newStart)
    }

    var finishDeltaDays: Int {
        WhatIfCascadeEngine.dayDelta(from: oldFinish, to: newFinish)
    }
}

/// Full cascade preview: the rescheduled plan plus every date shift relative
/// to the current schedule. Nothing is applied until the caller commits
/// `previewPlan` back into the live plan.
struct WhatIfCascadeResult: Identifiable {
    let id = UUID()
    let edit: WhatIfEdit
    let sourceTaskName: String
    /// The plan with the edit applied and a full reschedule run — every
    /// successor chain, constraint type, and task calendar honored.
    let previewPlan: NativeProjectPlan
    /// All tasks whose scheduled dates changed, source task first, then by
    /// new start date.
    let shifts: [WhatIfTaskShift]
    let oldProjectFinish: Date
    let newProjectFinish: Date

    var projectFinishDeltaDays: Int {
        WhatIfCascadeEngine.dayDelta(from: oldProjectFinish, to: newProjectFinish)
    }

    /// Downstream tasks only (leaf and milestone), excluding the edited task
    /// and summary roll-ups.
    var downstreamShifts: [WhatIfTaskShift] {
        shifts.filter { !$0.isSource && !$0.isSummary }
    }

    var summaryShifts: [WhatIfTaskShift] {
        shifts.filter { !$0.isSource && $0.isSummary }
    }

    var impactedMilestoneCount: Int {
        downstreamShifts.filter(\.isMilestone).count
    }

    var impactedCriticalCount: Int {
        downstreamShifts.filter(\.isCritical).count
    }
}

// MARK: - What-If Cascade Engine

/// Simulates a hypothetical edit to one task and computes the full downstream
/// propagation across the whole dependency graph by re-running the plan
/// scheduler on a value snapshot. The scheduler honors predecessor links,
/// constraint types (MSO/MFO/SNET/FNET), task calendars, and summary
/// roll-ups, so the preview is exactly what applying the edit would produce.
enum WhatIfCascadeEngine {

    static func simulate(plan: NativeProjectPlan, edit: WhatIfEdit) -> WhatIfCascadeResult? {
        let calendar = Calendar.current

        // Baseline: the current schedule. The editor keeps plan.tasks
        // scheduled, but re-running here guarantees the diff is against a
        // consistent baseline even when called with a raw snapshot.
        var basePlan = plan
        basePlan.tasks = PlanScheduler.scheduleSync(basePlan).tasks
        guard let index = basePlan.tasks.firstIndex(where: { $0.id == edit.taskID }) else { return nil }

        let baselineByID = Dictionary(nonThrowingUniquePairs: basePlan.tasks.map { ($0.id, $0) })
        let summaryTaskIDs = basePlan.summaryParentTaskIDs()

        // Apply the hypothetical edit to a trial copy. Auto-scheduled tasks
        // reseed from their own startDate, so moving the seed is enough; the
        // scheduler recomputes the finish and clamps to predecessors and
        // constraints. Manual tasks keep their stored dates, so both ends
        // must be maintained explicitly.
        var trialPlan = basePlan
        var task = trialPlan.tasks[index]

        if let newStartDate = edit.newStartDate {
            let oldStartDay = calendar.startOfDay(for: task.startDate)
            let newStartDay = calendar.startOfDay(for: newStartDate)
            if task.manuallyScheduled, !task.isMilestone {
                let dayDelta = calendar.dateComponents([.day], from: oldStartDay, to: newStartDay).day ?? 0
                task.finishDate = calendar.date(byAdding: .day, value: dayDelta, to: task.finishDate) ?? task.finishDate
            }
            task.startDate = newStartDay
            if task.isMilestone {
                task.finishDate = newStartDay
            }
        }

        if let newDurationDays = edit.newDurationDays, !task.isMilestone {
            task.durationDays = max(1, newDurationDays)
            // Manual tasks are scheduled from their stored dates, so stretch
            // the finish to cover the new duration; the scheduler normalizes
            // it onto working days. Auto tasks derive the finish from
            // durationDays directly.
            if task.manuallyScheduled {
                task.finishDate = calendar.date(
                    byAdding: .day,
                    value: max(0, task.durationDays - 1),
                    to: calendar.startOfDay(for: task.startDate)
                ) ?? task.finishDate
            }
        }

        if let newPercentComplete = edit.newPercentComplete {
            task.percentComplete = min(100, max(0, newPercentComplete))
        }

        trialPlan.tasks[index] = task

        // Full forward pass: cascades through every successor chain and rolls
        // up ancestor summaries.
        let trialSchedule = PlanScheduler.scheduleSync(trialPlan)
        trialPlan.tasks = trialSchedule.tasks

        var shifts: [WhatIfTaskShift] = []
        for scheduled in trialPlan.tasks {
            guard let baseline = baselineByID[scheduled.id] else { continue }
            let isSource = scheduled.id == edit.taskID
            let datesChanged = baseline.startDate != scheduled.startDate
                || baseline.finishDate != scheduled.finishDate
            guard datesChanged || isSource else { continue }
            shifts.append(WhatIfTaskShift(
                taskID: scheduled.id,
                taskName: scheduled.name,
                oldStart: baseline.startDate,
                oldFinish: baseline.normalizedFinishDate,
                newStart: scheduled.startDate,
                newFinish: scheduled.normalizedFinishDate,
                isSource: isSource,
                isSummary: summaryTaskIDs.contains(scheduled.id),
                isMilestone: scheduled.isMilestone,
                isCritical: trialSchedule.criticalTaskIDs.contains(scheduled.id)
            ))
        }
        shifts.sort { lhs, rhs in
            if lhs.isSource != rhs.isSource { return lhs.isSource }
            if lhs.newStart != rhs.newStart { return lhs.newStart < rhs.newStart }
            return lhs.taskID < rhs.taskID
        }

        let oldProjectFinish = basePlan.tasks.map(\.finishDate).max() ?? plan.statusDate
        let newProjectFinish = trialPlan.tasks.map(\.finishDate).max() ?? oldProjectFinish

        return WhatIfCascadeResult(
            edit: edit,
            sourceTaskName: basePlan.tasks[index].name,
            previewPlan: trialPlan,
            shifts: shifts,
            oldProjectFinish: oldProjectFinish,
            newProjectFinish: newProjectFinish
        )
    }

    static func dayDelta(from original: Date, to projected: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: original),
            to: calendar.startOfDay(for: projected)
        ).day ?? 0
    }
}
