import SwiftUI
import SwiftData

struct NativeCalendarEditorView: View {
    @Environment(\.modelContext) private var modelContext

    let planModel: PortfolioProjectPlan

    @State private var reviewProject: ProjectModel
    @State private var selectedCalendarID: Int?
    @State private var displayMonth = Date()
    @State private var mode: NativeCalendarScreenMode = .review
    @State private var calendarImportSession: CSVCalendarImportSession?
    @State private var lastCalendarImportSession: CSVCalendarImportSession?
    @State private var importReport: CSVImportReport?
    @State private var persistenceWorkItem: DispatchWorkItem?

    private let weekdayRows: [(label: String, value: Int)] = [
        ("Sunday", 1),
        ("Monday", 2),
        ("Tuesday", 3),
        ("Wednesday", 4),
        ("Thursday", 5),
        ("Friday", 6),
        ("Saturday", 7)
    ]

    private var orderedCalendars: [PortfolioPlanCalendar] {
        planModel.calendars.sorted { lhs, rhs in
            if lhs.legacyID == rhs.legacyID {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.legacyID < rhs.legacyID
        }
    }

    private var selectedCalendar: PortfolioPlanCalendar? {
        guard let selectedCalendarID else { return nil }
        return orderedCalendars.first(where: { $0.legacyID == selectedCalendarID })
    }

    init(planModel: PortfolioProjectPlan) {
        self.planModel = planModel
        self._reviewProject = State(initialValue: planModel.projectModelForUI())
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Calendars")
                        .font(.headline)
                    Text("(\(orderedCalendars.count))")
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
                            addCalendar()
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
                        .disabled(mode == .review || selectedCalendar == nil)
                        .help("Delete the selected calendar")

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        Picker("Default Calendar", selection: defaultCalendarBinding()) {
                            Text("None").tag(Int?.none)
                            ForEach(orderedCalendars, id: \.legacyID) { calendar in
                                Text(calendar.name).tag(Optional(calendar.legacyID))
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
                    List(orderedCalendars, selection: $selectedCalendarID) { calendar in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(calendar.name)
                                .fontWeight(.medium)
                            HStack(spacing: 8) {
                                Text(calendar.type)
                                if planModel.defaultCalendarUniqueID == calendar.legacyID {
                                    Text("Default")
                                }
                                if calendar.personal {
                                    Text("Personal")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .tag(calendar.legacyID)
                    }
                    .listStyle(.sidebar)
                    .frame(minWidth: 220, idealWidth: 260)

                    if let selectedCalendar {
                        calendarInspector(for: selectedCalendar)
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
        .onAppear {
            refreshReviewProject()
            if selectedCalendarID == nil {
                selectedCalendarID = orderedCalendars.first?.legacyID
            }
        }
        .onChange(of: planModel.updatedAt) { _, _ in
            refreshReviewProject()
        }
        .sheet(item: $calendarImportSession) { session in
            CalendarCSVImportMappingSheet(
                session: session,
                onImport: { mappedSession in
                    let snapshot = planModel.editorSnapshotForUI()
                    if let result = CSVExporter.applyCalendarImport(mappedSession, into: snapshot) {
                        planModel.update(from: result.plan)
                        planModel.updatedAt = Date()
                        try? modelContext.save()
                        refreshReviewProject()
                        selectedCalendarID = result.plan.calendars.last?.id
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
                selectedCalendarID = orderedCalendars.first?.legacyID
            }
        }
        .onChange(of: orderedCalendars.map(\.legacyID)) { _, ids in
            if let selectedCalendarID, ids.contains(selectedCalendarID) {
                return
            }
            selectedCalendarID = ids.first
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

    private func reopenCalendarImportMapping() {
        guard let session = lastCalendarImportSession else { return }
        importReport = nil
        DispatchQueue.main.async {
            calendarImportSession = session
        }
    }

    private func selectImportedCalendarIssue(_ issue: CSVImportIssue) {
        guard let targetID = issue.targetID, orderedCalendars.contains(where: { $0.legacyID == targetID }) else { return }
        selectedCalendarID = targetID
        importReport = nil
    }

    private func fixCalendarImportIssue(_ issue: CSVImportIssue) {
        guard let fixAction = issue.fixAction else { return }

        switch fixAction {
        case let .createParentCalendar(name, calendarID):
            let parentID = ensureCalendar(named: name)
            if let calendar = orderedCalendars.first(where: { $0.legacyID == calendarID }), calendar.legacyID != parentID {
                calendar.parentUniqueID = parentID
                selectedCalendarID = calendarID
                schedulePlanPersistence()
                removeIssueFromReport(issue.id)
            }
        default:
            break
        }
    }

    private func ensureCalendar(named name: String) -> Int {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let existing = orderedCalendars.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }) {
            return existing.legacyID
        }

        let nativeCalendar = planModel.makeCalendarForUI(name: name)
        let calendar = PortfolioPlanCalendar(nativeCalendar: nativeCalendar)
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
        .frame(width: 112, alignment: .leading)
    }

    @ViewBuilder
    private func calendarInspector(for calendar: PortfolioPlanCalendar) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Calendar Basics") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Name", text: binding(for: calendar, keyPath: \.name))
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 12) {
                            TextField("Type", text: binding(for: calendar, keyPath: \.type))
                                .textFieldStyle(.roundedBorder)
                            Toggle("Personal Calendar", isOn: binding(for: calendar, keyPath: \.personal))
                        }

                        Picker("Parent Calendar", selection: binding(for: calendar, keyPath: \.parentUniqueID)) {
                            Text("None").tag(Int?.none)
                            ForEach(orderedCalendars.filter { $0.legacyID != calendar.legacyID }, id: \.legacyID) { parent in
                                Text(parent.name).tag(Optional(parent.legacyID))
                            }
                        }
                        .pickerStyle(.menu)

                        if planModel.defaultCalendarUniqueID == calendar.legacyID {
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
                        if calendar.exceptions.isEmpty {
                            Text("No leave or holiday exceptions yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(calendar.exceptions.indices), id: \.self) { index in
                                exceptionEditor(exception: Binding(
                                    get: { calendar.exceptions[index] },
                                    set: {
                                        var updated = calendar.exceptions
                                        updated[index] = $0
                                        calendar.exceptions = updated
                                        schedulePlanPersistence()
                                    }
                                )) {
                                    var updated = calendar.exceptions
                                    updated.remove(at: index)
                                    calendar.exceptions = updated
                                    schedulePlanPersistence()
                                }
                            }
                        }

                        Button {
                            let baseDate = Calendar.current.startOfDay(for: displayMonth)
                            var updated = calendar.exceptions
                            updated.append(
                                NativeCalendarException(
                                    name: "Leave",
                                    fromDate: baseDate,
                                    toDate: baseDate,
                                    type: "non_working"
                                )
                            )
                            calendar.exceptions = updated
                            schedulePlanPersistence()
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

    private func dayBinding(for weekday: Int, in calendar: PortfolioPlanCalendar) -> Binding<NativeCalendarDay> {
        Binding(
            get: {
                switch weekday {
                case 1: return calendar.sunday
                case 2: return calendar.monday
                case 3: return calendar.tuesday
                case 4: return calendar.wednesday
                case 5: return calendar.thursday
                case 6: return calendar.friday
                default: return calendar.saturday
                }
            },
            set: { newValue in
                switch weekday {
                case 1: calendar.sunday = newValue
                case 2: calendar.monday = newValue
                case 3: calendar.tuesday = newValue
                case 4: calendar.wednesday = newValue
                case 5: calendar.thursday = newValue
                case 6: calendar.friday = newValue
                default: calendar.saturday = newValue
                }
                schedulePlanPersistence()
            }
        )
    }

    private func addCalendar() {
        let nativeCalendar = planModel.makeCalendarForUI()
        let calendar = PortfolioPlanCalendar(nativeCalendar: nativeCalendar)
        calendar.plan = planModel
        planModel.calendars.append(calendar)
        selectedCalendarID = calendar.legacyID
        schedulePlanPersistence()
    }

    private func deleteSelectedCalendar() {
        guard let selectedCalendar else { return }
        let removedID = selectedCalendar.legacyID

        if planModel.defaultCalendarUniqueID == removedID {
            planModel.defaultCalendarUniqueID = orderedCalendars.first(where: { $0.legacyID != removedID })?.legacyID
        }

        for resource in planModel.resources where resource.calendarUniqueID == removedID {
            resource.calendarUniqueID = nil
        }

        for calendar in orderedCalendars where calendar.parentUniqueID == removedID {
            calendar.parentUniqueID = nil
        }

        modelContext.delete(selectedCalendar)
        selectedCalendarID = orderedCalendars.first(where: { $0.legacyID != removedID })?.legacyID
        schedulePlanPersistence()
    }

    private func refreshReviewProject() {
        reviewProject = planModel.projectModelForUI()
    }

    private func defaultCalendarBinding() -> Binding<Int?> {
        Binding(
            get: { planModel.defaultCalendarUniqueID },
            set: { newValue in
                planModel.defaultCalendarUniqueID = newValue
                schedulePlanPersistence()
            }
        )
    }

    private func binding<T>(for calendar: PortfolioPlanCalendar, keyPath: ReferenceWritableKeyPath<PortfolioPlanCalendar, T>) -> Binding<T> {
        Binding(
            get: { calendar[keyPath: keyPath] },
            set: { newValue in
                calendar[keyPath: keyPath] = newValue
                schedulePlanPersistence()
            }
        )
    }
}

private enum NativeCalendarScreenMode: String, CaseIterable, Identifiable {
    case edit = "Edit"
    case review = "Review"

    var id: String { rawValue }
}
