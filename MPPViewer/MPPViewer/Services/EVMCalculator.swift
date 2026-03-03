import Foundation

// MARK: - EVM Metrics

struct EVMMetrics {
    let bac: Double   // Budget at Completion
    let pv: Double    // Planned Value (BCWS)
    let ev: Double    // Earned Value (BCWP)
    let ac: Double    // Actual Cost (ACWP)

    var cv: Double { ev - ac }          // Cost Variance
    var sv: Double { ev - pv }          // Schedule Variance
    var cpi: Double { ac > 0 ? ev / ac : 0 }  // Cost Performance Index
    var spi: Double { pv > 0 ? ev / pv : 0 }  // Schedule Performance Index
    var eac: Double { cpi > 0 ? bac / cpi : 0 } // Estimate at Completion
    var etc: Double { max(0, eac - ac) }         // Estimate to Complete
    var vac: Double { bac - eac }                // Variance at Completion
    var tcpi: Double {                           // To-Complete Performance Index
        let remaining = bac - ev
        let budgetRemaining = bac - ac
        return budgetRemaining > 0 ? remaining / budgetRemaining : 0
    }

    static let zero = EVMMetrics(bac: 0, pv: 0, ev: 0, ac: 0)
}

// MARK: - EVM Calculator

enum EVMCalculator {

    /// Compute EVM metrics for a single task
    static func compute(for task: ProjectTask, statusDate: Date) -> EVMMetrics {
        // Use MPXJ values if available
        if let bcws = task.bcws, let bcwp = task.bcwp, let acwp = task.acwp {
            let bac = task.baselineCost ?? task.cost ?? bcws
            return EVMMetrics(bac: bac, pv: bcws, ev: bcwp, ac: acwp)
        }

        // Fall back to computation from baseline/actual data
        let bac = task.baselineCost ?? task.cost ?? 0
        guard bac > 0 else { return .zero }

        let plannedPct = computePlannedPercent(
            baselineStart: task.baselineStartDate ?? task.startDate,
            baselineFinish: task.baselineFinishDate ?? task.finishDate,
            statusDate: statusDate
        )
        let pv = bac * plannedPct

        let earnedPct = (task.percentComplete ?? 0) / 100.0
        let ev = bac * earnedPct

        let ac = task.actualCost ?? (task.cost ?? 0) * earnedPct

        return EVMMetrics(bac: bac, pv: pv, ev: ev, ac: ac)
    }

    /// Aggregate project-level EVM from all non-summary tasks
    static func projectMetrics(tasks: [ProjectTask], statusDate: Date) -> EVMMetrics {
        let workTasks = tasks.filter { $0.summary != true }
        var totalBAC: Double = 0
        var totalPV: Double = 0
        var totalEV: Double = 0
        var totalAC: Double = 0

        for task in workTasks {
            let m = compute(for: task, statusDate: statusDate)
            totalBAC += m.bac
            totalPV += m.pv
            totalEV += m.ev
            totalAC += m.ac
        }

        return EVMMetrics(bac: totalBAC, pv: totalPV, ev: totalEV, ac: totalAC)
    }

    /// Linear interpolation of planned % complete based on baseline dates
    static func computePlannedPercent(baselineStart: Date?, baselineFinish: Date?, statusDate: Date) -> Double {
        guard let start = baselineStart, let finish = baselineFinish else { return 0 }
        let totalDuration = finish.timeIntervalSince(start)
        guard totalDuration > 0 else { return statusDate >= start ? 1.0 : 0 }
        let elapsed = statusDate.timeIntervalSince(start)
        return min(1.0, max(0, elapsed / totalDuration))
    }
}
