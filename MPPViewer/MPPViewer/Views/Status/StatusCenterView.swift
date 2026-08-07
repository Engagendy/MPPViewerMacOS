import SwiftUI
import SwiftData
import Combine
import AppKit
import UniformTypeIdentifiers

struct StatusCenterView: View {
    @Environment(\.modelContext) private var modelContext

    let planModel: PortfolioProjectPlan
    let project: ProjectModel

    @State private var derivedContent: StatusCenterDerivedContent
    @State private var selectedTaskID: Int?
    @State private var filter: StatusTaskFilter = .attention
    @State private var searchText = ""

    private var workTasks: [ProjectTask] {
        derivedContent.workTasks
    }

    private var statusMetrics: EVMMetrics {
        derivedContent.statusMetrics
    }

    private var overdueCount: Int {
        derivedContent.overdueCount
    }

    private var inProgressCount: Int {
        derivedContent.inProgressCount
    }

    private var missingActualCount: Int {
        derivedContent.missingActualCount
    }

    private var filteredTasks: [ProjectTask] {
        derivedContent.filteredTasks
    }

    private var selectedProjectTask: ProjectTask? {
        guard let selectedTaskID else { return nil }
        return project.tasksByID[selectedTaskID]
    }

    private var nativeAssignments: [NativePlanAssignment] {
        planModel.nativeAssignmentsForUI
    }

    private var nativeResources: [NativePlanResource] {
        planModel.nativeResourcesForUI
    }

    private var nativeStatusSnapshots: [NativeStatusSnapshot] {
        planModel.nativeStatusSnapshotsForUI
    }

    private var currentStatusDate: Date {
        planModel.statusDate
    }

    private var selectedAssignments: [NativePlanAssignment] {
        guard let selectedTaskID else { return [] }
        return nativeAssignments
            .filter { $0.taskID == selectedTaskID }
            .sorted { $0.id < $1.id }
    }

    private var topScheduleSlips: [ProjectTask] {
        derivedContent.topScheduleSlips
    }

    private var topCostOverruns: [ProjectTask] {
        derivedContent.topCostOverruns
    }

    private var topOvertimeDrivers: [StatusOvertimeDriver] {
        derivedContent.topOvertimeDrivers
    }

