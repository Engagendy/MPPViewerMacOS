import Foundation

struct ResourceCapacityScenarioWeek: Identifiable {
    let weekStart: Date
    let totalHours: Double
    let baselineCapacityHours: Double
    let simulatedCapacityHours: Double
    let baselineAllocationPercent: Double
    let simulatedAllocationPercent: Double
    let baselineOverloadHours: Double
    let simulatedOverloadHours: Double

    var id: Date { weekStart }

    var recoveredOverloadHours: Double {
        baselineOverloadHours - simulatedOverloadHours
    }
}

struct ResourceCapacityScenarioResult {
    let resourceName: String
    let addedTeamMembers: Int
    let baselineMaxUnits: Double
    let simulatedMaxUnits: Double
    let baselinePeakAllocation: Double
    let simulatedPeakAllocation: Double
    let baselineOverloadedWeekCount: Int
    let simulatedOverloadedWeekCount: Int
    let recoveredOverloadHours: Double
    let remainingOverloadHours: Double
    let weeks: [ResourceCapacityScenarioWeek]

    var resolvedWeekCount: Int {
        max(0, baselineOverloadedWeekCount - simulatedOverloadedWeekCount)
    }
}

enum ResourceCapacityScenarioAnalysis {

    static func simulate(
        resource: ProjectResource,
        assignments: [ResourceAssignment],
        tasks: [ProjectTask],
        calendars: [ProjectCalendar],
        defaultCalendarID: Int?,
        addedTeamMembers: Int
    ) -> ResourceCapacityScenarioResult? {
        guard addedTeamMembers > 0 else { return nil }

        let dateRange = scenarioDateRange(for: tasks)
        guard let workload = WorkloadCalculator.compute(
            resources: [resource],
            assignments: assignments,
            tasks: tasks,
            calendars: calendars,
            defaultCalendarID: defaultCalendarID,
            dateRange: dateRange
        ).first else {
            return nil
        }

        let baselineMaxUnits = max(resource.maxUnits ?? 100, 1)
        let fullTimeWeeklyCapacity = workload.weeklyLoads
            .compactMap { $0.capacity > 0 ? $0.capacity / (baselineMaxUnits / 100.0) : nil }
            .max() ?? 40
        let simulatedMaxUnits = baselineMaxUnits + Double(addedTeamMembers * 100)

        let weeks = workload.weeklyLoads.map { weeklyLoad -> ResourceCapacityScenarioWeek in
            let simulatedCapacity = weeklyLoad.capacity + (fullTimeWeeklyCapacity * Double(addedTeamMembers))
            let baselineOverloadHours = max(0, weeklyLoad.totalHours - weeklyLoad.capacity)
            let simulatedOverloadHours = max(0, weeklyLoad.totalHours - simulatedCapacity)
            return ResourceCapacityScenarioWeek(
                weekStart: weeklyLoad.weekStart,
                totalHours: weeklyLoad.totalHours,
                baselineCapacityHours: weeklyLoad.capacity,
                simulatedCapacityHours: simulatedCapacity,
                baselineAllocationPercent: weeklyLoad.allocationPercent,
                simulatedAllocationPercent: simulatedCapacity > 0 ? (weeklyLoad.totalHours / simulatedCapacity) * 100 : 0,
                baselineOverloadHours: baselineOverloadHours,
                simulatedOverloadHours: simulatedOverloadHours
            )
        }

        return ResourceCapacityScenarioResult(
            resourceName: resource.name ?? "Unnamed Resource",
            addedTeamMembers: addedTeamMembers,
            baselineMaxUnits: baselineMaxUnits,
            simulatedMaxUnits: simulatedMaxUnits,
            baselinePeakAllocation: weeks.map(\.baselineAllocationPercent).max() ?? 0,
            simulatedPeakAllocation: weeks.map(\.simulatedAllocationPercent).max() ?? 0,
            baselineOverloadedWeekCount: weeks.filter { $0.baselineOverloadHours > 0 }.count,
            simulatedOverloadedWeekCount: weeks.filter { $0.simulatedOverloadHours > 0 }.count,
            recoveredOverloadHours: weeks.reduce(0) { $0 + $1.recoveredOverloadHours },
            remainingOverloadHours: weeks.reduce(0) { $0 + $1.simulatedOverloadHours },
            weeks: weeks
        )
    }

    private static func scenarioDateRange(for tasks: [ProjectTask]) -> (start: Date, end: Date) {
        let allDates = tasks.compactMap(\.startDate) + tasks.compactMap(\.finishDate)
        guard let minDate = allDates.min(), let maxDate = allDates.max() else {
            let now = Date()
            return (now, now.addingTimeInterval(86_400 * 30))
        }

        let paddedStart = Calendar.current.date(byAdding: .day, value: -3, to: minDate) ?? minDate
        let paddedEnd = Calendar.current.date(byAdding: .day, value: 7, to: maxDate) ?? maxDate
        return (paddedStart, paddedEnd)
    }
}
