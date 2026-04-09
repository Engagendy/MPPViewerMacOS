import SwiftUI

struct ResourceSheetView: View {
    let resources: [ProjectResource]
    let assignments: [ResourceAssignment]
    let calendars: [ProjectCalendar]
    let defaultCalendarID: Int?
    let allTasks: [Int: ProjectTask]
    @Binding var navigateToTaskID: Int?
    @Binding var selectedNav: NavigationItem?

    @State private var selectedResourceID: Int? = nil
    @State private var inspectorWidth: CGFloat = 360

    private var workResources: [ResourceRow] {
        resources
            .filter { $0.type?.lowercased() == "work" || $0.type == nil }
            .map(ResourceRow.init)
    }

    private var selectedResource: ProjectResource? {
        guard let selectedResourceID else { return nil }
        return workResources.first(where: { $0.id == selectedResourceID })?.resource
    }

    var body: some View {
        if resources.isEmpty {
            ContentUnavailableView("No Resources", systemImage: "person.2", description: Text("This project has no resources defined."))
        } else {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Table(workResources, selection: $selectedResourceID) {
                        TableColumn("ID") { row in
                            let resource = row.resource
                            Text(resource.id.map(String.init) ?? "")
                                .monospacedDigit()
                        }
                        .width(min: 30, ideal: 50, max: 60)

                        TableColumn("Name") { row in
                            let resource = row.resource
                            Text(resource.name ?? "(Unnamed)")
                        }
                        .width(min: 150, ideal: 240)

                        TableColumn("Type") { row in
                            let resource = row.resource
                            Text(resource.type ?? "")
                        }
                        .width(min: 50, ideal: 80, max: 100)

                        TableColumn("Group") { row in
                            let resource = row.resource
                            Text(resource.group ?? "")
                        }
                        .width(min: 60, ideal: 100, max: 150)

                        TableColumn("Max Units") { row in
                            let resource = row.resource
                            if let units = resource.maxUnits {
                                Text("\(Int(units))%")
                                    .monospacedDigit()
                            }
                        }
                        .width(min: 60, ideal: 80, max: 100)

                        TableColumn("Assignments") { row in
                            let resource = row.resource
                            let count = resourceAssignments(for: resource).count
                            if count > 0 {
                                Text("\(count)")
                                    .monospacedDigit()
                            }
                        }
                        .width(min: 60, ideal: 80, max: 100)

                        TableColumn("Peak Load") { row in
                            let resource = row.resource
                            Text(peakAllocationText(for: resource))
                                .foregroundStyle(peakAllocationColor(for: resource))
                        }
                        .width(min: 80, ideal: 100, max: 120)
                    }

                    if let resource = selectedResource {
                        resizeHandle(totalWidth: geometry.size.width)
                        ResourceInspectorView(
                            resource: resource,
                            assignments: resourceAssignments(for: resource),
                            calendars: calendars,
                            defaultCalendarID: defaultCalendarID,
                            allTasks: allTasks,
                            navigateToTask: { uniqueID in
                                selectedNav = .tasks
                                navigateToTaskID = uniqueID
                            }
                        )
                        .frame(width: min(max(inspectorWidth, 320), max(320, geometry.size.width - 420)))
                    }
                }
            }
            .onAppear {
                if selectedResourceID == nil {
                    selectedResourceID = workResources.first?.id
                }
            }
        }
    }

    private func resourceAssignments(for resource: ProjectResource) -> [ResourceAssignment] {
        guard let uniqueID = resource.uniqueID else { return [] }
        return assignments.filter { $0.resourceUniqueID == uniqueID }
    }

    private func peakAllocationText(for resource: ProjectResource) -> String {
        let peak = peakAllocationPercent(for: resource)
        guard peak > 0 else { return "0%" }
        return "\(Int(peak))%"
    }

    private func peakAllocationColor(for resource: ProjectResource) -> Color {
        let peak = peakAllocationPercent(for: resource)
        let maxUnits = resource.maxUnits ?? 100
        return peak > maxUnits ? .red : .secondary
    }

    private func peakAllocationPercent(for resource: ProjectResource) -> Double {
        let resourceAssignments = resourceAssignments(for: resource)
        guard !resourceAssignments.isEmpty else { return 0 }

        let intervals = resourceAssignments.compactMap { assignment -> ResourceLoadInterval? in
            let task = allTasks[assignment.taskUniqueID ?? -1]
            guard let start = assignment.start.flatMap(DateFormatting.parseMPXJDate) ?? task?.startDate,
                  let finish = assignment.finish.flatMap(DateFormatting.parseMPXJDate) ?? task?.finishDate
            else { return nil }
            return ResourceLoadInterval(
                start: Calendar.current.startOfDay(for: start),
                finish: Calendar.current.startOfDay(for: finish),
                units: assignment.assignmentUnits ?? 100
            )
        }

        var peak: Double = 0
        let calendar = Calendar.current
        for interval in intervals {
            var day = interval.start
            while day <= interval.finish {
                let total = intervals
                    .filter { $0.start <= day && $0.finish >= day }
                    .reduce(0.0) { $0 + $1.units }
                peak = max(peak, total)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        return peak
    }

    private func resizeHandle(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 10)
            .overlay {
                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
            .cursor(.resizeLeftRight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let proposedWidth = inspectorWidth - value.translation.width
                        inspectorWidth = min(max(proposedWidth, 320), max(320, totalWidth - 420))
                    }
            )
    }
}

