import SwiftUI

struct NativeCalendarEditorView: View {
    @Binding var plan: NativeProjectPlan

    @State private var selectedCalendarID: Int?
    @State private var displayMonth = Date()
    @State private var mode: NativeCalendarScreenMode = .edit
    @State private var calendarImportSession: CSVCalendarImportSession?
    @State private var lastCalendarImportSession: CSVCalendarImportSession?
    @State private var importReport: CSVImportReport?

    private let weekdayRows: [(label: String, value: Int)] = [
        ("Sunday", 1),
        ("Monday", 2),
        ("Tuesday", 3),
        ("Wednesday", 4),
        ("Thursday", 5),
        ("Friday", 6),
        ("Saturday", 7)
    ]

    private var selectedCalendarIndex: Int? {
        guard let selectedCalendarID else { return nil }
        return plan.calendars.firstIndex(where: { $0.id == selectedCalendarID })
    }

    private var reviewProject: ProjectModel {
        plan.asProjectModel()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Calendars")
                        .font(.headline)
                    Text("(\(plan.calendars.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Picker("Mode", selection: $mode) {
                            ForEach(NativeCalendarScreenMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        .help("Switch between calendar editing and read-only review")

                        Button {
                            calendarImportSession = CSVExporter.selectCalendarImportSession()
                        } label: {
                            compactToolbarLabel("Import CSV/Excel", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .disabled(mode == .review)
                        .help("Import calendars and exceptions from CSV or Excel-compatible spreadsheet")

                        Menu {
                            Button("Export CSV Template") {
                                CSVExporter.exportCalendarImportTemplateCSV()
                            }
                            Button("Export Excel Example") {
                                CSVExporter.exportCalendarImportTemplateExcel()
                            }
                        } label: {
                            compactToolbarLabel("Templates", systemImage: "tablecells.badge.ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                        .disabled(mode == .review)
                        .help("Export calendar import templates and spreadsheet examples")

                        Button {
                            let calendar = plan.makeCalendar()
                            plan.calendars.append(calendar)
                            selectedCalendarID = calendar.id
                        } label: {
                            compactToolbarLabel("Add Calendar", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .help("Create a new working calendar")

                        Button(role: .destructive) {
                            deleteSelectedCalendar()
                        } label: {
                            compactToolbarLabel("Delete Calendar", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(mode == .review || selectedCalendarIndex == nil)
                        .help("Delete the selected calendar")

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        Picker("Default Calendar", selection: $plan.defaultCalendarUniqueID) {
                            Text("None").tag(Int?.none)
                            ForEach(plan.calendars) { calendar in
                                Text(calendar.name).tag(Optional(calendar.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)
                        .disabled(mode == .review)
                        .help("Choose the project default calendar for tasks and resources without their own calendar")

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            if mode == .edit {
                HSplitView {
                    List(plan.calendars, selection: $selectedCalendarID) { calendar in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(calendar.name)
                                .fontWeight(.medium)
                            HStack(spacing: 8) {
                                Text(calendar.type)
                                if plan.defaultCalendarUniqueID == calendar.id {
                                    Text("Default")
                                }
                                if calendar.personal {
                                    Text("Personal")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .tag(calendar.id)
                    }
                    .listStyle(.sidebar)
                    .frame(minWidth: 220, idealWidth: 260)

                    if let selectedCalendarIndex {
                        calendarInspector(for: $plan.calendars[selectedCalendarIndex])
                            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            "No Calendar Selected",
                            systemImage: "calendar",
                            description: Text("Create or select a calendar to define working time and leave exceptions.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                CalendarView(calendars: reviewProject.calendars)
            }
        }
        .sheet(item: $calendarImportSession) { session in
            CalendarCSVImportMappingSheet(
                session: session,
                onImport: { mappedSession in
                    if let result = CSVExporter.applyCalendarImport(mappedSession, into: plan) {
                        plan = result.plan
                        selectedCalendarID = plan.calendars.last?.id
                        lastCalendarImportSession = mappedSession
                        importReport = result.report
                    }
                    calendarImportSession = nil
                },
                onCancel: {
                    calendarImportSession = nil
                }
            )
        }
        .sheet(item: $importReport) { report in
            CSVImportReportSheet(
                report: report,
                secondaryActionTitle: lastCalendarImportSession == nil ? nil : "Adjust Mapping",
                onSecondaryAction: reopenCalendarImportMapping,
                onSelectIssue: selectImportedCalendarIssue,
                onFixIssue: fixCalendarImportIssue,
                onClose: {
                importReport = nil
                }
            )
        }
        .onAppear {
            if selectedCalendarID == nil {
                selectedCalendarID = plan.calendars.first?.id
            }
        }
        .onChange(of: plan.calendars.map(\.id)) { _, ids in
            if let selectedCalendarID, ids.contains(selectedCalendarID) {
                return
            }
            selectedCalendarID = ids.first
        }
    }

    private func reopenCalendarImportMapping() {
        guard let session = lastCalendarImportSession else { return }
        importReport = nil
        DispatchQueue.main.async {
            calendarImportSession = session
        }
    }

    private func selectImportedCalendarIssue(_ issue: CSVImportIssue) {
        guard let targetID = issue.targetID, plan.calendars.contains(where: { $0.id == targetID }) else { return }
        selectedCalendarID = targetID
        importReport = nil
    }

    private func fixCalendarImportIssue(_ issue: CSVImportIssue) {
        guard let fixAction = issue.fixAction else { return }

        switch fixAction {
        case let .createParentCalendar(name, calendarID):
            let parentID = ensureCalendar(named: name)
            if let calendarIndex = plan.calendars.firstIndex(where: { $0.id == calendarID }), plan.calendars[calendarIndex].id != parentID {
                plan.calendars[calendarIndex].parentUniqueID = parentID
                selectedCalendarID = calendarID
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
        .frame(width: 112, alignment: .leading)
    }

    @ViewBuilder
    private func calendarInspector(for calendar: Binding<NativePlanCalendar>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Calendar Basics") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Name", text: calendar.name)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 12) {
                            TextField("Type", text: calendar.type)
                                .textFieldStyle(.roundedBorder)
                            Toggle("Personal Calendar", isOn: calendar.personal)
                        }

                        Picker("Parent Calendar", selection: calendar.parentUniqueID) {
                            Text("None").tag(Int?.none)
                            ForEach(plan.calendars.filter { $0.id != calendar.wrappedValue.id }) { parent in
                                Text(parent.name).tag(Optional(parent.id))
                            }
                        }
                        .pickerStyle(.menu)

                        if plan.defaultCalendarUniqueID == calendar.wrappedValue.id {
                            Text("This is the current project default calendar.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Working Week") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(weekdayRows, id: \.value) { row in
                            weekdayRow(label: row.label, day: dayBinding(for: row.value, in: calendar))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Exceptions") {
                    VStack(alignment: .leading, spacing: 12) {
                        if calendar.wrappedValue.exceptions.isEmpty {
                            Text("No leave or holiday exceptions yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(calendar.wrappedValue.exceptions.indices), id: \.self) { index in
                                exceptionEditor(exception: Binding(
                                    get: { calendar.wrappedValue.exceptions[index] },
                                    set: { calendar.wrappedValue.exceptions[index] = $0 }
                                )) {
                                    calendar.wrappedValue.exceptions.remove(at: index)
                                }
                            }
                        }

                        Button {
                            let baseDate = Calendar.current.startOfDay(for: displayMonth)
                            calendar.wrappedValue.exceptions.append(
                                NativeCalendarException(
                                    name: "Leave",
                                    fromDate: baseDate,
                                    toDate: baseDate,
                                    type: "non_working"
                                )
                            )
                        } label: {
                            Label("Add Exception", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }

    private func weekdayRow(label: String, day: Binding<NativeCalendarDay>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(label, isOn: Binding(
                get: { day.wrappedValue.isWorking },
                set: { isWorking in
                    day.wrappedValue.type = isWorking ? "working" : "non_working"
                    if !isWorking {
                        day.wrappedValue.from = ""
                        day.wrappedValue.to = ""
                    } else {
                        if day.wrappedValue.from.isEmpty { day.wrappedValue.from = "08:00" }
                        if day.wrappedValue.to.isEmpty { day.wrappedValue.to = "17:00" }
                    }
                }
            ))

            if day.wrappedValue.isWorking {
                HStack(spacing: 12) {
                    TextField("From", text: day.from)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    TextField("To", text: day.to)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }
        }
    }

    private func exceptionEditor(
        exception: Binding<NativeCalendarException>,
        onDelete: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Exception Name", text: exception.name)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("From")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: exception.fromDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("To")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: exception.toDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }

                Picker("Type", selection: exception.type) {
                    Text("Non-working").tag("non_working")
                    Text("Working").tag("working")
                }
                .pickerStyle(.menu)
            }

            HStack {
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func dayBinding(for weekday: Int, in calendar: Binding<NativePlanCalendar>) -> Binding<NativeCalendarDay> {
        Binding(
            get: {
                switch weekday {
                case 1: return calendar.wrappedValue.sunday
                case 2: return calendar.wrappedValue.monday
                case 3: return calendar.wrappedValue.tuesday
                case 4: return calendar.wrappedValue.wednesday
                case 5: return calendar.wrappedValue.thursday
                case 6: return calendar.wrappedValue.friday
                default: return calendar.wrappedValue.saturday
                }
            },
            set: { newValue in
                switch weekday {
                case 1: calendar.wrappedValue.sunday = newValue
                case 2: calendar.wrappedValue.monday = newValue
                case 3: calendar.wrappedValue.tuesday = newValue
                case 4: calendar.wrappedValue.wednesday = newValue
                case 5: calendar.wrappedValue.thursday = newValue
                case 6: calendar.wrappedValue.friday = newValue
                default: calendar.wrappedValue.saturday = newValue
                }
            }
        )
    }

    private func deleteSelectedCalendar() {
        guard let selectedCalendarIndex else { return }
        let removedID = plan.calendars[selectedCalendarIndex].id
        plan.calendars.remove(at: selectedCalendarIndex)

        if plan.defaultCalendarUniqueID == removedID {
            plan.defaultCalendarUniqueID = plan.calendars.first?.id
        }

        for resourceIndex in plan.resources.indices where plan.resources[resourceIndex].calendarUniqueID == removedID {
            plan.resources[resourceIndex].calendarUniqueID = nil
        }

        for calendarIndex in plan.calendars.indices where plan.calendars[calendarIndex].parentUniqueID == removedID {
            plan.calendars[calendarIndex].parentUniqueID = nil
        }
    }
}

private enum NativeCalendarScreenMode: String, CaseIterable, Identifiable {
    case edit = "Edit"
    case review = "Review"

    var id: String { rawValue }
}
