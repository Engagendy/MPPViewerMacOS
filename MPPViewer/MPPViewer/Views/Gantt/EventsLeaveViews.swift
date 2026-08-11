import SwiftUI
import SwiftData
import AppKit

// MARK: - Holidays / Events / Leave editor

/// Authoring surface for visual-only timeline holidays/observances/events and
/// per-resource leave. Edits a working copy and hands the final arrays back via
/// `onSave` when the user commits. Never touches scheduling.
struct EventLeaveEditorView: View {
    enum Section: String, CaseIterable, Identifiable {
        case events = "Holidays & Events"
        case leave = "Resource Leave"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss

    @State private var events: [PlanTimelineEvent]
    @State private var leaves: [PlanResourceLeave]
    @State private var section: Section = .events
    let resources: [NativePlanResource]
    let onSave: ([PlanTimelineEvent], [PlanResourceLeave]) -> Void

    init(
        events: [PlanTimelineEvent],
        leaves: [PlanResourceLeave],
        resources: [NativePlanResource],
        onSave: @escaping ([PlanTimelineEvent], [PlanResourceLeave]) -> Void
    ) {
        self._events = State(initialValue: events)
        self._leaves = State(initialValue: leaves)
        self.resources = resources
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Picker("", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            Group {
                switch section {
                case .events: eventsList
                case .leave: leaveList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footer
        }
        .frame(width: 640, height: 480)
    }

    private var header: some View {
        HStack {
            Label("Holidays, Events & Leave", systemImage: "calendar.badge.clock")
                .font(.headline)
            Spacer()
            Text("Visual only — does not reschedule tasks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Button {
                switch section {
                case .events: addEvent()
                case .leave: addLeave()
                }
            } label: {
                Label(section == .events ? "Add Event" : "Add Leave", systemImage: "plus")
            }
            .disabled(section == .leave && resources.isEmpty)

            Menu {
                if section == .events {
                    Button("Download CSV Template") { CSVExporter.exportEventImportTemplateCSV() }
                    Button("Download Excel Template") { CSVExporter.exportEventImportTemplateExcel() }
                } else {
                    Button("Download CSV Template") { CSVExporter.exportLeaveImportTemplateCSV(resources: resources) }
                    Button("Download Excel Template") { CSVExporter.exportLeaveImportTemplateExcel(resources: resources) }
                }
            } label: {
                Label("Template", systemImage: "tablecells")
            }
            .fixedSize()

            Button {
                if section == .events {
                    if let imported = CSVExporter.importTimelineEvents() { events.append(contentsOf: imported) }
                } else {
                    if let imported = CSVExporter.importResourceLeaves(resources: resources) { leaves.append(contentsOf: imported) }
                }
            } label: {
                Label("Import…", systemImage: "square.and.arrow.down")
            }
            .disabled(section == .leave && resources.isEmpty)

            if section == .leave && resources.isEmpty {
                Text("Add a resource first to record leave.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("Save") {
                onSave(normalizedEvents, normalizedLeaves)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    // MARK: Events

    private var eventsList: some View {
        Group {
            if events.isEmpty {
                emptyState("No holidays or events yet.", systemImage: "calendar")
            } else {
                List {
                    ForEach($events) { $event in
                        TimelineEventRow(
                            event: $event,
                            onDelete: { events.removeAll { $0.id == event.id } },
                            onDuplicate: { copy in events.append(copy) }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: Leave

    private var leaveList: some View {
        Group {
            if leaves.isEmpty {
                emptyState("No resource leave recorded yet.", systemImage: "figure.walk.departure")
            } else {
                List {
                    ForEach($leaves) { $leave in
                        ResourceLeaveRow(leave: $leave, resources: resources) {
                            leaves.removeAll { $0.id == leave.id }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func emptyState(_ message: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func addEvent() {
        let today = Calendar.current.startOfDay(for: Date())
        events.append(PlanTimelineEvent(name: "New Event", startDate: today, endDate: today))
    }

    private func addLeave() {
        guard let resourceID = resources.first?.id else { return }
        let today = Calendar.current.startOfDay(for: Date())
        leaves.append(PlanResourceLeave(resourceID: resourceID, startDate: today, endDate: today))
    }

    private var normalizedEvents: [PlanTimelineEvent] {
        events.map { event in
            var normalized = event
            if normalized.endDate < normalized.startDate {
                normalized.endDate = normalized.startDate
            }
            return normalized
        }
    }

    private var normalizedLeaves: [PlanResourceLeave] {
        leaves.map { leave in
            var normalized = leave
            if normalized.endDate < normalized.startDate {
                normalized.endDate = normalized.startDate
            }
            return normalized
        }
    }
}

// MARK: - Reusable event / leave row editors

/// One editable holiday/observance/event row (color, name, kind, date range).
struct TimelineEventRow: View {
    @Binding var event: PlanTimelineEvent
    let onDelete: () -> Void
    var onDuplicate: ((PlanTimelineEvent) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("", selection: Binding(
                get: { Color(hex: event.colorHex.isEmpty ? event.effectiveColorHex : event.colorHex) ?? .accentColor },
                set: { event.colorHex = $0.hexString ?? "" }
            ))
            .labelsHidden()
            .frame(width: 40)

            TextField("Name", text: $event.name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120)

            Picker("", selection: $event.kind) {
                ForEach(PlanTimelineEvent.Kind.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)

            DatePicker("", selection: $event.startDate, displayedComponents: .date)
                .labelsHidden()
            Text("→").foregroundStyle(.secondary)
            DatePicker("", selection: $event.endDate, displayedComponents: .date)
                .labelsHidden()

            if let onDuplicate {
                Menu {
                    Button("Repeat Next Year") {
                        onDuplicate(event.shiftedByOneYear(calendarIdentifier: .gregorian))
                    }
                    Button("Repeat Next Year (Hijri)") {
                        onDuplicate(event.shiftedByOneYear(calendarIdentifier: .islamicUmmAlQura))
                    }
                } label: {
                    Image(systemName: "repeat")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add a copy of this event one year later. Use Hijri for observances like Ramadan and Eid, whose dates follow the Islamic calendar.")
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

extension PlanTimelineEvent {
    /// A copy of this event shifted one year later in the given calendar.
    /// Hijri (islamicUmmAlQura) keeps observances like Ramadan aligned with the
    /// Islamic year (~11 days earlier each Gregorian year).
    func shiftedByOneYear(calendarIdentifier: Calendar.Identifier) -> PlanTimelineEvent {
        var shiftCalendar = Calendar(identifier: calendarIdentifier)
        shiftCalendar.timeZone = Calendar.current.timeZone
        let newStart = shiftCalendar.date(byAdding: .year, value: 1, to: startDate) ?? startDate
        let newEnd = shiftCalendar.date(byAdding: .year, value: 1, to: endDate) ?? endDate
        return PlanTimelineEvent(
            name: name,
            startDate: newStart,
            endDate: newEnd,
            kind: kind,
            colorHex: colorHex
        )
    }
}

/// One editable resource-leave row (color, resource, reason, date range).
struct ResourceLeaveRow: View {
    @Binding var leave: PlanResourceLeave
    let resources: [NativePlanResource]
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("", selection: Binding(
                get: { Color(hex: leave.colorHex.isEmpty ? leave.effectiveColorHex : leave.colorHex) ?? .accentColor },
                set: { leave.colorHex = $0.hexString ?? "" }
            ))
            .labelsHidden()
            .frame(width: 40)

            Picker("", selection: $leave.resourceID) {
                ForEach(resources, id: \.id) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .frame(width: 150)

            TextField("Reason", text: $leave.name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 100)

            DatePicker("", selection: $leave.startDate, displayedComponents: .date)
                .labelsHidden()
            Text("→").foregroundStyle(.secondary)
            DatePicker("", selection: $leave.endDate, displayedComponents: .date)
                .labelsHidden()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Full-screen Events & Leave manager (sidebar destination)

/// Sidebar destination for managing holidays/observances/events and per-resource
/// leave. Edits persist directly to the SwiftData-backed plan. Visual only.
struct EventsLeaveManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    let planModel: PortfolioProjectPlan

    @State private var events: [PlanTimelineEvent]
    @State private var leaves: [PlanResourceLeave]

    init(planModel: PortfolioProjectPlan) {
        self.planModel = planModel
        _events = State(initialValue: planModel.nativeTimelineEventsForUI)
        _leaves = State(initialValue: planModel.nativeResourceLeavesForUI)
    }

    private var resources: [NativePlanResource] { planModel.nativeResourcesForUI }

    /// Combined events + leave, mapped to timeline rows for the right pane.
    private var timelineItems: [EventsLeaveTimelineView.Item] {
        var result: [EventsLeaveTimelineView.Item] = []
        for event in events.sorted(by: { $0.startDate < $1.startDate }) {
            result.append(.init(
                id: event.id,
                name: event.name,
                subtitle: event.kind.label,
                start: event.startDate,
                end: event.endDate,
                colorHex: event.effectiveColorHex
            ))
        }
        let names = Dictionary(resources.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        for leave in leaves.sorted(by: { $0.startDate < $1.startDate }) {
            let resourceName = names[leave.resourceID] ?? "Resource"
            let reason = leave.name.trimmingCharacters(in: .whitespaces)
            let hasReason = !reason.isEmpty && reason.caseInsensitiveCompare("Leave") != .orderedSame
            result.append(.init(
                id: leave.id,
                name: resourceName,
                subtitle: hasReason ? reason : "Leave",
                start: leave.startDate,
                end: leave.endDate,
                colorHex: leave.effectiveColorHex
            ))
        }
        return result
    }

    @State private var isEditing = false

    var body: some View {
        EventsLeaveTimelineView(
            items: timelineItems,
            title: planModel.title.isEmpty ? "Plan" : planModel.title,
            onEdit: { isEditing = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $isEditing) {
            EventLeaveEditorView(
                events: events,
                leaves: leaves,
                resources: resources,
                onSave: { newEvents, newLeaves in
                    events = newEvents
                    leaves = newLeaves
                    persist()
                }
            )
        }
        // Resync when the plan changes underneath us (undo/redo, Gantt sheet).
        .onChange(of: planModel.timelineEvents) { _, newValue in
            if events != newValue { events = newValue }
        }
        .onChange(of: planModel.resourceLeaves) { _, newValue in
            if leaves != newValue { leaves = newValue }
        }
    }

    private func persist() {
        let previousEvents = planModel.timelineEvents
        let previousLeaves = planModel.resourceLeaves

        planModel.timelineEvents = events.map { event in
            var normalized = event
            if normalized.endDate < normalized.startDate { normalized.endDate = normalized.startDate }
            return normalized
        }
        planModel.resourceLeaves = leaves.map { leave in
            var normalized = leave
            if normalized.endDate < normalized.startDate { normalized.endDate = normalized.startDate }
            return normalized
        }
        planModel.updatedAt = Date()

        if previousEvents != planModel.timelineEvents || previousLeaves != planModel.resourceLeaves {
            Self.registerUndo(
                undoManager,
                planModel: planModel,
                modelContext: modelContext,
                events: previousEvents,
                leaves: previousLeaves
            )
        }
        try? modelContext.save()
    }

    /// Snapshot-based undo/redo for event & leave edits: each registration
    /// captures the arrays to restore and re-registers the inverse.
    private static func registerUndo(
        _ undoManager: UndoManager?,
        planModel: PortfolioProjectPlan,
        modelContext: ModelContext,
        events: [PlanTimelineEvent],
        leaves: [PlanResourceLeave]
    ) {
        undoManager?.registerUndo(withTarget: planModel) { model in
            let redoEvents = model.timelineEvents
            let redoLeaves = model.resourceLeaves
            model.timelineEvents = events
            model.resourceLeaves = leaves
            model.updatedAt = Date()
            try? modelContext.save()
            registerUndo(undoManager, planModel: model, modelContext: modelContext, events: redoEvents, leaves: redoLeaves)
        }
        undoManager?.setActionName("Edit Events & Leave")
    }
}

// MARK: - Events & Leave timeline (Gantt of only events/leaves)

/// A focused Gantt-style timeline that plots only holidays/observances/events
/// and resource leave — each as its own labelled bar row — with zoom and
/// PDF/SVG export. Used on the right side of the Events & Leave manager.
struct EventsLeaveTimelineView: View {
    struct Item: Identifiable {
        let id: UUID
        let name: String
        let subtitle: String
        let start: Date
        let end: Date
        let colorHex: String
    }

    let items: [Item]
    let title: String
    var onEdit: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var pixelsPerDay: CGFloat = 5
    @State private var shouldAutoFit = true
    @State private var viewportWidth: CGFloat = 0

    private let nameColumnWidth: CGFloat = 220
    private let rowHeight: CGFloat = 30
    private let headerHeight: CGFloat = 44

    private var dateRange: (start: Date, end: Date) {
        let cal = Calendar.current
        guard let minStart = items.map(\.start).min(),
              let maxEnd = items.map(\.end).max() else {
            let today = cal.startOfDay(for: Date())
            return (today, cal.date(byAdding: .day, value: 30, to: today) ?? today)
        }
        let start = cal.date(byAdding: .day, value: -7, to: minStart) ?? minStart
        let end = cal.date(byAdding: .day, value: 7, to: maxEnd) ?? maxEnd
        return (cal.startOfDay(for: start), cal.startOfDay(for: end))
    }

    private var totalDays: Int {
        max(1, Calendar.current.dateComponents([.day], from: dateRange.start, to: dateRange.end).day ?? 1)
    }

    private var timelineWidth: CGFloat { CGFloat(totalDays) * pixelsPerDay }

    private func dayOffset(_ date: Date) -> CGFloat {
        CGFloat(Calendar.current.dateComponents([.day], from: dateRange.start, to: Calendar.current.startOfDay(for: date)).day ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if items.isEmpty {
                ContentUnavailableView(
                    "Nothing to Plot",
                    systemImage: "calendar.badge.clock",
                    description: Text("Add holidays, events, or resource leave to see them on the timeline.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        timelineContent
                            .frame(minHeight: geometry.size.height, alignment: .topLeading)
                    }
                    .onAppear { fit(to: geometry.size.width) }
                    .onChange(of: geometry.size.width) { _, w in fit(to: w) }
                    .onChange(of: totalDays) { _, _ in if shouldAutoFit { fit(to: geometry.size.width) } }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Text("Events & Leave")
                .font(.headline)
            Text("(\(items.count))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()

            if let onEdit {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "square.and.pencil").font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .help("Add, edit, or remove holidays, events, and resource leave.")

                Divider().frame(height: 16)
            }

            Menu {
                Button { exportPDF() } label: { Label("Export PDF…", systemImage: "doc.richtext") }
                Button { exportSVG() } label: { Label("Export SVG (Vector)…", systemImage: "square.on.square.dashed") }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up").font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(items.isEmpty)

            Divider().frame(height: 16)

            GanttZoomControls(
                pixelsPerDay: pixelsPerDay,
                totalDays: totalDays,
                onFitAll: { shouldAutoFit = true; fit(to: viewportWidth) },
                onShowWeek: { shouldAutoFit = false; pixelsPerDay = 40 },
                onShowMonth: { shouldAutoFit = false; pixelsPerDay = 10 },
                onZoomOut: { shouldAutoFit = false; pixelsPerDay = max(2, pixelsPerDay / 1.5) },
                onZoomIn: { shouldAutoFit = false; pixelsPerDay = min(100, pixelsPerDay * 1.5) }
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var timelineContent: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("Details").font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(width: nameColumnWidth, height: headerHeight, alignment: .bottomLeading)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                Divider()

                ForEach(items) { item in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: item.colorHex) ?? .accentColor)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.caption).fontWeight(.medium).lineLimit(1)
                            Text("\(item.subtitle) · \(DateFormatting.shortDate(item.start)) – \(DateFormatting.shortDate(item.end))")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: nameColumnWidth, height: rowHeight, alignment: .leading)
                    .padding(.horizontal, 8)
                    Divider()
                }
            }
            .frame(width: nameColumnWidth)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                GanttHeaderView(dateRange: dateRange, pixelsPerDay: pixelsPerDay, totalWidth: timelineWidth)
                timelineCanvas
                    .frame(width: timelineWidth, height: CGFloat(items.count) * rowHeight)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var timelineCanvas: some View {
        Canvas { context, size in
            // Row separators
            for row in 0...items.count {
                let y = CGFloat(row) * rowHeight
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)
            }

            for (index, item) in items.enumerated() {
                let y = CGFloat(index) * rowHeight
                let x1 = dayOffset(item.start) * pixelsPerDay
                let x2 = (dayOffset(item.end) + 1) * pixelsPerDay
                let w = max(3, x2 - x1)
                let color = Color(hex: item.colorHex) ?? .accentColor
                let rect = CGRect(x: x1, y: y + 5, width: w, height: rowHeight - 10)
                let rr = RoundedRectangle(cornerRadius: 4).path(in: rect)
                context.fill(rr, with: .color(color.opacity(0.85)))
                context.stroke(rr, with: .color(color), lineWidth: 0.75)

                let label = Text(item.name).font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
                context.draw(context.resolve(label), at: CGPoint(x: x1 + 6, y: y + rowHeight / 2), anchor: .leading)
            }
        }
    }

    private func fit(to width: CGFloat) {
        viewportWidth = width
        guard shouldAutoFit, width > 0 else { return }
        let available = max(50, width - nameColumnWidth - 1)
        pixelsPerDay = max(2, min(100, available / CGFloat(max(1, totalDays))))
    }

    // MARK: Export

    private var exportContentSize: CGSize {
        CGSize(width: nameColumnWidth + 1 + timelineWidth, height: headerHeight + CGFloat(items.count) * rowHeight)
    }

    @MainActor
    private func exportPDF() {
        guard !items.isEmpty else { return }
        PDFExporter.exportGanttToPDF(
            view: timelineContent.frame(width: exportContentSize.width, height: exportContentSize.height, alignment: .topLeading),
            contentSize: exportContentSize,
            fileName: "\(title) - Events \(PDFExporter.fileNameTimestamp).pdf"
        )
    }

    @MainActor
    private func exportSVG() {
        guard !items.isEmpty else { return }
        let rows: [SVGExporter.GanttRow] = items.map { item in
            let dates = "\(DateFormatting.shortDate(item.start)) – \(DateFormatting.shortDate(item.end))"
            let subtitle = item.subtitle.isEmpty ? dates : "\(item.subtitle) · \(dates)"
            return SVGExporter.GanttRow(
                name: item.name,
                outlineLevel: 1,
                start: item.start,
                finish: item.end,
                isMilestone: false,
                isSummary: false,
                isCritical: false,
                percentComplete: 0,
                colorHex: item.colorHex,
                subtitle: subtitle
            )
        }
        SVGExporter.exportGantt(
            rows: rows,
            rangeStart: dateRange.start,
            rangeEnd: dateRange.end,
            pixelsPerDay: max(2, pixelsPerDay),
            rowHeight: rowHeight,
            title: "\(title) — Events & Leave",
            fileName: "\(title) - Events \(PDFExporter.fileNameTimestamp).svg"
        )
    }
}
