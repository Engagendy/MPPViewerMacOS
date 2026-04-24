import Foundation

// MARK: - Workload Models

struct ResourceWeeklyLoad: Identifiable {
    let id = UUID()
    let weekStart: Date
    let dayOffset: Int
    let totalHours: Double
    let capacity: Double
    var isOverAllocated: Bool { totalHours > capacity }
    var allocationPercent: Double { capacity > 0 ? (totalHours / capacity) * 100 : 0 }
}

struct ResourceWorkload: Identifiable {
    var id: Int { resource.uniqueID ?? 0 }
    let resource: ProjectResource
    let weeklyLoads: [ResourceWeeklyLoad]
    var peakAllocation: Double {
        weeklyLoads.map(\.allocationPercent).max() ?? 0
    }
    var isOverAllocated: Bool {
        weeklyLoads.contains(where: \.isOverAllocated)
    }
}

// MARK: - Workload Calculator

enum WorkloadCalculator {

    static func compute(
        resources: [ProjectResource],
        assignments: [ResourceAssignment],
        tasks: [ProjectTask],
        calendars: [ProjectCalendar],
        defaultCalendarID: Int?,
        dateRange: (start: Date, end: Date)
    ) -> [ResourceWorkload] {
        let calendar = Calendar.current
        let tasksByID = Dictionary(nonThrowingUniquePairs: tasks.map { ($0.uniqueID, $0) })
        let calendarsByID = Dictionary(nonThrowingUniquePairs: calendars.compactMap { cal -> (Int, ProjectCalendar)? in
            guard let uid = cal.uniqueID else { return nil }
            return (uid, cal)
        })

        // Resolve parent calendars: build effective working day lookup per calendar
        let defaultCal = defaultCalendarID.flatMap { calendarsByID[$0] }

        // Build week boundaries
        let weeks = buildWeekBoundaries(start: dateRange.start, end: dateRange.end, calendar: calendar)

        var workloads: [ResourceWorkload] = []

        for resource in resources {
            guard resource.type?.lowercased() == "work" || resource.type == nil else { continue }

            let resourceAssignments = assignments.filter { $0.resourceUniqueID == resource.uniqueID }
            guard !resourceAssignments.isEmpty else { continue }

            // Resolve resource's calendar: resource calendar → parent → default
            let resourceCal = resolveCalendar(
                for: resource,
                calendarsByID: calendarsByID,
                defaultCalendar: defaultCal
            )

            // Pre-compute exception date ranges for this calendar
            let exceptionRanges = buildExceptionRanges(from: resourceCal, calendar: calendar)

            let maxUnits = (resource.maxUnits ?? 100.0) / 100.0
            let weeklyCapacity = computeWeeklyCapacity(
                projectCalendar: resourceCal,
                calendarsByID: calendarsByID,
                maxUnits: maxUnits
            )

            var weeklyLoads: [ResourceWeeklyLoad] = []

            for (weekStart, weekEnd) in weeks {
                var totalHours: Double = 0

                for assignment in resourceAssignments {
                    guard let task = tasksByID[assignment.taskUniqueID ?? 0] else { continue }
                    guard let taskStart = task.startDate, let taskFinish = task.finishDate else { continue }

                    // Check overlap between task and this week
                    let overlapStart = max(taskStart, weekStart)
                    let overlapEnd = min(taskFinish, weekEnd)
                    guard overlapStart < overlapEnd else { continue }

                    // Count working days using the resource's actual calendar
                    let overlapWorkingDays = countWorkingDays(
                        from: overlapStart, to: overlapEnd,
                        projectCalendar: resourceCal,
                        exceptionRanges: exceptionRanges,
                        calendarsByID: calendarsByID,
                        calendar: calendar
                    )
                    guard overlapWorkingDays > 0 else { continue }

                    let taskWorkingDays = max(1, countWorkingDays(
                        from: taskStart, to: taskFinish,
                        projectCalendar: resourceCal,
                        exceptionRanges: exceptionRanges,
                        calendarsByID: calendarsByID,
                        calendar: calendar
                    ))

                    // Spread work evenly across working days
                    let totalWorkSeconds = Double(assignment.work ?? task.work ?? 0)
                    let totalWorkHours = totalWorkSeconds / 3600.0
                    let hoursPerDay = totalWorkHours / Double(taskWorkingDays)
                    let units = (assignment.assignmentUnits ?? 100.0) / 100.0

                    totalHours += hoursPerDay * Double(overlapWorkingDays) * units
                }

                let offset = calendar.dateComponents([.day], from: dateRange.start, to: weekStart).day ?? 0
                weeklyLoads.append(ResourceWeeklyLoad(
                    weekStart: weekStart,
                    dayOffset: offset,
                    totalHours: totalHours,
                    capacity: weeklyCapacity
                ))
            }

            workloads.append(ResourceWorkload(
                resource: resource,
                weeklyLoads: weeklyLoads
            ))
        }

        return workloads.sorted { $0.peakAllocation > $1.peakAllocation }
    }