private struct ResourceRow: Identifiable {
    let resource: ProjectResource

    var id: Int {
        resource.uniqueID ?? resource.id ?? 0
    }
}

private struct ResourceInspectorView: View {
    let resource: ProjectResource
    let assignments: [ResourceAssignment]
    let calendars: [ProjectCalendar]
    let defaultCalendarID: Int?
    let allTasks: [Int: ProjectTask]
    let navigateToTask: (Int) -> Void

    @State private var cachedLoadBuckets: [ResourceLoadBucket] = []
    @State private var cachedWeeklyWeeks: [ResourceWeek] = []
    @State private var scenarioAddedTeamMembers: Int = 1

    private var assignmentRows: [ResourceAssignmentRow] {
        assignments.compactMap { assignment in
            guard let task = allTasks[assignment.taskUniqueID ?? -1] else { return nil }
            return ResourceAssignmentRow(assignment: assignment, task: task)
        }
        .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    private var capacityScenarioResult: ResourceCapacityScenarioResult? {
        ResourceCapacityScenarioAnalysis.simulate(
            resource: resource,
            assignments: assignments,
            tasks: Array(allTasks.values),
            calendars: calendars,
            defaultCalendarID: defaultCalendarID,
            addedTeamMembers: scenarioAddedTeamMembers
        )
    }

    private var capacityScenarioWeeks: [ResourceCapacityScenarioWeek] {
        guard let capacityScenarioResult else { return [] }
        return capacityScenarioResult.weeks
            .filter { $0.baselineOverloadHours > 0 || $0.simulatedOverloadHours > 0 }
            .sorted { lhs, rhs in
                if lhs.recoveredOverloadHours == rhs.recoveredOverloadHours {
                    return lhs.weekStart < rhs.weekStart
                }
                return lhs.recoveredOverloadHours > rhs.recoveredOverloadHours
            }
    }

    private func refreshLoadData() {
        let rows = assignmentRows
        let buckets = rows.isEmpty ? [] : Self.buildLoadBuckets(from: rows)
        cachedLoadBuckets = buckets
        cachedWeeklyWeeks = buckets.isEmpty ? [] : Self.buildWeeklyWeeks(from: buckets)
    }

    private static func buildLoadBuckets(from rows: [ResourceAssignmentRow]) -> [ResourceLoadBucket] {
        guard !rows.isEmpty else { return [] }
        let calendar = Calendar.current
        let starts = rows.compactMap(\.startDate)
        let finishes = rows.compactMap(\.finishDate)
        guard let first = starts.min(), let last = finishes.max() else { return [] }

        var buckets: [ResourceLoadBucket] = []
        var day = calendar.startOfDay(for: first)
        let endDay = calendar.startOfDay(for: last)

        while day <= endDay {
            let active = rows.filter {
                guard let start = $0.startDate, let finish = $0.finishDate else { return false }
                return calendar.startOfDay(for: start) <= day && calendar.startOfDay(for: finish) >= day
            }
            let units = active.reduce(0.0) { $0 + ($1.assignment.assignmentUnits ?? 100) }
            let taskNames = active.map(\.task.displayName)
            buckets.append(ResourceLoadBucket(date: day, units: units, taskNames: taskNames))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return buckets
    }

    private static func buildWeeklyWeeks(from buckets: [ResourceLoadBucket]) -> [ResourceWeek] {
        guard !buckets.isEmpty else { return [] }
        let calendar = Calendar.current
        let sortedBuckets = buckets.sorted { $0.date < $1.date }
        let firstDay = calendar.dateInterval(of: .weekOfYear, for: sortedBuckets.first!.date)?.start ?? sortedBuckets.first!.date
        let lastDay = calendar.dateInterval(of: .weekOfYear, for: sortedBuckets.last!.date)?.end ?? sortedBuckets.last!.date
        var weeks: [ResourceWeek] = []
        var cursor = firstDay
        let bucketMap = Dictionary(grouping: buckets) { calendar.startOfDay(for: $0.date) }

        while cursor <= lastDay {
            var weekBuckets: [ResourceLoadBucket] = []
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: cursor) else { continue }
                let dayKey = calendar.startOfDay(for: day)
                if let existing = bucketMap[dayKey]?.first {
                    weekBuckets.append(existing)
                } else {
                    weekBuckets.append(ResourceLoadBucket(date: day, units: 0, taskNames: []))
                }
            }
            weeks.append(ResourceWeek(startDate: cursor, dailyBuckets: weekBuckets))
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }

        return weeks
    }

