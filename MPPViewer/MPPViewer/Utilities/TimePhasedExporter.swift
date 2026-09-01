import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Options

enum TimePhasedGranularity: String, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case daily = "Daily"
    var id: String { rawValue }
}

enum TimePhasedBreakdown: String, CaseIterable, Identifiable {
    case projectOnly = "Project Only"
    case perTask = "Per Task"
    case perResource = "Per Resource"
    var id: String { rawValue }
}

struct TimePhasedExportOptions {
    var granularity: TimePhasedGranularity = .weekly
    var breakdown: TimePhasedBreakdown = .projectOnly
}

// MARK: - Exporter

/// Writes per-period (weekly or daily) planned value, earned value, actual
/// cost, and work-hour rows as CSV — project-level, with an optional per-task
/// or per-resource breakdown. The time-phasing model matches the EVM S-curve
/// (linear interpolation across each task's baseline window) and spreads work
/// hours evenly across each task's scheduled window.
enum TimePhasedExporter {

    private static let csvHeaders = [
        "Period Start",
        "Period End",
        "Scope",
        "ID",
        "Name",
        "Planned Value",
        "Earned Value",
        "Actual Cost",
        "Planned Work (h)",
        "Actual Work (h)"
    ]

    @MainActor
    static func exportWithSavePanel(project: ProjectModel, options: TimePhasedExportOptions) {
        guard let csv = buildCSV(project: project, options: options) else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Export Failed")
            alert.informativeText = String(localized: "This project has no dated tasks, so no time-phased data can be exported.")
            alert.runModal()
            return
        }

