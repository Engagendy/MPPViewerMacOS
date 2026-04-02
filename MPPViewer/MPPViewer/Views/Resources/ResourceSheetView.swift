import SwiftUI

struct ResourceSheetView: View {
    let resources: [ProjectResource]
    let assignments: [ResourceAssignment]
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
    let allTasks: [Int: ProjectTask]
    let navigateToTask: (Int) -> Void

    private var assignmentRows: [ResourceAssignmentRow] {
        assignments.compactMap { assignment in
            guard let task = allTasks[assignment.taskUniqueID ?? -1] else { return nil }
            return ResourceAssignmentRow(assignment: assignment, task: task)
        }
        .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    private var loadBuckets: [ResourceLoadBucket] {
        guard !assignmentRows.isEmpty else { return [] }
        let calendar = Calendar.current
        let starts = assignmentRows.compactMap(\.startDate)
        let finishes = assignmentRows.compactMap(\.finishDate)
        guard let first = starts.min(), let last = finishes.max() else { return [] }

        var buckets: [ResourceLoadBucket] = []
        var day = calendar.startOfDay(for: first)
        let endDay = calendar.startOfDay(for: last)

        while day <= endDay {
            let active = assignmentRows.filter {
                guard let start = $0.startDate, let finish = $0.finishDate else { return false }
                return calendar.startOfDay(for: start) <= day && calendar.startOfDay(for: finish) >= day
            }
            let units = active.reduce(0.0) { $0 + ($1.assignment.assignmentUnits ?? 100) }
            buckets.append(ResourceLoadBucket(date: day, units: units, taskNames: active.map(\.task.displayName)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return buckets
    }

    private var weeklyLoadWeeks: [ResourceWeek] {
        guard !loadBuckets.isEmpty else { return [] }
        let calendar = Calendar.current
        let firstDay = calendar.dateInterval(of: .weekOfYear, for: loadBuckets.first!.date)?.start ?? loadBuckets.first!.date
        let lastDay = calendar.dateInterval(of: .weekOfYear, for: loadBuckets.last!.date)?.end ?? loadBuckets.last!.date
        var weeks: [ResourceWeek] = []
        var cursor = firstDay

        while cursor <= lastDay {
            var weekBuckets: [ResourceLoadBucket] = []
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: cursor) else { continue }
                weekBuckets.append(bucketForDay(day))
            }
            weeks.append(ResourceWeek(startDate: cursor, dailyBuckets: weekBuckets))
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }

        return weeks
    }

    private func bucketForDay(_ date: Date) -> ResourceLoadBucket {
        if let existing = loadBuckets.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            return existing
        }
        return ResourceLoadBucket(date: date, units: 0, taskNames: [])
    }

    private func weeklyBarHeight(for bucket: ResourceLoadBucket, maxUnits: Double) -> CGFloat {
        let normalized = min(bucket.units / maxUnits, 2)
        return 30 + CGFloat(normalized) * 28
    }

    private var peakBucket: ResourceLoadBucket? {
        loadBuckets.max(by: { $0.units < $1.units })
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
                        infoRow("Overload Days", "\(loadBuckets.filter { $0.units > (resource.maxUnits ?? 100) }.count)")
                    }
                    .padding(4)
                }

                if !loadBuckets.isEmpty {
                    GroupBox("Load Timeline") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(loadBuckets.prefix(21)) { bucket in
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

        if !weeklyLoadWeeks.isEmpty {
            GroupBox("Weekly Overload Calendar") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(weeklyLoadWeeks) { week in
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