    private func weeklyBarHeight(for bucket: ResourceLoadBucket, maxUnits: Double) -> CGFloat {
        let normalized = min(bucket.units / maxUnits, 2)
        return 30 + CGFloat(normalized) * 28
    }

    private func timelineBarHeight(for bucket: ResourceLoadBucket, maxUnits: Double) -> CGFloat {
        let normalized = min(bucket.units / max(maxUnits, 1), 2)
        return 30 + CGFloat(normalized) * 28
    }

    private func overloadSuggestion(maxUnits: Double) -> String {
        let overloaded = cachedLoadBuckets.filter { $0.units > maxUnits }
        guard let peak = overloaded.max(by: { $0.units < $1.units }) else {
            return "Allocations are within the resource's max units."
        }
        let tasks = peak.taskNames.prefix(2).joined(separator: ", ")
        return "Peak \(Int(peak.units))% on \(DateFormatting.shortDate(peak.date)). Consider shifting \(tasks) to reduce pressure."
    }

    private var peakBucket: ResourceLoadBucket? {
        cachedLoadBuckets.max(by: { $0.units < $1.units })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(resource.name ?? "(Unnamed Resource)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    HStack(spacing: 10) {
                        statPill(resource.type ?? "Work", color: .blue)
                        statPill("Assignments \(assignmentRows.count)", color: .secondary)
                        if let maxUnits = resource.maxUnits {
                            statPill("Max \(Int(maxUnits))%", color: .orange)
                        }
                    }
                }

                GroupBox("Overview") {
                    VStack(alignment: .leading, spacing: 6) {
                        infoRow("Group", resource.group)
                        infoRow("Email", resource.emailAddress)
                        infoRow("Peak Allocation", peakBucket.map { "\(Int($0.units))% on \(DateFormatting.shortDate($0.date))" })
                        infoRow("Overload Days", "\(cachedLoadBuckets.filter { $0.units > (resource.maxUnits ?? 100) }.count)")
                    }
                    .padding(4)
                }