    init(planModel: PortfolioProjectPlan, project: ProjectModel) {
        self.planModel = planModel
        self.project = project
        self._derivedContent = State(
            initialValue: StatusCenterDerivedContent.build(
                project: project,
                assignments: planModel.nativeAssignmentsForUI,
                resources: planModel.nativeResourcesForUI,
                statusDate: planModel.statusDate,
                snapshots: planModel.nativeStatusSnapshotsForUI,
                filter: .attention,
                searchText: ""
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
            Divider()
            metricsStrip
            Divider()

            HStack(spacing: 0) {
                taskListPane
                    .frame(minWidth: 420, idealWidth: 540, maxWidth: 680)

                Divider()

                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear {
            refreshDerivedContent()
            if selectedTaskID == nil {
                selectedTaskID = filteredTasks.first?.uniqueID ?? workTasks.first?.uniqueID
            }
        }
        .onChange(of: planModel.updatedAt) { _, _ in
            refreshDerivedContent()
        }
        .onChange(of: planModel.tasks.map(\.legacyID)) { _, ids in
            guard !ids.isEmpty else {
                selectedTaskID = nil
                return
            }

            if let selectedTaskID, ids.contains(selectedTaskID) {
                return
            }

            selectedTaskID = ids.first
        }
        .onChange(of: filter) { _, _ in
            refreshDerivedContent()
            if let selectedTaskID, filteredTasks.contains(where: { $0.uniqueID == selectedTaskID }) {
                return
            }
            selectedTaskID = filteredTasks.first?.uniqueID
        }
        .onChange(of: searchText) { _, _ in
            refreshDerivedContent()
            if let selectedTaskID, filteredTasks.contains(where: { $0.uniqueID == selectedTaskID }) {
                return
            }
            selectedTaskID = filteredTasks.first?.uniqueID
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func persistStatusStoreChanges(refreshMetrics: Bool = true) {
        planModel.updatedAt = Date()
        if refreshMetrics {
            planModel.refreshPortfolioMetrics()
        }
        modelContext.saveReportingFailures()
        refreshDerivedContent()
    }

    private func withStatusTask(_ taskID: Int, _ update: (PortfolioPlanTask) -> Void) {
        guard let task = planModel.tasks.first(where: { $0.legacyID == taskID }) else { return }
        update(task)
        persistStatusStoreChanges()
    }

    private func withStatusAssignment(_ assignmentID: Int, _ update: (PortfolioPlanAssignment) -> Void) {
        guard let assignment = planModel.tasks
            .flatMap(\.assignments)
            .first(where: { $0.legacyID == assignmentID }) else { return }
        update(assignment)
        persistStatusStoreChanges()
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Status Center")
                        .font(.title2.weight(.semibold))
                        .fixedSize()
                    Text("Update actuals, variance, and earned value as of the current status date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                FinancialTermsButton()
                    .fixedSize()
            }

            // Controls reflow as whole units on narrow windows instead of
            // squeezing the segmented filter and truncating buttons.
            FlowLayout(spacing: 12, lineSpacing: 10) {
                Picker("Filter", selection: $filter) {
                    ForEach(StatusTaskFilter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 440)

                TextField("Search Tasks", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                CalendarDatePicker(date: statusDateBinding, isCompact: true)
                    .fixedSize()
                    .help("Sets the control date used by earned value and variance calculations.")

                Button("Today") {
                    statusDateBinding.wrappedValue = Calendar.current.startOfDay(for: Date())
                }
                .help("Move the status date to today.")

                Button("Apply Status Defaults") {
                    applyStatusDefaults()
                }
                .help("Fill missing actual dates for tasks that have already started or finished by the current status date.")

                Button("Capture Snapshot") {
                    captureStatusSnapshot()
                }
                .help("Save the current status date, EVM state, and sprint position as a reporting-period snapshot.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var metricsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                statusMetricCard(title: "In Progress", value: "\(inProgressCount)", tone: .blue)
                statusMetricCard(title: "Overdue", value: "\(overdueCount)", tone: overdueCount > 0 ? .red : .secondary)
                statusMetricCard(title: "Missing Actuals", value: "\(missingActualCount)", tone: missingActualCount > 0 ? .orange : .secondary)
                statusMetricCard(title: "BAC", value: currencyText(statusMetrics.bac), tone: .primary)
                statusMetricCard(title: "AC", value: currencyText(statusMetrics.ac), tone: .primary)
                statusMetricCard(title: "CPI", value: ratioText(statusMetrics.cpi), tone: statusMetrics.cpi >= 1 ? .green : .orange)
                statusMetricCard(title: "SPI", value: ratioText(statusMetrics.spi), tone: statusMetrics.spi >= 1 ? .green : .orange)
                statusMetricCard(title: "EAC", value: currencyText(statusMetrics.eac), tone: .primary)
                statusMetricCard(title: "VAC", value: currencyText(statusMetrics.vac), tone: statusMetrics.vac >= 0 ? .green : .red)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var taskListPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Task Status")
                    .font(.headline)
                Text("(\(filteredTasks.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            HStack(spacing: 0) {
                listHeader("Task", width: 220, alignment: .leading)
                listHeader("%", width: 48)
                listHeader("Actual Start", width: 94)
                listHeader("Actual Finish", width: 94)
                listHeader("Cost Δ", width: 82)
                listHeader("Slip", width: 62)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.thinMaterial)

            Divider()

            List(selection: $selectedTaskID) {
                ForEach(filteredTasks, id: \.uniqueID) { task in
                    Button {
                        selectStatusTask(task.uniqueID)
                    } label: {
                        HStack(spacing: 0) {
                            taskCell(task: task)
                            numericCell(task.percentComplete.map { "\(Int($0))%" } ?? "0%", width: 48)
                            numericCell(task.actualStart.map(DateFormatting.shortDate) ?? "Missing", width: 94, tint: task.actualStart == nil && (task.percentComplete ?? 0) > 0 ? .orange : .secondary)
                            numericCell(task.actualFinish.map(DateFormatting.shortDate) ?? "Missing", width: 94, tint: task.actualFinish == nil && task.isCompleted ? .orange : .secondary)
                            numericCell(costVarianceText(for: task), width: 82, tint: costVarianceColor(for: task))
                            numericCell(slipText(for: task), width: 62, tint: slipColor(for: task))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight()
                    .tag(task.uniqueID)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            }
            .listStyle(.plain)
        }
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let task = selectedProjectTask {
                    taskStatusEditor(task: task)
                    assignmentStatusEditor(task: task)
                } else {
                    Text("Select a task from the left to update status, actuals, and progress.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top)
                }

                varianceDashboard
                snapshotHistoryPanel
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func taskStatusEditor(task: ProjectTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.displayName)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 8) {
                        if let wbs = task.wbs {
                            Text(wbs)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }

                        statusBadge(for: task)
                    }
                }

                Spacer()
            }

            GroupBox("Task Update") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Actual Start")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            CalendarDatePicker(date: actualStartBinding(for: task.uniqueID), isCompact: true)
                            HStack(spacing: 8) {
                                Button("Use Scheduled") {
                                    setActualStart(for: task.uniqueID, to: task.startDate ?? currentStatusDate)
                                }
                                Button("Clear") {
                                    setActualStart(for: task.uniqueID, to: nil)
                                }
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Actual Finish")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            CalendarDatePicker(date: actualFinishBinding(for: task.uniqueID), isCompact: true)
                            HStack(spacing: 8) {
                                Button("Use Scheduled") {
                                    setActualFinish(for: task.uniqueID, to: task.finishDate ?? currentStatusDate)
                                }
                                Button("Clear") {
                                    setActualFinish(for: task.uniqueID, to: nil)
                                }
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("% Complete")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("0", text: percentCompleteBinding(for: task.uniqueID))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 84)
                            Text("Statused progress")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Actual Cost")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            StableDecimalTextField(title: "0", text: actualCostBinding(for: task.uniqueID))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                            Text("Override only if needed")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Status Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: notesBinding(for: task.uniqueID))
                            .font(.body)
                            .frame(minHeight: 72)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                            )
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("Variance Snapshot") {
                VStack(alignment: .leading, spacing: 8) {
                    statusFactRow(label: "Baseline", value: baselineRangeText(for: task))
                    statusFactRow(label: "Current", value: currentRangeText(for: task))
                    statusFactRow(label: "Planned Value", value: currencyText(task.bcws ?? EVMCalculator.compute(for: task, statusDate: currentStatusDate).pv))
                    statusFactRow(label: "Earned Value", value: currencyText(task.bcwp ?? EVMCalculator.compute(for: task, statusDate: currentStatusDate).ev))
                    statusFactRow(label: "Actual Cost", value: currencyText(task.acwp ?? EVMCalculator.compute(for: task, statusDate: currentStatusDate).ac))
                    statusFactRow(label: "Cost Variance", value: costVarianceText(for: task), tint: costVarianceColor(for: task))
                    statusFactRow(label: "Schedule Variance", value: currencyText(EVMCalculator.compute(for: task, statusDate: currentStatusDate).sv), tint: EVMCalculator.compute(for: task, statusDate: currentStatusDate).sv >= 0 ? .green : .red)
                }
                .padding(.top, 4)
            }
        }
    }

    private func assignmentStatusEditor(task: ProjectTask) -> some View {
        GroupBox("Assignment Updates") {
            VStack(alignment: .leading, spacing: 10) {
                if selectedAssignments.isEmpty {
                    Text("No assignments on this task yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectedAssignments) { assignment in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(resourceName(for: assignment))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("Units \(Int(assignment.units))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 12) {
                                assignmentField(title: "Actual (h)", text: assignmentHoursBinding(for: assignment.id, keyPath: \.actualWorkSeconds))
                                assignmentField(title: "Remaining (h)", text: assignmentHoursBinding(for: assignment.id, keyPath: \.remainingWorkSeconds))
                                assignmentField(title: "OT (h)", text: assignmentHoursBinding(for: assignment.id, keyPath: \.overtimeWorkSeconds))
                                Spacer()
                                Text(assignmentCostSummary(for: assignment))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.primary.opacity(0.03))
                        )
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var varianceDashboard: some View {
        GroupBox("Control Radar") {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Top Schedule Slips")
                        .font(.headline)
                    if topScheduleSlips.isEmpty {
                        Text("No slipped tasks against the current baseline.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(topScheduleSlips, id: \.uniqueID) { task in
                            radarRow(
                                title: task.displayName,
                                detail: slipText(for: task),
                                tint: .red,
                                action: { selectStatusTask(task.uniqueID) }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Top Cost Overruns")
                        .font(.headline)
                    if topCostOverruns.isEmpty {
                        Text("No tasks are exceeding baseline cost.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(topCostOverruns, id: \.uniqueID) { task in
                            radarRow(
                                title: task.displayName,
                                detail: costVarianceText(for: task),
                                tint: .orange,
                                action: { selectStatusTask(task.uniqueID) }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Overtime Drivers")
                        .font(.headline)
                    if topOvertimeDrivers.isEmpty {
                        Text("No explicit overtime has been statused yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(topOvertimeDrivers.enumerated()), id: \.offset) { _, item in
                            radarRow(
                                title: resourceName(for: item.assignment),
                                detail: hoursText(item.assignment.overtimeWorkSeconds),
                                tint: .purple,
                                action: { selectStatusTask(item.assignment.taskID) }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.top, 4)
        }
    }

    private var snapshotHistoryPanel: some View {
        GroupBox("Status History") {
            VStack(alignment: .leading, spacing: 10) {
                if nativeStatusSnapshots.isEmpty {
                    Text("No status snapshots captured yet. Use `Capture Snapshot` to save reporting periods for trend and sprint review.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(derivedContent.sortedSnapshots.prefix(8), id: \.id) { snapshot in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(snapshot.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text("Status Date \(DateFormatting.simpleDate(snapshot.statusDate))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Use Date") {
                                    statusDateBinding.wrappedValue = snapshot.statusDate
                                }
                                .buttonStyle(.accessoryBar)
                            }

                            HStack(spacing: 18) {
                                snapshotMetric("BAC", currencyText(snapshot.bac))
                                snapshotMetric("EV", currencyText(snapshot.ev))
                                snapshotMetric("AC", currencyText(snapshot.ac))
                                snapshotMetric("CPI", ratioText(snapshot.cpi))
                                snapshotMetric("SPI", ratioText(snapshot.spi))
                                snapshotMetric("VAC", currencyText(snapshot.vac))
                            }

                            if !snapshot.sprintSnapshots.isEmpty {
                                Text(snapshot.sprintSnapshots.map { "\($0.sprintName): \($0.completedPoints)/\($0.committedPoints) pts" }.joined(separator: "   "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !snapshot.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(snapshot.notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func radarRow(title: String, detail: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(tint)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .hoverHighlight()
    }

    private func refreshDerivedContent() {
        PerformanceMonitor.measure("StatusCenter.RefreshDerived") {
            derivedContent = StatusCenterDerivedContent.build(
                project: project,
                assignments: nativeAssignments,
                resources: nativeResources,
                statusDate: currentStatusDate,
                snapshots: nativeStatusSnapshots,
                filter: filter,
                searchText: searchText
            )
        }
    }

    private func selectStatusTask(_ taskID: Int?) {
        guard let taskID else { return }
        PerformanceMonitor.mark("StatusCenter.SelectTask", message: "task \(taskID)")
        selectedTaskID = taskID
    }

    private func listHeader(_ title: String, width: CGFloat, alignment: Alignment = .center) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
    }

    private func taskCell(task: ProjectTask) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(taskStatusColor(for: task))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.displayName)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if let wbs = task.wbs {
                        Text(wbs)
                    }
                    Text(statusText(for: task))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .frame(width: 220, alignment: .leading)
    }

    private func numericCell(_ value: String, width: CGFloat, tint: Color = .secondary) -> some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(tint)
            .frame(width: width)
    }

    private func statusMetricCard(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(tone)
        }
        .frame(width: 108, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func statusBadge(for task: ProjectTask) -> some View {
        Text(statusText(for: task))
            .font(.caption.weight(.semibold))
            .foregroundStyle(taskStatusColor(for: task))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(taskStatusColor(for: task).opacity(0.14))
            )
    }

    private func statusFactRow(label: String, value: String, tint: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(tint)
        }
        .font(.callout)
    }

    private func assignmentField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("0", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 88)
        }
    }

    private var statusDateBinding: Binding<Date> {
        Binding(
            get: { planModel.statusDate },
            set: { newValue in
                let normalized = Calendar.current.startOfDay(for: newValue)
                guard planModel.statusDate != normalized else { return }
                planModel.statusDate = normalized
                persistStatusStoreChanges()
            }
        )
    }

    private func captureStatusSnapshot() {
        PerformanceMonitor.measure("StatusCenter.CaptureSnapshot") {
            var snapshotPlan = planModel.asNativePlan()
            snapshotPlan.captureStatusSnapshot()
            planModel.update(from: snapshotPlan)
            persistStatusStoreChanges(refreshMetrics: true)
        }
    }

    private func percentCompleteBinding(for taskID: Int) -> Binding<String> {
        Binding(
            get: {
                guard let task = planModel.tasks.first(where: { $0.legacyID == taskID }) else { return "" }
                return "\(Int(task.percentComplete.rounded()))"
            },
            set: { newValue in
                let parsed = Double(newValue.filter { $0.isNumber || $0 == "." }) ?? 0
                withStatusTask(taskID) { task in
                    task.percentComplete = min(max(parsed, 0), 100)
                    if task.percentComplete > 0, task.actualStartDate == nil {
                        task.actualStartDate = min(task.startDate, planModel.statusDate)
                    }
                    if task.percentComplete >= 100, task.actualFinishDate == nil {
                        task.actualFinishDate = min(task.finishDate, planModel.statusDate)
                    }
                }
            }
        )
    }

    private func actualCostBinding(for taskID: Int) -> Binding<String> {
        Binding(
            get: {
                guard let task = planModel.tasks.first(where: { $0.legacyID == taskID }) else { return "" }
                return task.actualCost.map(decimalText) ?? ""
            },
            set: { newValue in
                withStatusTask(taskID) { task in
                    task.actualCost = parseDecimalInput(newValue)
                }
            }
        )
    }

    private func notesBinding(for taskID: Int) -> Binding<String> {
        Binding(
            get: {
                guard let task = planModel.tasks.first(where: { $0.legacyID == taskID }) else { return "" }
                return task.notes
            },
            set: { newValue in
                withStatusTask(taskID) { task in
                    task.notes = newValue
                }
            }
        )
    }

    private func actualStartBinding(for taskID: Int) -> Binding<Date> {
        Binding(
            get: {
                guard let task = planModel.tasks.first(where: { $0.legacyID == taskID }) else { return planModel.statusDate }
                return task.actualStartDate ?? task.startDate
            },
            set: { newValue in
                setActualStart(for: taskID, to: newValue)
            }
        )
    }

    private func actualFinishBinding(for taskID: Int) -> Binding<Date> {
        Binding(
            get: {
                guard let task = planModel.tasks.first(where: { $0.legacyID == taskID }) else { return planModel.statusDate }
                return task.actualFinishDate ?? task.finishDate
            },
            set: { newValue in
                setActualFinish(for: taskID, to: newValue)
            }
        )
    }

    private func assignmentHoursBinding(for assignmentID: Int, keyPath: WritableKeyPath<NativePlanAssignment, Int?>) -> Binding<String> {
        Binding(
            get: {
                guard let assignment = planModel.tasks
                    .flatMap(\.assignments)
                    .first(where: { $0.legacyID == assignmentID }) else { return "" }
                let native = assignment.asNativeAssignment(taskLegacyID: assignment.taskLegacyID)
                return hoursText(native[keyPath: keyPath])
            },
            set: { newValue in
                withStatusAssignment(assignmentID) { assignment in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    let seconds: Int?
                    if trimmed.isEmpty {
                        seconds = nil
                    } else if let value = Double(trimmed) {
                        seconds = max(0, Int(value * 3600))
                    } else {
                        seconds = nil
                    }
                    switch keyPath {
                    case \NativePlanAssignment.actualWorkSeconds:
                        assignment.actualWorkSeconds = seconds
                    case \NativePlanAssignment.remainingWorkSeconds:
                        assignment.remainingWorkSeconds = seconds
                    default:
                        assignment.overtimeWorkSeconds = seconds
                    }
                }
            }
        )
    }

    private func setActualStart(for taskID: Int, to date: Date?) {
        PerformanceMonitor.measure("StatusCenter.SetActualStart") {
            let normalized = date.map { Calendar.current.startOfDay(for: $0) }
            withStatusTask(taskID) { task in
                task.actualStartDate = normalized
                if let normalized, let finish = task.actualFinishDate, finish < normalized {
                    task.actualFinishDate = normalized
                }
            }
        }
    }

    private func setActualFinish(for taskID: Int, to date: Date?) {
        PerformanceMonitor.measure("StatusCenter.SetActualFinish") {
            let normalized = date.map { Calendar.current.startOfDay(for: $0) }
            withStatusTask(taskID) { task in
                if let normalized, let start = task.actualStartDate, normalized < start {
                    task.actualFinishDate = start
                } else {
                    task.actualFinishDate = normalized
                }
                if task.actualFinishDate != nil, task.percentComplete < 100 {
                    task.percentComplete = 100
                }
            }
        }
    }

    private func applyStatusDefaults() {
        PerformanceMonitor.measure("StatusCenter.ApplyDefaults") {
            let statusDate = Calendar.current.startOfDay(for: planModel.statusDate)
            var didChange = false
            for task in planModel.tasks {
                if task.percentComplete > 0, task.actualStartDate == nil {
                    task.actualStartDate = min(task.startDate, statusDate)
                    didChange = true
                }

                if task.percentComplete >= 100, task.actualFinishDate == nil {
                    task.actualFinishDate = min(task.finishDate, statusDate)
                    didChange = true
                }

                if let actualStart = task.actualStartDate, actualStart > statusDate {
                    task.actualStartDate = statusDate
                    didChange = true
                }

                if let actualFinish = task.actualFinishDate, actualFinish > statusDate {
                    task.actualFinishDate = statusDate
                    didChange = true
                }
            }

            guard didChange else { return }
            persistStatusStoreChanges()
        }
    }

    private func taskStatusNeedsAttention(_ task: ProjectTask) -> Bool {
        isOverdue(task)
            || task.finishVarianceDays ?? 0 > 0
            || costVarianceValue(for: task) > 0
            || ((task.percentComplete ?? 0) > 0 && task.actualStart == nil)
            || (task.isCompleted && task.actualFinish == nil)
    }

    private func costVarianceValue(for task: ProjectTask) -> Double {
        (task.actualCost ?? 0) - (task.baselineCost ?? task.cost ?? 0)
    }

    private func costVarianceText(for task: ProjectTask) -> String {
        let variance = costVarianceValue(for: task)
        guard variance != 0 else { return "On plan" }
        return currencyText(variance)
    }

    private func costVarianceColor(for task: ProjectTask) -> Color {
        let variance = costVarianceValue(for: task)
        if variance > 0 { return .red }
        if variance < 0 { return .green }
        return .secondary
    }

    private func slipText(for task: ProjectTask) -> String {
        let days = task.finishVarianceDays ?? task.startVarianceDays ?? 0
        if days == 0 { return "On time" }
        return "\(days > 0 ? "+" : "")\(days)d"
    }

    private func slipColor(for task: ProjectTask) -> Color {
        let days = task.finishVarianceDays ?? task.startVarianceDays ?? 0
        if days > 0 { return .red }
        if days < 0 { return .green }
        return .secondary
    }

    private func baselineRangeText(for task: ProjectTask) -> String {
        let start = task.baselineStartDate.map(DateFormatting.simpleDate) ?? "?"
        let finish = task.baselineFinishDate.map(DateFormatting.simpleDate) ?? "?"
        return "\(start) -> \(finish)"
    }

    private func currentRangeText(for task: ProjectTask) -> String {
        let start = task.startDate.map(DateFormatting.simpleDate) ?? "?"
        let finish = task.finishDate.map(DateFormatting.simpleDate) ?? "?"
        return "\(start) -> \(finish)"
    }

    private func statusText(for task: ProjectTask) -> String {
        if task.isCompleted { return "Complete" }
        if isOverdue(task) { return "Overdue" }
        if task.isInProgress { return "In Progress" }
        return "Not Started"
    }

    private func taskStatusColor(for task: ProjectTask) -> Color {
        if task.isCompleted { return .green }
        if isOverdue(task) { return .red }
        if task.isInProgress { return .blue }
        return .secondary
    }

    private func isOverdue(_ task: ProjectTask) -> Bool {
        guard !task.isCompleted, let finishDate = task.finishDate else { return false }
        return finishDate < planModel.statusDate
    }

    private func resourceName(for assignment: NativePlanAssignment) -> String {
        if let resourceID = assignment.resourceID {
            if let name = planModel.resources.first(where: { $0.legacyID == resourceID })?.name,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
        }
        return "Unassigned"
    }

    private func assignmentCostSummary(for assignment: NativePlanAssignment) -> String {
        guard let projectAssignment = project.assignments.first(where: { $0.uniqueID == assignment.id }) else {
            return "No rolled cost"
        }
        return projectAssignment.cost.map(currencyText) ?? "No rolled cost"
    }

    private func hoursText(_ seconds: Int?) -> String {
        guard let seconds else { return "" }
        let hours = Double(seconds) / 3600
        return abs(hours.rounded() - hours) < 0.01 ? "\(Int(hours.rounded()))" : String(format: "%.1f", hours)
    }

    private func decimalText(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private func parseDecimalInput(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: ",", with: "")
            .filter { $0.isNumber || $0 == "." }
        return Double(normalized)
    }

    private func currencyText(_ value: Double) -> String {
        CurrencyFormatting.string(
            from: value,
            currencyCode: project.properties.currencyCode ?? "USD",
            currencySymbol: project.properties.currencySymbol ?? "$",
            maximumFractionDigits: 0,
            minimumFractionDigits: 0
        )
    }

    private func ratioText(_ value: Double) -> String {
        value == 0 ? "0.00" : String(format: "%.2f", value)
    }

    private func snapshotMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }
}

enum StatusTaskFilter: String, CaseIterable, Identifiable {
    case attention = "Needs Attention"
    case all = "All"
    case inProgress = "In Progress"
    case overdue = "Overdue"
    case missingActuals = "Missing Actuals"

    var id: String { rawValue }
}
