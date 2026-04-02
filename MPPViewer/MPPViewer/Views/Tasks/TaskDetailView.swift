import SwiftUI

struct TaskDetailView: View {
    let task: ProjectTask
    let allTasks: [Int: ProjectTask]
    let resources: [ProjectResource]
    let assignments: [ResourceAssignment]
    let breadcrumbTaskIDs: [Int]
    var onSelectTask: ((Int) -> Void)? = nil
    var onSelectBreadcrumb: ((Int) -> Void)? = nil
    @AppStorage(ReviewNotesStore.key) private var taskReviewNotesData: Data = Data()
    @State private var dependencyDepth: Int = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                header

                if !breadcrumbTasks.isEmpty {
                    breadcrumbBar
                }

                Divider()

                // General Info
                GroupBox("General") {
                    detailGrid {
                        detailRow("ID", value: task.id.map(String.init))
                        detailRow("WBS", value: task.wbs)
                        detailRow("Outline Level", value: task.outlineLevel.map(String.init))
                        detailRow("Type", value: taskTypeLabel)
                        detailRow("Priority", value: task.priority.map(String.init))
                        detailRow("Active", value: task.active.map { $0 ? "Yes" : "No" })
                        detailRow("GUID", value: task.guid)
                    }
                }

                GroupBox("Source Data") {
                    detailGrid {
                        detailRow("Raw Type", value: task.type)
                        detailRow("Raw Milestone Flag", value: boolLabel(task.milestone))
                        detailRow("Raw Summary Flag", value: boolLabel(task.summary))
                        detailRow("Raw Critical Flag", value: boolLabel(task.critical))
                        detailRow("Display Type", value: displayTypeLabel)
                        detailRow("Classification Note", value: classificationNote)
                    }
                }

                // Schedule
                GroupBox("Schedule") {
                    detailGrid {
                        detailRow("Start", value: DateFormatting.mediumDateTime(task.start))
                        detailRow("Finish", value: DateFormatting.mediumDateTime(task.finish))
                        detailRow("Actual Start", value: DateFormatting.mediumDateTime(task.actualStart))
                        detailRow("Actual Finish", value: DateFormatting.mediumDateTime(task.actualFinish))
                        detailRow("Duration", value: task.durationDisplay)
                        detailRow("Actual Duration", value: task.actualDuration.map { DurationFormatting.formatSeconds($0) })
                        detailRow("Remaining Duration", value: task.remainingDuration.map { DurationFormatting.formatSeconds($0) })
                        detailRow("Constraint", value: task.constraintType)
                        detailRow("Constraint Date", value: DateFormatting.mediumDateTime(task.constraintDate))
                    }
                }

                // Baseline
                if task.hasBaseline {
                    GroupBox("Baseline") {
                        detailGrid {
                            detailRow("Baseline Start", value: DateFormatting.mediumDateTime(task.baselineStart))
                            detailRow("Baseline Finish", value: DateFormatting.mediumDateTime(task.baselineFinish))
                            detailRow("Baseline Duration", value: task.baselineDuration.map { DurationFormatting.formatSeconds($0) })
                            if let bc = task.baselineCost {
                                let formatter = NumberFormatter()
                                let _ = (formatter.numberStyle = .currency)
                                detailRow("Baseline Cost", value: formatter.string(from: NSNumber(value: bc)))
                            }
                            if let bw = task.baselineWork {
                                detailRow("Baseline Work", value: DurationFormatting.formatSeconds(bw))
                            }
                            if let sv = task.startVarianceDays {
                                detailRow("Start Variance", value: "\(sv > 0 ? "+" : "")\(sv) days")
                            }
                            if let fv = task.finishVarianceDays {
                                detailRow("Finish Variance", value: "\(fv > 0 ? "+" : "")\(fv) days")
                            }
                            detailRow("Baseline Health", value: baselineHealthText)
                        }
                    }
                }