                if let capacityScenarioResult {
                    GroupBox("Capacity Scenario") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Model added weekly capacity for this resource. This reduces overload pressure, but it does not reschedule tasks or change dates.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Text("Added Team Members")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Stepper(value: $scenarioAddedTeamMembers, in: 1...3) {
                                    Text("\(scenarioAddedTeamMembers)")
                                        .font(.caption)
                                        .monospacedDigit()
                                }
                                .labelsHidden()
                                Text("\(scenarioAddedTeamMembers)")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .frame(width: 24, alignment: .trailing)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                infoRow("Capacity", "\(Int(capacityScenarioResult.baselineMaxUnits))% -> \(Int(capacityScenarioResult.simulatedMaxUnits))%")
                                infoRow("Peak Allocation", "\(Int(capacityScenarioResult.baselinePeakAllocation.rounded()))% -> \(Int(capacityScenarioResult.simulatedPeakAllocation.rounded()))%")
                                infoRow("Overloaded Weeks", "\(capacityScenarioResult.baselineOverloadedWeekCount) -> \(capacityScenarioResult.simulatedOverloadedWeekCount)")
                                infoRow("Excess Hours", "\(formatHours(capacityScenarioResult.recoveredOverloadHours + capacityScenarioResult.remainingOverloadHours)) -> \(formatHours(capacityScenarioResult.remainingOverloadHours))")
                            }