    // MARK: - Calendar Resolution

    /// Walk the calendar's parent chain to find the most specific calendar for this resource
    private static func resolveCalendar(
        for resource: ProjectResource,
        calendarsByID: [Int: ProjectCalendar],
        defaultCalendar: ProjectCalendar?
    ) -> ProjectCalendar? {
        if let calID = resource.calendarUniqueID, let cal = calendarsByID[calID] {
            return cal
        }
        return defaultCalendar
    }

    // MARK: - Exception Pre-computation

    private struct ExceptionRange {
        let startDay: Date
        let endDay: Date
        let isWorking: Bool
    }

    private static func buildExceptionRanges(from projectCalendar: ProjectCalendar?, calendar: Calendar) -> [ExceptionRange] {
        guard let exceptions = projectCalendar?.exceptions else { return [] }
        return exceptions.compactMap { exception -> ExceptionRange? in
            guard let from = exception.fromDate, let to = exception.toDate else { return nil }
            return ExceptionRange(
                startDay: calendar.startOfDay(for: from),
                endDay: calendar.startOfDay(for: to),
                isWorking: exception.isWorking
            )
        }
    }

    // MARK: - Working Day Calculation

    private static func isWorkingDate(
        _ date: Date,
        weekday: Int,
        projectCalendar: ProjectCalendar?,
        exceptionRanges: [ExceptionRange],
        calendarsByID: [Int: ProjectCalendar],
        calendar: Calendar
    ) -> Bool {
        let startOfDay = calendar.startOfDay(for: date)

        // Exceptions override everything
        for exception in exceptionRanges {
            if startOfDay >= exception.startDay && startOfDay <= exception.endDay {
                return exception.isWorking
            }
        }

        // Use the calendar's day-of-week definition, resolving through parent chain
        if let cal = projectCalendar {
            return cal.resolvedIsWorkingDay(weekday: weekday, calendarsByID: calendarsByID)
        }

        // Fallback: Mon-Fri
        return weekday >= 2 && weekday <= 6
    }

    private static func countWorkingDays(
        from start: Date,
        to end: Date,
        projectCalendar: ProjectCalendar?,
        exceptionRanges: [ExceptionRange],
        calendarsByID: [Int: ProjectCalendar],
        calendar: Calendar
    ) -> Int {
        var count = 0
        var date = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        while date < endDay {
            let weekday = calendar.component(.weekday, from: date)
            if isWorkingDate(date, weekday: weekday, projectCalendar: projectCalendar, exceptionRanges: exceptionRanges, calendarsByID: calendarsByID, calendar: calendar) {
                count += 1
            }
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? endDay
        }
        return count
    }

    // MARK: - Weekly Capacity

    /// Calculate hours per week from the calendar's working day definitions, resolving through parents
    private static func computeWeeklyCapacity(
        projectCalendar: ProjectCalendar?,
        calendarsByID: [Int: ProjectCalendar],
        maxUnits: Double
    ) -> Double {
        guard let cal = projectCalendar else {
            return maxUnits * 40.0
        }

        var hoursPerWeek: Double = 0
        for weekday in 1...7 {
            if cal.resolvedIsWorkingDay(weekday: weekday, calendarsByID: calendarsByID) {
                if let hours = cal.resolvedHours(weekday: weekday, calendarsByID: calendarsByID), !hours.isEmpty {
                    hoursPerWeek += totalHoursFromRanges(hours)
                } else {
                    hoursPerWeek += 8.0
                }
            }
        }

        if hoursPerWeek == 0 {
            hoursPerWeek = 40.0
        }

        return maxUnits * hoursPerWeek
    }

    /// Parse "HH:mm" time ranges and sum total hours
    private static func totalHoursFromRanges(_ ranges: [CalendarHours]) -> Double {
        var total: Double = 0
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for range in ranges {
            guard let fromStr = range.from, let toStr = range.to,
                  let fromDate = formatter.date(from: fromStr),
                  let toDate = formatter.date(from: toStr) else { continue }
            let diff = toDate.timeIntervalSince(fromDate) / 3600.0
            if diff > 0 {
                total += diff
            }
        }
        return total
    }

    // MARK: - Week Boundaries

    private static func buildWeekBoundaries(start: Date, end: Date, calendar: Calendar) -> [(Date, Date)] {
        var weeks: [(Date, Date)] = []
        var current = calendar.startOfDay(for: start)

        // Align to Monday
        let weekday = calendar.component(.weekday, from: current)
        let daysToMonday = (weekday == 1) ? -6 : (2 - weekday)
        current = calendar.date(byAdding: .day, value: daysToMonday, to: current) ?? current

        while current < end {
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: current) ?? current
            weeks.append((current, weekEnd))
            current = weekEnd
        }

        return weeks
    }
}