                // Progress
                GroupBox("Progress") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let pct = task.percentComplete {
                            HStack {
                                Text("% Complete")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 120, alignment: .trailing)
                                ProgressView(value: pct, total: 100)
                                    .frame(width: 100)
                                Text("\(Int(pct))%")
                                    .fontWeight(.medium)
                            }
                            .font(.caption)
                        }
                        if let pctWork = task.percentWorkComplete {
                            detailRow("% Work Complete", value: "\(Int(pctWork))%")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(2)
                }

                // Cost & Work
                if task.cost != nil || task.work != nil {
                    GroupBox("Cost & Work") {
                        detailGrid {
                            if let cost = task.cost {
                                let formatter = NumberFormatter()
                                let _ = (formatter.numberStyle = .currency)
                                detailRow("Cost", value: formatter.string(from: NSNumber(value: cost)))
                            }
                            if let work = task.work {
                                detailRow("Work", value: DurationFormatting.formatSeconds(work))
                            }
                        }
                    }
                }

                if !predecessorLinks.isEmpty || !successorLinks.isEmpty {
                    GroupBox("Relationship Inspector") {
                        VStack(alignment: .leading, spacing: 12) {
                            detailGrid {
                                detailRow("Predecessors", value: "\(predecessorLinks.count)")
                                detailRow("Successors", value: "\(successorLinks.count)")
                                detailRow("Blocking Predecessors", value: blockingPredecessors.isEmpty ? "None" : "\(blockingPredecessors.count)")
                                detailRow("Driving Successors", value: activeSuccessors.isEmpty ? "None" : "\(activeSuccessors.count)")
                                detailRow("Network Position", value: networkPositionText)
                                detailRow("Dependency Insight", value: dependencyInsightText)
                            }

                            if !predecessorLinks.isEmpty {
                                dependencySection("Predecessors", links: predecessorLinks)
                            }

                            if !successorLinks.isEmpty {
                                dependencySection("Successors", links: successorLinks)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(2)
                    }

                    GroupBox("Dependency Map") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Depth")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Depth", selection: $dependencyDepth) {
                                    Text("1").tag(1)
                                    Text("2").tag(2)
                                    Text("3").tag(3)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 160)
                                Spacer()
                            }

                            DependencyMapView(
                            currentTask: task,
                            predecessors: visiblePredecessorLinks,
                            successors: visibleSuccessorLinks,
                            onSelectTask: { uniqueID in
                                onSelectTask?(uniqueID)
                            }
                        )
                        .padding(.vertical, 2)
                        }
                    }
                }

                // Assigned Resources
                let taskAssignments = assignments.filter { $0.taskUniqueID == task.uniqueID }
                if !taskAssignments.isEmpty {
                    GroupBox("Assigned Resources") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(taskAssignments, id: \.id) { assignment in
                                let resourceName = resources
                                    .first(where: { $0.uniqueID == assignment.resourceUniqueID })?
                                    .name ?? "Resource \(assignment.resourceUniqueID ?? 0)"
                                HStack {
                                    Image(systemName: "person.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                    Text(resourceName)
                                    Spacer()
                                    if let units = assignment.assignmentUnits {
                                        Text("\(Int(units))%")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(2)
                    }
                }

                // Notes
                if let notes = task.notes, !notes.isEmpty {
                    GroupBox("Notes") {
                        Text(notes)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(2)
                    }
                }

                GroupBox("Review Notes") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Local notes saved on this Mac for review and reporting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: reviewNoteBinding)
                            .font(.caption)
                            .frame(minHeight: 120)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                        HStack {
                            Spacer()
                            if !reviewNoteBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button("Clear Review Note") {
                                    reviewNoteBinding.wrappedValue = ""
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(2)
                }

                // Custom Fields
                if let customFields = task.customFields, !customFields.isEmpty {
                    GroupBox("Custom Fields") {
                        detailGrid {
                            ForEach(customFields.keys.sorted(), id: \.self) { key in
                                if let val = customFields[key] {
                                    detailRow(key, value: val.displayString)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if task.summary == true {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                } else if task.milestone == true {
                    Image(systemName: "diamond.fill")
                        .foregroundStyle(.orange)
                }
                if task.critical == true {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            Text(task.displayName)
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                if task.milestone == true {
                    badge("Milestone", color: .orange)
                }
                if task.summary == true {
                    badge("Summary", color: .blue)
                }
                if task.critical == true {
                    badge("Critical", color: .red)
                }
                if (task.percentComplete ?? 0) >= 100 {
                    badge("Completed", color: .green)
                }
            }
        }
    }

    private func badge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Helpers

    private var taskTypeLabel: String {
        if task.milestone == true { return "Milestone" }
        if task.summary == true { return "Summary" }
        return task.type ?? "Task"
    }

    private var displayTypeLabel: String {
        if task.isDisplayMilestone { return "Milestone" }
        if task.summary == true { return "Summary Task" }
        return "Task"
    }

    private var predecessorLinks: [DependencyLink] {
        (task.predecessors ?? []).map { relation in
            DependencyLink(relation: relation, task: allTasks[relation.targetTaskUniqueID], direction: .predecessor, level: 1)
        }
    }

    private var successorLinks: [DependencyLink] {
        (task.successors ?? []).map { relation in
            DependencyLink(relation: relation, task: allTasks[relation.targetTaskUniqueID], direction: .successor, level: 1)
        }
    }

    private var visiblePredecessorLinks: [DependencyLink] {
        gatherDependencyLinks(from: task, direction: .predecessor, maxDepth: dependencyDepth)
    }

    private var visibleSuccessorLinks: [DependencyLink] {
        gatherDependencyLinks(from: task, direction: .successor, maxDepth: dependencyDepth)
    }

    private var breadcrumbTasks: [ProjectTask] {
        breadcrumbTaskIDs.compactMap { allTasks[$0] }
    }

    private var blockingPredecessors: [DependencyLink] {
        predecessorLinks.filter { !$0.isCompleted }
    }

    private var activeSuccessors: [DependencyLink] {
        successorLinks.filter { !$0.isCompleted }
    }

    private var baselineHealthText: String {
        let startVariance = task.startVarianceDays ?? 0
        let finishVariance = task.finishVarianceDays ?? 0
        let dominant = abs(finishVariance) >= abs(startVariance) ? finishVariance : startVariance

        if dominant == 0 {
            return "On baseline"
        }
        if dominant > 0 {
            return "Late versus baseline by \(dominant) days"
        }
        return "Ahead of baseline by \(abs(dominant)) days"
    }

    private var networkPositionText: String {
        switch (predecessorLinks.isEmpty, successorLinks.isEmpty) {
        case (true, true):
            return "Isolated"
        case (true, false):
            return "Starting point"
        case (false, true):
            return "End point"
        default:
            return "In-chain"
        }
    }

    private var dependencyInsightText: String {
        if !blockingPredecessors.isEmpty {
            let names = blockingPredecessors.prefix(2).map(\.displayName).joined(separator: ", ")
            return "Waiting on \(blockingPredecessors.count) predecessor(s): \(names)"
        }
        if !activeSuccessors.isEmpty {
            return "This task drives \(activeSuccessors.count) successor task(s)."
        }
        if predecessorLinks.isEmpty && successorLinks.isEmpty {
            return "No dependency links are recorded for this task."
        }
        return "Dependencies are connected and currently clear."
    }

    private var classificationNote: String? {
        if task.milestone == true && task.summary == true && !task.isDisplayMilestone {
            return "Excluded from milestone views because it is also a summary task with a duration span."
        }
        if task.milestone == true && !task.isDisplayMilestone {
            return "Raw milestone flag is set, but the task does not behave like a zero-duration checkpoint."
        }
        if task.summary == true {
            return "Summary tasks aggregate child tasks and are not treated as milestones."
        }
        return nil
    }

    private var reviewNoteBinding: Binding<String> {
        Binding(
            get: {
                reviewNotes[task.uniqueID] ?? ""
            },
            set: { newValue in
                var updated = reviewNotes
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    updated.removeValue(forKey: task.uniqueID)
                } else {
                    updated[task.uniqueID] = newValue
                }
                taskReviewNotesData = (try? JSONEncoder().encode(updated)) ?? Data()
            }
        )
    }

    private var reviewNotes: [Int: String] {
        ReviewNotesStore.decode(taskReviewNotesData)
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(breadcrumbTasks.enumerated()), id: \.element.uniqueID) { index, crumb in
                    Button {
                        onSelectBreadcrumb?(crumb.uniqueID)
                    } label: {
                        Text(crumb.displayName)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if index < breadcrumbTasks.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailGrid(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(2)
    }

    @ViewBuilder
    private func detailRow(_ label: String, value: String?) -> some View {
        if let value = value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .trailing)
                Text(value)
                    .textSelection(.enabled)
            }
            .font(.caption)
        }
    }

    private func boolLabel(_ value: Bool?) -> String? {
        guard let value else { return nil }
        return value ? "Yes" : "No"
    }

    @ViewBuilder
    private func dependencySection(_ title: String, links: [DependencyLink]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            ForEach(links) { link in
                dependencyRow(link)
                if link.id != links.last?.id {
                    Divider()
                }
            }
        }
    }

    private func dependencyRow(_ link: DependencyLink) -> some View {
        Button {
            if let uniqueID = link.task?.uniqueID {
                onSelectTask?(uniqueID)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(link.statusColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(link.taskIDText)
                            .fontWeight(.medium)
                        Text(link.displayName)
                    }
                    Text(link.detailText)
                        .foregroundStyle(.secondary)
                    if let scheduleText = link.scheduleText {
                        Text(scheduleText)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(link.statusLabel)
                        .foregroundStyle(link.statusColor)
                    if link.level > 1 {
                        Text("Depth \(link.level)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(link.task == nil)
    }

    private func gatherDependencyLinks(from rootTask: ProjectTask, direction: DependencyDirection, maxDepth: Int) -> [DependencyLink] {
        guard maxDepth > 0 else { return [] }

        var queue: [(task: ProjectTask, depth: Int)] = [(rootTask, 1)]
        var seen = Set<Int>([rootTask.uniqueID])
        var links: [DependencyLink] = []

        while let current = queue.first {
            queue.removeFirst()
            guard current.depth <= maxDepth else { continue }

            let relations: [TaskRelation] = {
                switch direction {
                case .predecessor:
                    return current.task.predecessors ?? []
                case .successor:
                    return current.task.successors ?? []
                }
            }()

            for relation in relations {
                guard let targetTask = allTasks[relation.targetTaskUniqueID] else { continue }
                let link = DependencyLink(
                    relation: relation,
                    task: targetTask,
                    direction: direction,
                    level: current.depth
                )
                if !links.contains(where: { $0.id == link.id && $0.level == link.level }) {
                    links.append(link)
                }
                if !seen.contains(targetTask.uniqueID) {
                    seen.insert(targetTask.uniqueID)
                    queue.append((targetTask, current.depth + 1))
                }
            }
        }

        return links
    }
}

private enum DependencyDirection {
    case predecessor
    case successor
}

private struct DependencyLink: Identifiable {
    let relation: TaskRelation
    let task: ProjectTask?
    let direction: DependencyDirection
    let level: Int

    var id: String { "\(direction)-\(relation.id)-\(task?.uniqueID ?? 0)" }

    var displayName: String {
        task?.displayName ?? "Task \(relation.targetTaskUniqueID)"
    }

    var taskIDText: String {
        task?.id.map(String.init) ?? "\(relation.targetTaskUniqueID)"
    }

    var isCompleted: Bool {
        task?.isCompleted ?? false
    }

    var statusLabel: String {
        guard let task else { return "Missing" }
        if task.isCompleted { return "Done" }
        if task.isOverdue { return "Overdue" }
        if task.isInProgress { return "In Progress" }
        return "Not Started"
    }

    var statusColor: Color {
        guard let task else { return .secondary }
        if task.isCompleted { return .green }
        if task.isOverdue { return .red }
        if task.isInProgress { return .blue }
        return .secondary
    }

    var detailText: String {
        let relationType = relation.type ?? "FS"
        let lagText = relation.lag.flatMap {
            $0 == 0 ? nil : "\(DurationFormatting.formatSeconds($0)) lag"
        }
        return ([relationType, lagText].compactMap { $0 }).joined(separator: " · ")
    }

    var scheduleText: String? {
        guard let task else { return nil }
        let startText = task.startDate.map { _ in DateFormatting.shortDate(task.start) } ?? "No start"
        let finishText = task.finishDate.map { _ in DateFormatting.shortDate(task.finish) } ?? "No finish"
        return "\(startText) to \(finishText)"
    }
}

private struct DependencyMapView: View {
    let currentTask: ProjectTask
    let predecessors: [DependencyLink]
    let successors: [DependencyLink]
    var onSelectTask: ((Int) -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            let horizontalInset: CGFloat = 20
            let availableWidth = max(220, geometry.size.width - horizontalInset * 2)
            let nodeWidth = min(420, availableWidth)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    dependencyGroup(title: "Predecessors", links: predecessors, direction: .predecessor, width: nodeWidth)

                    centerNode(width: min(360, nodeWidth * 0.82))

                    dependencyGroup(title: "Successors", links: successors, direction: .successor, width: nodeWidth)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, horizontalInset)
                .padding(.vertical, 4)
            }
        }
        .frame(minHeight: 320)
    }

    @ViewBuilder
    private func dependencyGroup(title: String, links: [DependencyLink], direction: DependencyDirection, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if links.isEmpty {
                dependencyNode(title: "None", subtitle: "No linked tasks", color: .secondary, width: width, action: nil)
            } else {
                let visibleLinks = Array(links.prefix(6))
                ForEach(visibleLinks) { link in
                    VStack(alignment: .center, spacing: 6) {
                        if direction == .successor {
                            dependencyArrow(systemName: "arrow.down")
                        }

                        dependencyNode(
                            title: link.displayName,
                            subtitle: "\(link.taskIDText) · \(link.statusLabel)\(link.level > 1 ? " · D\(link.level)" : "")",
                            color: link.statusColor,
                            width: width,
                            action: {
                                if let uniqueID = link.task?.uniqueID {
                                    onSelectTask?(uniqueID)
                                }
                            }
                        )

                        if direction == .predecessor && link.id != visibleLinks.last?.id {
                            dependencyArrow(systemName: "arrow.down")
                        }
                    }
                }
                if links.count > 6 {
                    Text("+\(links.count - 6) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func centerNode(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !predecessors.isEmpty {
                dependencyArrow(systemName: "arrow.down")
            }

            dependencyNode(
                title: currentTask.displayName,
                subtitle: currentTask.id.map { "Task \($0)" } ?? "Selected Task",
                color: currentTask.critical == true ? .red : (currentTask.isDisplayMilestone ? .orange : .accentColor),
                width: width,
                action: nil
            )

            if !successors.isEmpty {
                dependencyArrow(systemName: "arrow.down")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dependencyArrow(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 12)
    }

    @ViewBuilder
    private func dependencyNode(title: String, subtitle: String, color: Color, width: CGFloat, action: (() -> Void)?) -> some View {
        let node = VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(2)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )

        if let action {
            Button(action: action) {
                node
            }
            .buttonStyle(.plain)
        } else {
            node
        }
    }
}