                            Text(capacityScenarioSummary(capacityScenarioResult))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if capacityScenarioWeeks.isEmpty {
                                Text("Current weekly workload is already within capacity for this resource.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Most Improved Weeks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    ForEach(capacityScenarioWeeks.prefix(4)) { week in
                                        capacityScenarioWeekRow(week)
                                        if week.id != capacityScenarioWeeks.prefix(4).last?.id {
                                            Divider()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(4)
                    }
                }

                if !cachedLoadBuckets.isEmpty {
                    GroupBox("Load Timeline") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(cachedLoadBuckets.prefix(21)) { bucket in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(DateFormatting.shortDate(bucket.date))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 90, alignment: .leading)
                                        GeometryReader { geometry in
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.secondary.opacity(0.15))
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(bucket.units > (resource.maxUnits ?? 100) ? Color.red.opacity(0.7) : Color.blue.opacity(0.7))
                                                    .frame(width: geometry.size.width * min(CGFloat(bucket.units / max(resource.maxUnits ?? 100, 100)), 1.0))
                                            }
                                        }
                                        .frame(height: 10)
                                        Text("\(Int(bucket.units))%")
                                            .font(.caption)
                                            .monospacedDigit()
                                            .frame(width: 50, alignment: .trailing)
                                    }
                                    if !bucket.taskNames.isEmpty {
                                        Text(bucket.taskNames.prefix(3).joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(4)
                    }
                }

                if !cachedLoadBuckets.isEmpty {
                    GroupBox("Overload Timeline") {
                        ScrollView(.horizontal, showsIndicators: true) {
                            HStack(alignment: .bottom, spacing: 10) {
                                ForEach(cachedLoadBuckets) { bucket in
                                    let maxUnits = resource.maxUnits ?? 100
                                    let barHeight = timelineBarHeight(for: bucket, maxUnits: maxUnits)
                                    VStack(spacing: 6) {
                                        ZStack(alignment: .bottom) {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.secondary.opacity(0.15))
                                                .frame(width: 40, height: 110)
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(bucket.units > maxUnits ? Color.red.opacity(0.9) : Color.blue.opacity(0.65))
                                                .frame(width: 40, height: barHeight)
                                                .shadow(color: bucket.units > maxUnits ? Color.red.opacity(0.25) : Color.blue.opacity(0.15), radius: 4, x: 0, y: 3)
                                        }
                                        Text(DateFormatting.shortDate(bucket.date))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("\(Int(bucket.units))%")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(bucket.units > maxUnits ? .red : .primary)
                                        if bucket.units > maxUnits, let highlight = bucket.taskNames.first {
                                            Text(highlight)
                                                .font(.caption2)
                                                .lineLimit(1)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(width: 54)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 6)
                        }
                        Text(overloadSuggestion(maxUnits: resource.maxUnits ?? 100))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }

                if !cachedWeeklyWeeks.isEmpty {
                    GroupBox("Weekly Overload Calendar") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 18) {
                                ForEach(cachedWeeklyWeeks) { week in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Week of \(DateFormatting.shortDate(week.startDate))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        HStack(alignment: .bottom, spacing: 6) {
                                            ForEach(week.dailyBuckets) { bucket in
                                                VStack(spacing: 4) {
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .fill(bucket.units > (resource.maxUnits ?? 100) ? Color.red.opacity(0.85) : Color.blue.opacity(0.65))
                                                        .frame(width: 26, height: weeklyBarHeight(for: bucket, maxUnits: resource.maxUnits ?? 100))
                                                    Text(DateFormatting.shortWeekday(bucket.date))
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                                .help(bucket.taskNames.prefix(3).joined(separator: ", "))
                                            }
                                        }
                                    }
                                    .frame(width: 220)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(height: 140)
                    }
                }

                GroupBox("Assignments") {
                    if assignmentRows.isEmpty {
                        Text("No assignments found for this resource.")
                            .foregroundStyle(.secondary)
                            .padding(4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(assignmentRows) { row in
                                Button {
                                    navigateToTask(row.task.uniqueID)
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Circle()
                                            .fill(row.assignment.assignmentUnits ?? 100 > (resource.maxUnits ?? 100) ? Color.red : Color.blue)
                                            .frame(width: 8, height: 8)
                                            .padding(.top, 4)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(row.task.displayName)
                                                .foregroundStyle(.primary)
                                            Text("Task \(row.task.id.map(String.init) ?? "\(row.task.uniqueID)") · \(DateFormatting.shortDate(row.task.start)) to \(DateFormatting.shortDate(row.task.finish))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("\(Int(row.assignment.assignmentUnits ?? 100))%")
                                                .foregroundStyle(.primary)
                                            if let work = row.assignment.work {
                                                Text(DurationFormatting.formatSeconds(work))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if row.id != assignmentRows.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refreshLoadData()
        }
        .task(id: resource.uniqueID ?? -1) {
            refreshLoadData()
        }
    }

    private func statPill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .trailing)
                Text(value)
            }
            .font(.caption)
        }
    }

    private func formatHours(_ hours: Double) -> String {
        let rounded = (hours * 10).rounded() / 10
        if rounded.rounded(.towardZero) == rounded {
            return "\(Int(rounded))h"
        }
        return String(format: "%.1fh", rounded)
    }

    private func capacityScenarioSummary(_ result: ResourceCapacityScenarioResult) -> String {
        if result.baselineOverloadedWeekCount == 0 {
            return "This resource is already within weekly capacity. Adding people only creates extra headroom."
        }

        if result.simulatedOverloadedWeekCount == 0 {
            return "Adding \(result.addedTeamMembers) team member\(result.addedTeamMembers == 1 ? "" : "s") would absorb all currently overloaded weeks for this resource."
        }

        return "Adding \(result.addedTeamMembers) team member\(result.addedTeamMembers == 1 ? "" : "s") resolves \(result.resolvedWeekCount) overloaded week\(result.resolvedWeekCount == 1 ? "" : "s"), but \(result.simulatedOverloadedWeekCount) still remain."
    }

    private func capacityScenarioWeekRow(_ week: ResourceCapacityScenarioWeek) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text("Week of \(DateFormatting.shortDate(week.weekStart))")
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(Int(week.baselineAllocationPercent.rounded()))% -> \(Int(week.simulatedAllocationPercent.rounded()))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(week.simulatedOverloadHours > 0 ? .red : .green)
            }
            Text("Load \(formatHours(week.totalHours)) against \(formatHours(week.baselineCapacityHours)) baseline capacity and \(formatHours(week.simulatedCapacityHours)) scenario capacity.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if week.recoveredOverloadHours > 0 {
                Text("Recovered \(formatHours(week.recoveredOverloadHours)) of weekly overload.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}

private struct ResourceAssignmentRow: Identifiable {
    let assignment: ResourceAssignment
    let task: ProjectTask

    var id: Int {
        assignment.id
    }

    var startDate: Date? {
        assignment.start.flatMap(DateFormatting.parseMPXJDate) ?? task.startDate
    }

    var finishDate: Date? {
        assignment.finish.flatMap(DateFormatting.parseMPXJDate) ?? task.finishDate
    }
}

private struct ResourceLoadInterval {
    let start: Date
    let finish: Date
    let units: Double
}

private struct ResourceLoadBucket: Identifiable {
    let date: Date
    let units: Double
    let taskNames: [String]

    var id: Date { date }
}

private struct ResourceWeek: Identifiable {
    let startDate: Date
    let dailyBuckets: [ResourceLoadBucket]

    var id: Date { startDate }
}
