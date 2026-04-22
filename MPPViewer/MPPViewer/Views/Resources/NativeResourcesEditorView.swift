import SwiftUI

struct NativeResourcesEditorView: View {
    @Binding var plan: NativeProjectPlan
    @Binding var navigateToTaskID: Int?
    @Binding var selectedNav: NavigationItem?

    @State private var selectedResourceID: Int?
    @State private var mode: NativeScreenMode = .edit
    @State private var resourceImportSession: CSVResourceImportSession?
    @State private var lastResourceImportSession: CSVResourceImportSession?
    @State private var importReport: CSVImportReport?

    private var selectedResourceIndex: Int? {
        guard let selectedResourceID else { return nil }
        return plan.resources.firstIndex(where: { $0.id == selectedResourceID })
    }

    private var reviewProject: ProjectModel {
        plan.asProjectModel()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Resources")
                        .font(.headline)
                    Text("(\(plan.resources.count))")
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
                        let resource = plan.makeResource()
                        plan.resources.append(resource)
                        selectedResourceID = resource.id
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
                    .disabled(mode == .review || selectedResourceIndex == nil)
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
                    List(plan.resources, selection: $selectedResourceID) { resource in
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
                        .tag(resource.id)
                    }
                    .listStyle(.sidebar)
                    .frame(minWidth: 220, idealWidth: 260)

                    if let selectedResourceIndex {
                        resourceInspector(for: $plan.resources[selectedResourceIndex])
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
        .sheet(item: $resourceImportSession) { session in
            ResourceCSVImportMappingSheet(
                session: session,
                onImport: { mappedSession in
                    if let result = CSVExporter.applyResourceImport(mappedSession, into: plan) {
                        plan = result.plan
                        selectedResourceID = plan.resources.last?.id
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
                selectedResourceID = plan.resources.first?.id
            }
        }
        .onChange(of: plan.resources.map(\.id)) { _, ids in
            if let selectedResourceID, ids.contains(selectedResourceID) {
                return
            }
            selectedResourceID = ids.first
        }
    }

    private func reopenResourceImportMapping() {
        guard let session = lastResourceImportSession else { return }
        importReport = nil
        DispatchQueue.main.async {
            resourceImportSession = session
        }
    }

    private func selectImportedResourceIssue(_ issue: CSVImportIssue) {
        guard let targetID = issue.targetID, plan.resources.contains(where: { $0.id == targetID }) else { return }
        selectedResourceID = targetID
        importReport = nil
    }

    private func fixResourceImportIssue(_ issue: CSVImportIssue) {
        guard let fixAction = issue.fixAction else { return }

        switch fixAction {
        case let .createResourceCalendar(name, resourceID):
            let calendarID = ensureCalendar(named: name)
            if let resourceIndex = plan.resources.firstIndex(where: { $0.id == resourceID }) {
                plan.resources[resourceIndex].calendarUniqueID = calendarID
                selectedResourceID = resourceID
                plan.reschedule()
                removeIssueFromReport(issue.id)
            }
        default:
            break
        }
    }

    private func ensureCalendar(named name: String) -> Int {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let existing = plan.calendars.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }) {
            return existing.id
        }

        let calendar = plan.makeCalendar(name: name)
        plan.calendars.append(calendar)
        return calendar.id
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
    private func resourceInspector(for resource: Binding<NativePlanResource>) -> some View {
        let resourceAssignments = assignments(for: resource.wrappedValue.id)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Resource Basics") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Name", text: resource.name)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 12) {
                            TextField("Type", text: resource.type)
                                .textFieldStyle(.roundedBorder)
                            TextField("Initials", text: resource.initials)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }

                        HStack(spacing: 12) {
                            TextField("Group", text: resource.group)
                                .textFieldStyle(.roundedBorder)
                            TextField("Email", text: resource.emailAddress)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Max Units")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: resource.maxUnits, in: 0 ... 300, step: 25)
                            Text("\(Int(resource.wrappedValue.maxUnits))%")
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        Toggle("Active", isOn: resource.active)

                        Picker("Base Calendar", selection: resource.calendarUniqueID) {
                            Text("Default Project Calendar").tag(Int?.none)
                            ForEach(plan.calendars) { calendar in
                                Text(calendar.name).tag(Optional(calendar.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Notes") {
                    TextEditor(text: resource.notes)
                        .frame(minHeight: 120)
                }

                GroupBox("Financials") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Standard Rate / Hour")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                StableDecimalTextField(title: "0", text: decimalTextBinding(resource.standardRate))
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Overtime Rate / Hour")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                StableDecimalTextField(title: "0", text: decimalTextBinding(resource.overtimeRate))
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Cost Per Use")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                StableDecimalTextField(title: "0", text: decimalTextBinding(resource.costPerUse))
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Accrue At")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Accrue At", selection: resource.accrueAt) {
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

    private func deleteSelectedResource() {
        guard let selectedResourceIndex else { return }
        let removedID = plan.resources[selectedResourceIndex].id
        plan.resources.remove(at: selectedResourceIndex)
        plan.assignments.removeAll { $0.resourceID == removedID }
    }

    private func assignments(for resourceID: Int) -> [NativePlanAssignment] {
        plan.assignments.filter { $0.resourceID == resourceID }
    }

    private func taskName(for taskID: Int) -> String {
        plan.tasks.first(where: { $0.id == taskID })?.name ?? "Unknown Task"
    }

    private func currencyText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private func decimalTextBinding(_ value: Binding<Double>) -> Binding<String> {
        Binding(
            get: {
                let current = value.wrappedValue
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
                value.wrappedValue = max(0, Double(normalized) ?? 0)
            }
        )
    }
}

private enum NativeScreenMode: String, CaseIterable, Identifiable {
    case edit = "Edit"
    case review = "Review"

    var id: String { rawValue }
}
