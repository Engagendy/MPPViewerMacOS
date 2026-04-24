import SwiftUI
import SwiftData

struct NativeResourcesEditorView: View {
    @Environment(\.modelContext) private var modelContext

    let planModel: PortfolioProjectPlan
    @Binding var navigateToTaskID: Int?
    @Binding var selectedNav: NavigationItem?

    @State private var reviewProject: ProjectModel
    @State private var selectedResourceID: Int?
    @State private var mode: NativeScreenMode = .review
    @State private var resourceImportSession: CSVResourceImportSession?
    @State private var lastResourceImportSession: CSVResourceImportSession?
    @State private var importReport: CSVImportReport?
    @State private var persistenceWorkItem: DispatchWorkItem?

    private var orderedResources: [PortfolioPlanResource] {
        planModel.resources.sorted { lhs, rhs in
            if lhs.legacyID == rhs.legacyID {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.legacyID < rhs.legacyID
        }
    }

    private var selectedResource: PortfolioPlanResource? {
        guard let selectedResourceID else { return nil }
        return orderedResources.first(where: { $0.legacyID == selectedResourceID })
    }

    private var calendarOptions: [ProjectCalendar] {
        reviewProject.calendars.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    init(planModel: PortfolioProjectPlan, navigateToTaskID: Binding<Int?>, selectedNav: Binding<NavigationItem?>) {
        self.planModel = planModel
        self._navigateToTaskID = navigateToTaskID
        self._selectedNav = selectedNav
        self._reviewProject = State(initialValue: planModel.projectModelForUI())
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Resources")
                        .font(.headline)
                    Text("(\(orderedResources.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                HStack(spacing: 8) {
                    Picker("Mode", selection: $mode) {
                        ForEach(NativeScreenMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .help("Switch between resource editing and read-only review")

                    Button {
                        resourceImportSession = CSVExporter.selectResourceImportSession()
                    } label: {
                        compactToolbarLabel("Import CSV/Excel", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(mode == .review)
                    .help("Import resources from CSV or Excel-compatible spreadsheet")

                    Menu {
                        Button("Export CSV Template") {
                            CSVExporter.exportResourceImportTemplateCSV()
                        }
                        Button("Export Excel Example") {
                            CSVExporter.exportResourceImportTemplateExcel()
                        }
                    } label: {
                        compactToolbarLabel("Templates", systemImage: "tablecells.badge.ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(mode == .review)
                    .help("Export resource import templates and spreadsheet examples")

                    Button {
                        addResource()
                    } label: {
                        compactToolbarLabel("Add Resource", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Create a new resource in the native plan")

                    Button(role: .destructive) {
                        deleteSelectedResource()
                    } label: {
                        compactToolbarLabel("Delete Resource", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(mode == .review || selectedResource == nil)
                    .help("Delete the selected resource and its assignments")

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            if mode == .edit {
                HSplitView {
                    List(orderedResources, selection: $selectedResourceID) { resource in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(resource.name.isEmpty ? "Unnamed Resource" : resource.name)
                                .fontWeight(.medium)
                            HStack(spacing: 8) {
                                Text(resource.type)
                                Text("\(Int(resource.maxUnits))%")
                                    .monospacedDigit()
                                if resource.standardRate > 0 {
                                    Text(currencyText(resource.standardRate) + "/h")
                                        .monospacedDigit()
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .tag(resource.legacyID)
                    }
                    .listStyle(.sidebar)
                    .frame(minWidth: 220, idealWidth: 260)

                    if let selectedResource {
                        resourceInspector(for: selectedResource)
                            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            "No Resource Selected",
                            systemImage: "person.2",
                            description: Text("Create or select a resource to edit staffing details and base calendar.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                ResourceSheetView(
                    resources: reviewProject.resources,
                    assignments: reviewProject.assignments,
                    calendars: reviewProject.calendars,
                    defaultCalendarID: reviewProject.properties.defaultCalendarUniqueId,
                    allTasks: reviewProject.tasksByID,
                    navigateToTaskID: $navigateToTaskID,
                    selectedNav: $selectedNav
                )
            }
        }
        .onAppear {
            refreshReviewProject()
            if selectedResourceID == nil {
                selectedResourceID = orderedResources.first?.legacyID
            }
        }
        .onChange(of: planModel.updatedAt) { _, _ in
            refreshReviewProject()
        }
        .sheet(item: $resourceImportSession) { session in
            ResourceCSVImportMappingSheet(
                session: session,
                onImport: { mappedSession in
                    let snapshot = planModel.editorSnapshotForUI()
                    if let result = CSVExporter.applyResourceImport(mappedSession, into: snapshot) {
                        planModel.update(from: result.plan)
                        planModel.updatedAt = Date()
                        try? modelContext.save()
                        refreshReviewProject()
                        selectedResourceID = result.plan.resources.last?.id
                        lastResourceImportSession = mappedSession
                        importReport = result.report
                    }
                    resourceImportSession = nil
                },
                onCancel: {
                    resourceImportSession = nil
                }
            )
        }
        .sheet(item: $importReport) { report in
            CSVImportReportSheet(
                report: report,
                secondaryActionTitle: lastResourceImportSession == nil ? nil : "Adjust Mapping",
                onSecondaryAction: reopenResourceImportMapping,
                onSelectIssue: selectImportedResourceIssue,
                onFixIssue: fixResourceImportIssue,
                onClose: {
                importReport = nil
                }
            )
        }
        .onAppear {
            if selectedResourceID == nil {
                selectedResourceID = orderedResources.first?.legacyID
            }
        }
        .onChange(of: orderedResources.map(\.legacyID)) { _, ids in
            if let selectedResourceID, ids.contains(selectedResourceID) {
                return
            }
            selectedResourceID = ids.first
        }
        .onDisappear {
            persistPlanImmediately()
        }
    }

    private func schedulePlanPersistence() {
        persistenceWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            Task { @MainActor in
                persist()
            }
        }
        persistenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func persistPlanImmediately() {
        persistenceWorkItem?.cancel()
        persist()
    }

    @MainActor
    private func persist() {
        planModel.updatedAt = Date()
        planModel.refreshPortfolioMetrics()
        try? modelContext.save()
        refreshReviewProject()
    }

    private func reopenResourceImportMapping() {
        guard let session = lastResourceImportSession else { return }
        importReport = nil
        DispatchQueue.main.async {
            resourceImportSession = session
        }
    }

    private func selectImportedResourceIssue(_ issue: CSVImportIssue) {
        guard let targetID = issue.targetID, orderedResources.contains(where: { $0.legacyID == targetID }) else { return }
        selectedResourceID = targetID
        importReport = nil
    }

    private func fixResourceImportIssue(_ issue: CSVImportIssue) {
        guard let fixAction = issue.fixAction else { return }

        switch fixAction {
        case let .createResourceCalendar(name, resourceID):
            let calendarID = ensureCalendar(named: name)
            if let resource = orderedResources.first(where: { $0.legacyID == resourceID }) {
                resource.calendarUniqueID = calendarID
                selectedResourceID = resourceID
                schedulePlanPersistence()
                removeIssueFromReport(issue.id)
            }
        default:
            break
        }
    }

    private func ensureCalendar(named name: String) -> Int {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let existing = planModel.calendars
            .first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }) {
            return existing.legacyID
        }

        let calendar = PortfolioPlanCalendar(nativeCalendar: planModel.makeCalendarForUI(name: name))
        calendar.plan = planModel
        planModel.calendars.append(calendar)
        planModel.updatedAt = Date()
        try? modelContext.save()
        refreshReviewProject()
        return calendar.legacyID
    }

    private func removeIssueFromReport(_ issueID: UUID) {
        guard let report = importReport else { return }
        let remaining = report.issues.filter { $0.id != issueID }
        importReport = CSVImportReport(title: report.title, summaryLines: report.summaryLines, issues: remaining)
    }

    private func compactToolbarLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .font(.caption)
        .frame(width: 108, alignment: .leading)
    }

    @ViewBuilder
    private func resourceInspector(for resource: PortfolioPlanResource) -> some View {
        let resourceAssignments = assignments(for: resource.legacyID)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Resource Basics") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Name", text: binding(for: resource, keyPath: \.name))
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 12) {
                            TextField("Type", text: binding(for: resource, keyPath: \.type))
                                .textFieldStyle(.roundedBorder)
                            TextField("Initials", text: binding(for: resource, keyPath: \.initials))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }

                        HStack(spacing: 12) {
                            TextField("Group", text: binding(for: resource, keyPath: \.group))
                                .textFieldStyle(.roundedBorder)
                            TextField("Email", text: binding(for: resource, keyPath: \.emailAddress))
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Max Units")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: binding(for: resource, keyPath: \.maxUnits, minimum: 0), in: 0 ... 300, step: 25)
                            Text("\(Int(resource.maxUnits))%")
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        Toggle("Active", isOn: binding(for: resource, keyPath: \.active))

                        Picker("Base Calendar", selection: binding(for: resource, keyPath: \.calendarUniqueID)) {
                            Text("Default Project Calendar").tag(Int?.none)
                            ForEach(calendarOptions, id: \.uniqueID) { calendar in
                                Text(calendar.name ?? "Calendar").tag(Optional(calendar.uniqueID))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Notes") {
                    TextEditor(text: binding(for: resource, keyPath: \.notes))
                        .frame(minHeight: 120)
                }

                GroupBox("Financials") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Standard Rate / Hour")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                StableDecimalTextField(title: "0", text: decimalTextBinding(resource, keyPath: \.standardRate))
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Overtime Rate / Hour")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                StableDecimalTextField(title: "0", text: decimalTextBinding(resource, keyPath: \.overtimeRate))
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Cost Per Use")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                StableDecimalTextField(title: "0", text: decimalTextBinding(resource, keyPath: \.costPerUse))
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Accrue At")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Accrue At", selection: accrueAtBinding(for: resource)) {
                                    Text("Start").tag("start")
                                    Text("Prorated").tag("prorated")
                                    Text("End").tag("end")
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Assignments") {
                    VStack(alignment: .leading, spacing: 10) {
                        if resourceAssignments.isEmpty {
                            Text("This resource is not assigned to any tasks yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(resourceAssignments) { assignment in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(taskName(for: assignment.taskID))
                                            .fontWeight(.medium)
                                        Text("Task #\(assignment.taskID)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(Int(assignment.units))%")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }

    private func addResource() {
        let nativeResource = planModel.makeResourceForUI()
        let resource = PortfolioPlanResource(nativeResource: nativeResource)
        resource.plan = planModel
        planModel.resources.append(resource)
        selectedResourceID = resource.legacyID
        schedulePlanPersistence()
    }

    private func deleteSelectedResource() {
        guard let selectedResource else { return }
        let removedID = selectedResource.legacyID

        for task in planModel.tasks {
            for assignment in task.assignments where assignment.resourceLegacyID == removedID {
                assignment.resourceLegacyID = nil
                assignment.resource = nil
            }
        }

        modelContext.delete(selectedResource)
        selectedResourceID = orderedResources.first(where: { $0.legacyID != removedID })?.legacyID
        schedulePlanPersistence()
    }

    private func assignments(for resourceID: Int) -> [NativePlanAssignment] {
        planModel.tasks
            .flatMap(\.assignments)
            .filter { $0.resourceLegacyID == resourceID }
            .map { $0.asNativeAssignment() }
    }

    private func taskName(for taskID: Int) -> String {
        planModel.tasks.first(where: { $0.legacyID == taskID })?.name ?? "Unknown Task"
    }

    private func currencyText(_ value: Double) -> String {
        CurrencyFormatting.string(from: value, maximumFractionDigits: value.rounded() == value ? 0 : 2, minimumFractionDigits: 0)
    }

    private func refreshReviewProject() {
        reviewProject = planModel.projectModelForUI()
    }

    private func binding<T>(for resource: PortfolioPlanResource, keyPath: ReferenceWritableKeyPath<PortfolioPlanResource, T>) -> Binding<T> {
        Binding(
            get: { resource[keyPath: keyPath] },
            set: { newValue in
                resource[keyPath: keyPath] = newValue
                schedulePlanPersistence()
            }
        )
    }

    private func binding(for resource: PortfolioPlanResource, keyPath: ReferenceWritableKeyPath<PortfolioPlanResource, Double>, minimum: Double) -> Binding<Double> {
        Binding(
            get: { resource[keyPath: keyPath] },
            set: { newValue in
                resource[keyPath: keyPath] = max(minimum, newValue)
                schedulePlanPersistence()
            }
        )
    }

    private func decimalTextBinding(_ resource: PortfolioPlanResource, keyPath: ReferenceWritableKeyPath<PortfolioPlanResource, Double>) -> Binding<String> {
        Binding(
            get: {
                let current = resource[keyPath: keyPath]
                if current.rounded() == current {
                    return String(Int(current))
                }
                return String(format: "%.2f", current)
            },
            set: { newValue in
                let normalized = newValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: ",", with: "")
                    .filter { $0.isNumber || $0 == "." }
                resource[keyPath: keyPath] = max(0, Double(normalized) ?? 0)
                schedulePlanPersistence()
            }
        )
    }

    private func accrueAtBinding(for resource: PortfolioPlanResource) -> Binding<String> {
        Binding(
            get: { resource.accrueAtValue },
            set: { newValue in
                let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                switch normalized {
                case "start", "prorated", "end":
                    resource.accrueAt = normalized
                default:
                    resource.accrueAt = nil
                }
                schedulePlanPersistence()
            }
        )
    }
}

private enum NativeScreenMode: String, CaseIterable, Identifiable {
    case edit = "Edit"
    case review = "Review"

    var id: String { rawValue }
}