        let panel = NSSavePanel()
        panel.title = String(localized: "Export Time-Phased Data")
        panel.allowedContentTypes = [UTType(filenameExtension: "csv") ?? .commaSeparatedText]
        panel.nameFieldStringValue = "Time-Phased Data \(PDFExporter.fileNameTimestamp).csv"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    static func buildCSV(project: ProjectModel, options: TimePhasedExportOptions) -> String? {
        let statusDate = DateFormatting.parseMPXJDate(project.properties.statusDate ?? "") ?? Date()
        let phasings = project.tasks
            .filter { $0.summary != true }
            .map { TaskPhasing(task: $0, statusDate: statusDate, assignments: project.assignments) }
            .filter { $0.hasAnyData }

        guard let rangeStart = phasings.compactMap(\.earliestDate).min(),
              let rangeEnd = phasings.compactMap(\.latestDate).max(),
              rangeStart <= rangeEnd else {
            return nil
        }

        let periods = buildPeriods(from: rangeStart, to: rangeEnd, granularity: options.granularity)
        guard !periods.isEmpty else { return nil }

        let projectName = project.properties.projectTitle ?? "Project"
        var lines = [csvHeaders.joined(separator: ",")]

        for period in periods {
            // Project-level rollup row (always emitted).
            var totals = PeriodValues()
            for phasing in phasings {
                totals.add(phasing.values(from: period.start, to: period.endExclusive))
            }
            lines.append(row(period: period, scope: "Project", id: "", name: projectName, values: totals))

            switch options.breakdown {
            case .projectOnly:
                break
            case .perTask:
                for phasing in phasings {
                    let values = phasing.values(from: period.start, to: period.endExclusive)
                    guard !values.isEmpty else { continue }
                    lines.append(row(
                        period: period,
                        scope: "Task",
                        id: String(phasing.task.uniqueID),
                        name: phasing.task.displayName,
                        values: values
                    ))
                }
            case .perResource:
                for resource in project.resources {
                    guard let resourceID = resource.uniqueID else { continue }
                    var values = PeriodValues()
                    for phasing in phasings {
                        values.add(phasing.values(from: period.start, to: period.endExclusive, resourceID: resourceID))
                    }
                    guard !values.isEmpty else { continue }
                    lines.append(row(
                        period: period,
                        scope: "Resource",
                        id: String(resourceID),
                        name: resource.name ?? "Unnamed Resource",
                        values: values
                    ))
                }
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Periods

    private struct Period {
        let start: Date
        let endExclusive: Date
        var endInclusive: Date {
            Calendar.current.date(byAdding: .day, value: -1, to: endExclusive) ?? endExclusive
        }
    }

    private static func buildPeriods(from rangeStart: Date, to rangeEnd: Date, granularity: TimePhasedGranularity) -> [Period] {
        let calendar = Calendar.current
        var periods: [Period] = []

        var cursor: Date
        let stepDays: Int
        switch granularity {
        case .weekly:
            cursor = calendar.dateInterval(of: .weekOfYear, for: rangeStart)?.start
                ?? calendar.startOfDay(for: rangeStart)
            stepDays = 7
        case .daily:
            cursor = calendar.startOfDay(for: rangeStart)
            stepDays = 1
        }

        // Safety valve for degenerate date ranges (decades of daily rows).
        let maxPeriods = 4000
        while cursor <= rangeEnd, periods.count < maxPeriods {
            guard let next = calendar.date(byAdding: .day, value: stepDays, to: cursor) else { break }
            periods.append(Period(start: cursor, endExclusive: next))
            cursor = next
        }

        return periods
    }

    // MARK: - Row formatting

    private static func row(period: Period, scope: String, id: String, name: String, values: PeriodValues) -> String {
        [
            DateFormatting.simpleDate(period.start),
            DateFormatting.simpleDate(period.endInclusive),
            scope,
            id,
            name,
            format(values.plannedValue),
            format(values.earnedValue),
            format(values.actualCost),
            format(values.plannedWorkHours),
            format(values.actualWorkHours)
        ]
        .map(escapeCSV)
        .joined(separator: ",")
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

// MARK: - Period values

private struct PeriodValues {
    var plannedValue: Double = 0
    var earnedValue: Double = 0
    var actualCost: Double = 0
    var plannedWorkHours: Double = 0
    var actualWorkHours: Double = 0

    var isEmpty: Bool {
        abs(plannedValue) < 0.005 && abs(earnedValue) < 0.005 && abs(actualCost) < 0.005
            && abs(plannedWorkHours) < 0.005 && abs(actualWorkHours) < 0.005
    }

    mutating func add(_ other: PeriodValues) {
        plannedValue += other.plannedValue
        earnedValue += other.earnedValue
        actualCost += other.actualCost
        plannedWorkHours += other.plannedWorkHours
        actualWorkHours += other.actualWorkHours
    }
}

// MARK: - Per-task phasing model

private struct TaskPhasing {
    let task: ProjectTask
    let statusDate: Date

    /// Baseline (falls back to scheduled) window used for PV/EV interpolation.
    let costStart: Date?
    let costFinish: Date?
    /// Scheduled window used for planned work spreading.
    let workStart: Date?
    let workFinish: Date?
    /// Window used to spread actual cost and actual work.
    let actualStart: Date?
    let actualFinish: Date?

    let bac: Double
    let earnedPercent: Double        // 0...1
    let totalActualCost: Double
    let plannedWorkHours: Double
    let totalActualWorkHours: Double

    /// Per-resource shares of this task's work, keyed by resource unique ID.
    let resourceShares: [Int: (costFraction: Double, plannedWorkHours: Double, actualWorkHours: Double)]

    init(task: ProjectTask, statusDate: Date, assignments: [ResourceAssignment]) {
        self.task = task
        self.statusDate = statusDate

        costStart = task.baselineStartDate ?? task.startDate
        costFinish = task.baselineFinishDate ?? task.finishDate
        workStart = task.startDate ?? task.baselineStartDate
        workFinish = task.finishDate ?? task.baselineFinishDate
        actualStart = DateFormatting.parseMPXJDate(task.actualStart ?? "") ?? workStart
        let parsedActualFinish = DateFormatting.parseMPXJDate(task.actualFinish ?? "")
        actualFinish = min(parsedActualFinish ?? statusDate, statusDate)

        let metrics = EVMCalculator.compute(for: task, statusDate: statusDate)
        bac = metrics.bac
        totalActualCost = metrics.ac
        earnedPercent = min(1, max(0, (task.percentComplete ?? 0) / 100.0))

        let taskAssignments = assignments.filter { $0.taskUniqueID == task.uniqueID }
        let assignmentWorkSeconds = taskAssignments.reduce(0) { $0 + ($1.work ?? 0) }
        let taskWorkSeconds = task.work ?? assignmentWorkSeconds
        plannedWorkHours = Double(taskWorkSeconds > 0 ? taskWorkSeconds : assignmentWorkSeconds) / 3600.0

        let assignmentActualSeconds = taskAssignments.reduce(0) { $0 + ($1.actualWork ?? 0) }
        if assignmentActualSeconds > 0 {
            totalActualWorkHours = Double(assignmentActualSeconds) / 3600.0
        } else {
            let workPct = min(1, max(0, (task.percentWorkComplete ?? task.percentComplete ?? 0) / 100.0))
            totalActualWorkHours = plannedWorkHours * workPct
        }

        var shares: [Int: (costFraction: Double, plannedWorkHours: Double, actualWorkHours: Double)] = [:]
        let totalAssignmentCost = taskAssignments.reduce(0.0) { $0 + ($1.cost ?? 0) }
        let totalAssignmentWork = taskAssignments.reduce(0) { $0 + ($1.work ?? 0) }
        for assignment in taskAssignments {
            guard let resourceID = assignment.resourceUniqueID else { continue }
            let costFraction: Double
            if totalAssignmentCost > 0 {
                costFraction = (assignment.cost ?? 0) / totalAssignmentCost
            } else if totalAssignmentWork > 0 {
                costFraction = Double(assignment.work ?? 0) / Double(totalAssignmentWork)
            } else {
                costFraction = taskAssignments.isEmpty ? 0 : 1.0 / Double(taskAssignments.count)
            }

            var share = shares[resourceID] ?? (0, 0, 0)
            share.costFraction += costFraction
            share.plannedWorkHours += Double(assignment.work ?? 0) / 3600.0
            share.actualWorkHours += Double(assignment.actualWork ?? 0) / 3600.0
            shares[resourceID] = share
        }
        resourceShares = shares
    }

    var hasAnyData: Bool {
        bac > 0 || plannedWorkHours > 0 || totalActualCost > 0
    }

    var earliestDate: Date? {
        [costStart, workStart, actualStart].compactMap { $0 }.min()
    }

    var latestDate: Date? {
        [costFinish, workFinish, actualFinish].compactMap { $0 }.max()
    }

    /// Incremental values that fall inside [periodStart, periodEndExclusive).
    func values(from periodStart: Date, to periodEndExclusive: Date) -> PeriodValues {
        var values = PeriodValues()
        values.plannedValue = cumulativePV(at: periodEndExclusive) - cumulativePV(at: periodStart)
        values.earnedValue = cumulativeEV(at: periodEndExclusive) - cumulativeEV(at: periodStart)
        values.actualCost = cumulativeAC(at: periodEndExclusive) - cumulativeAC(at: periodStart)
        values.plannedWorkHours = cumulativePlannedWork(at: periodEndExclusive) - cumulativePlannedWork(at: periodStart)
        values.actualWorkHours = cumulativeActualWork(at: periodEndExclusive) - cumulativeActualWork(at: periodStart)
        return values
    }

    /// Incremental values for a single resource's share of this task.
    func values(from periodStart: Date, to periodEndExclusive: Date, resourceID: Int) -> PeriodValues {
        guard let share = resourceShares[resourceID] else { return PeriodValues() }
        let taskValues = values(from: periodStart, to: periodEndExclusive)

        var values = PeriodValues()
        values.plannedValue = taskValues.plannedValue * share.costFraction
        values.earnedValue = taskValues.earnedValue * share.costFraction
        values.actualCost = taskValues.actualCost * share.costFraction

        if plannedWorkHours > 0 {
            values.plannedWorkHours = taskValues.plannedWorkHours * (share.plannedWorkHours / plannedWorkHours)
        }
        if totalActualWorkHours > 0, share.actualWorkHours > 0 {
            values.actualWorkHours = taskValues.actualWorkHours * (share.actualWorkHours / totalActualWorkHours)
        }
        return values
    }

    // MARK: Cumulative curves (all monotone in `date`)

    private func cumulativePV(at date: Date) -> Double {
        bac * EVMCalculator.computePlannedPercent(baselineStart: costStart, baselineFinish: costFinish, statusDate: date)
    }

    private func cumulativeEV(at date: Date) -> Double {
        // Earned value is only known up to the status date; within that window
        // it follows the planned curve, capped at the reported % complete —
        // the same model the S-curve chart uses.
        let capped = min(date, statusDate)
        let plannedPct = EVMCalculator.computePlannedPercent(baselineStart: costStart, baselineFinish: costFinish, statusDate: capped)
        return bac * min(plannedPct, earnedPercent)
    }

    private func cumulativeAC(at date: Date) -> Double {
        let capped = min(date, statusDate)
        let fraction = EVMCalculator.computePlannedPercent(baselineStart: actualStart, baselineFinish: actualFinish, statusDate: capped)
        return totalActualCost * fraction
    }

    private func cumulativePlannedWork(at date: Date) -> Double {
        let fraction = EVMCalculator.computePlannedPercent(baselineStart: workStart, baselineFinish: workFinish, statusDate: date)
        return plannedWorkHours * fraction
    }

    private func cumulativeActualWork(at date: Date) -> Double {
        let capped = min(date, statusDate)
        let fraction = EVMCalculator.computePlannedPercent(baselineStart: actualStart, baselineFinish: actualFinish, statusDate: capped)
        return totalActualWorkHours * fraction
    }
}

// MARK: - Options sheet

struct TimePhasedExportSheet: View {
    let project: ProjectModel
    @Binding var isPresented: Bool

    @State private var options = TimePhasedExportOptions()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Export Time-Phased Data")
                    .font(.headline)
                Text("Per-period planned value, earned value, actual cost, and work hours as CSV.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Granularity", selection: $options.granularity) {
                ForEach(TimePhasedGranularity.allCases) { granularity in
                    Text(granularity.rawValue).tag(granularity)
                }
            }
            .pickerStyle(.radioGroup)

            Picker("Breakdown", selection: $options.breakdown) {
                ForEach(TimePhasedBreakdown.allCases) { breakdown in
                    Text(breakdown.rawValue).tag(breakdown)
                }
            }
            .pickerStyle(.radioGroup)
            .help("Project totals are always included; a breakdown adds one row per task or resource in each period.")

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Export…") {
                    isPresented = false
                    let exportOptions = options
                    let exportProject = project
                    DispatchQueue.main.async {
                        TimePhasedExporter.exportWithSavePanel(project: exportProject, options: exportOptions)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
