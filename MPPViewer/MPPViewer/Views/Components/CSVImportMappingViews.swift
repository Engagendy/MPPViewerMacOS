import SwiftUI

struct TaskCSVImportMappingSheet: View {
    let initialSession: CSVTaskImportSession
    let onImport: (CSVTaskImportSession) -> Void
    let onCancel: () -> Void

    @State private var session: CSVTaskImportSession

    init(
        session: CSVTaskImportSession,
        onImport: @escaping (CSVTaskImportSession) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialSession = session
        self.onImport = onImport
        self.onCancel = onCancel
        _session = State(initialValue: session)
    }

    private var canImport: Bool {
        (session.mapping[.name] ?? nil) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Tasks from CSV or Excel")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(session.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Map the spreadsheet columns to planner fields before importing. Unmapped fields will be ignored.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(CSVTaskImportField.allCases) { field in
                        CSVImportMappingRow(
                            title: field.rawValue,
                            required: field == .name,
                            headers: session.headers,
                            selection: Binding(
                                get: { session.mapping[field] ?? nil },
                                set: { session.mapping[field] = $0 }
                            )
                        )
                    }
                }
            }
            .frame(maxHeight: 320)

            CSVImportPreviewTable(headers: session.headers, rows: session.previewRows)

            HStack {
                if !canImport {
                    Text("Map `Task Name` to continue.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Import") {
                    onImport(session)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canImport)
            }
        }
        .padding(20)
        .frame(minWidth: 860, minHeight: 620)
    }
}

struct ResourceCSVImportMappingSheet: View {
    let initialSession: CSVResourceImportSession
    let onImport: (CSVResourceImportSession) -> Void
    let onCancel: () -> Void

    @State private var session: CSVResourceImportSession

    init(
        session: CSVResourceImportSession,
        onImport: @escaping (CSVResourceImportSession) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialSession = session
        self.onImport = onImport
        self.onCancel = onCancel
        _session = State(initialValue: session)
    }

    private var canImport: Bool {
        (session.mapping[.name] ?? nil) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Resources from CSV or Excel")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(session.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Map the spreadsheet columns to resource fields before importing. Existing resources are matched by name.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(CSVResourceImportField.allCases) { field in
                        CSVImportMappingRow(
                            title: field.rawValue,
                            required: field == .name,
                            headers: session.headers,
                            selection: Binding(
                                get: { session.mapping[field] ?? nil },
                                set: { session.mapping[field] = $0 }
                            )
                        )
                    }
                }
            }
            .frame(maxHeight: 260)

            CSVImportPreviewTable(headers: session.headers, rows: session.previewRows)

            HStack {
                if !canImport {
                    Text("Map `Resource Name` to continue.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Import") {
                    onImport(session)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canImport)
            }
        }
        .padding(20)
        .frame(minWidth: 820, minHeight: 560)
    }
}

struct AssignmentCSVImportMappingSheet: View {
    let initialSession: CSVAssignmentImportSession
    let onImport: (CSVAssignmentImportSession) -> Void
    let onCancel: () -> Void

    @State private var session: CSVAssignmentImportSession

    init(
        session: CSVAssignmentImportSession,
        onImport: @escaping (CSVAssignmentImportSession) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialSession = session
        self.onImport = onImport
        self.onCancel = onCancel
        _session = State(initialValue: session)
    }

    private var canImport: Bool {
        (session.mapping[.resourceName] ?? nil) != nil &&
        ((session.mapping[.taskID] ?? nil) != nil || (session.mapping[.taskName] ?? nil) != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Assignments from CSV or Excel")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(session.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Each row links a resource to an existing task. Match by `Task ID` when possible; otherwise `Task Name` must be unique.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(CSVAssignmentImportField.allCases) { field in
                        CSVImportMappingRow(
                            title: field.rawValue,
                            required: field == .resourceName,
                            headers: session.headers,
                            selection: Binding(
                                get: { session.mapping[field] ?? nil },
                                set: { session.mapping[field] = $0 }
                            )
                        )
                    }
                }
            }
            .frame(maxHeight: 240)

            CSVImportPreviewTable(headers: session.headers, rows: session.previewRows)

            HStack {
                if !canImport {
                    Text("Map `Resource Name` and either `Task ID` or `Task Name` to continue.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Import") {
                    onImport(session)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canImport)
            }
        }
        .padding(20)
        .frame(minWidth: 840, minHeight: 540)
    }
}

struct DependencyCSVImportMappingSheet: View {
    let initialSession: CSVDependencyImportSession
    let onImport: (CSVDependencyImportSession) -> Void
    let onCancel: () -> Void

    @State private var session: CSVDependencyImportSession

    init(
        session: CSVDependencyImportSession,
        onImport: @escaping (CSVDependencyImportSession) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialSession = session
        self.onImport = onImport
        self.onCancel = onCancel
        _session = State(initialValue: session)
    }

    private var canImport: Bool {
        (session.mapping[.predecessors] ?? nil) != nil &&
        ((session.mapping[.taskID] ?? nil) != nil || (session.mapping[.taskName] ?? nil) != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Dependencies from CSV or Excel")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(session.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Each row targets one task and replaces its predecessor list. Match by `Task ID` when possible; otherwise `Task Name` must be unique.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(CSVDependencyImportField.allCases) { field in
                        CSVImportMappingRow(
                            title: field.rawValue,
                            required: field == .predecessors,
                            headers: session.headers,
                            selection: Binding(
                                get: { session.mapping[field] ?? nil },
                                set: { session.mapping[field] = $0 }
                            )
                        )
                    }
                }
            }
            .frame(maxHeight: 200)

            CSVImportPreviewTable(headers: session.headers, rows: session.previewRows)

            HStack {
                if !canImport {
                    Text("Map `Predecessors` and either `Task ID` or `Task Name` to continue.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Import") {
                    onImport(session)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canImport)
            }
        }
        .padding(20)
        .frame(minWidth: 820, minHeight: 500)
    }
}

struct ConstraintCSVImportMappingSheet: View {
    let initialSession: CSVConstraintImportSession
    let onImport: (CSVConstraintImportSession) -> Void
    let onCancel: () -> Void

    @State private var session: CSVConstraintImportSession

    init(
        session: CSVConstraintImportSession,
        onImport: @escaping (CSVConstraintImportSession) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialSession = session
        self.onImport = onImport
        self.onCancel = onCancel
        _session = State(initialValue: session)
    }

    private var canImport: Bool {
        (session.mapping[.constraintType] ?? nil) != nil &&
        ((session.mapping[.taskID] ?? nil) != nil || (session.mapping[.taskName] ?? nil) != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Constraints from CSV or Excel")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(session.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Each row targets one task and updates its scheduling constraint. Supported types are `ASAP`, `SNET`, `FNET`, `MSO`, and `MFO`.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(CSVConstraintImportField.allCases) { field in
                        CSVImportMappingRow(
                            title: field.rawValue,
                            required: field == .constraintType,
                            headers: session.headers,
                            selection: Binding(
                                get: { session.mapping[field] ?? nil },
                                set: { session.mapping[field] = $0 }
                            )
                        )
                    }
                }
            }
            .frame(maxHeight: 220)

            CSVImportPreviewTable(headers: session.headers, rows: session.previewRows)

            HStack {
                if !canImport {
                    Text("Map `Constraint Type` and either `Task ID` or `Task Name` to continue.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Import") {
                    onImport(session)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canImport)
            }
        }
        .padding(20)
        .frame(minWidth: 820, minHeight: 520)
    }
}

struct BaselineCSVImportMappingSheet: View {
    let initialSession: CSVBaselineImportSession
    let onImport: (CSVBaselineImportSession) -> Void
    let onCancel: () -> Void

    @State private var session: CSVBaselineImportSession

    init(
        session: CSVBaselineImportSession,
        onImport: @escaping (CSVBaselineImportSession) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialSession = session
        self.onImport = onImport
        self.onCancel = onCancel
        _session = State(initialValue: session)
    }

    private var canImport: Bool {
        let hasTaskReference = (session.mapping[.taskID] ?? nil) != nil || (session.mapping[.taskName] ?? nil) != nil
        let hasBaselineField = (session.mapping[.baselineStart] ?? nil) != nil
            || (session.mapping[.baselineFinish] ?? nil) != nil
            || (session.mapping[.baselineDuration] ?? nil) != nil
        return hasTaskReference && hasBaselineField
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Baselines from CSV or Excel")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(session.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Each row matches one task and updates its stored baseline dates or duration. Blank baseline fields clear the stored baseline for that task.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(CSVBaselineImportField.allCases) { field in
                        CSVImportMappingRow(
                            title: field.rawValue,
                            required: field == .baselineStart || field == .baselineFinish || field == .baselineDuration,
                            headers: session.headers,
                            selection: Binding(
                                get: { session.mapping[field] ?? nil },
                                set: { session.mapping[field] = $0 }
                            )
                        )
                    }
                }
            }
            .frame(maxHeight: 220)

            CSVImportPreviewTable(headers: session.headers, rows: session.previewRows)

            HStack {
                if !canImport {
                    Text("Map either `Task ID` or `Task Name`, plus at least one baseline field, to continue.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Import") {
                    onImport(session)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canImport)
            }
        }
        .padding(20)
        .frame(minWidth: 820, minHeight: 520)
    }
}

struct CalendarCSVImportMappingSheet: View {
    let initialSession: CSVCalendarImportSession
    let onImport: (CSVCalendarImportSession) -> Void
    let onCancel: () -> Void

    @State private var session: CSVCalendarImportSession

    init(
        session: CSVCalendarImportSession,
        onImport: @escaping (CSVCalendarImportSession) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialSession = session
        self.onImport = onImport
        self.onCancel = onCancel
        _session = State(initialValue: session)
    }

    private var canImport: Bool {
        (session.mapping[.name] ?? nil) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Calendars from CSV or Excel")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(session.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Each row can define a calendar, its working week, and optionally one exception. Repeating the same calendar name updates that calendar and adds unique exceptions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(CSVCalendarImportField.allCases) { field in
                        CSVImportMappingRow(
                            title: field.rawValue,
                            required: field == .name,
                            headers: session.headers,
                            selection: Binding(
                                get: { session.mapping[field] ?? nil },
                                set: { session.mapping[field] = $0 }
                            )
                        )
                    }
                }
            }
            .frame(maxHeight: 360)

            CSVImportPreviewTable(headers: session.headers, rows: session.previewRows)

            HStack {
                if !canImport {
                    Text("Map `Calendar Name` to continue.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Import") {
                    onImport(session)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canImport)
            }
        }
        .padding(20)
        .frame(minWidth: 920, minHeight: 680)
    }
}

struct CSVImportReportSheet: View {
    let report: CSVImportReport
    let secondaryActionTitle: String?
    let onSecondaryAction: (() -> Void)?
    let onSelectIssue: ((CSVImportIssue) -> Void)?
    let onFixIssue: ((CSVImportIssue) -> Void)?
    let onClose: () -> Void

    private var warningCount: Int {
        report.issues.filter { $0.severity == .warning }.count
    }

    private var errorCount: Int {
        report.issues.filter { $0.severity == .error }.count
    }

    private var fixableIssues: [CSVImportIssue] {
        report.issues.filter { $0.fixAction != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(report.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Review the import outcome before continuing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                importMetricChip(title: "Warnings", value: warningCount, color: .orange)
                importMetricChip(title: "Errors", value: errorCount, color: .red)
                if !fixableIssues.isEmpty {
                    importMetricChip(title: "Fixable", value: fixableIssues.count, color: .green)
                }
                Spacer()
            }

            GroupBox("Summary") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(report.summaryLines, id: \.self) { line in
                        Text(line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("Row Notes") {
                if report.issues.isEmpty {
                    Text("No row-level warnings were generated.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(report.issues) { issue in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: issue.severity.symbolName)
                                        .foregroundStyle(issue.severity.color)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(issue.rowLabel)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(issue.message)
                                    }
                                    Spacer(minLength: 12)
                                    if issue.targetID != nil, let onSelectIssue {
                                        Button("Show") {
                                            onSelectIssue(issue)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    if issue.fixAction != nil, let onFixIssue {
                                        Button(issue.fixAction?.title ?? "Fix") {
                                            onFixIssue(issue)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 220, maxHeight: 320)
                }
            }

            HStack {
                if let secondaryActionTitle, let onSecondaryAction {
                    Button(secondaryActionTitle) {
                        onSecondaryAction()
                    }
                }

                if !fixableIssues.isEmpty, let onFixIssue {
                    Button("Fix All Safe Issues") {
                        for issue in fixableIssues {
                            onFixIssue(issue)
                        }
                    }
                }

                Button("Export CSV") {
                    CSVExporter.exportImportReportToCSV(report)
                }
                .disabled(report.summaryLines.isEmpty && report.issues.isEmpty)

                Spacer()
                Button("Done") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 520)
    }

    private func importMetricChip(title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
    }
}

private extension CSVImportIssueSeverity {
    var symbolName: String {
        switch self {
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

private struct CSVImportMappingRow: View {
    let title: String
    let required: Bool
    let headers: [String]
    @Binding var selection: Int?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(title)
                if required {
                    Text("*")
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 180, alignment: .leading)

            Picker("", selection: $selection) {
                Text("Skip").tag(Int?.none)
                ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                    Text(header.isEmpty ? "Column \(index + 1)" : header).tag(Optional(index))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CSVImportPreviewTable: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.headline)

            if headers.isEmpty {
                Text("No preview available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                                previewCell(
                                    header.isEmpty ? "Column \(index + 1)" : header,
                                    minWidth: 140,
                                    background: Color(nsColor: .controlBackgroundColor),
                                    weight: .semibold
                                )
                            }
                        }

                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 0) {
                                ForEach(Array(headers.enumerated()), id: \.offset) { index, _ in
                                    previewCell(
                                        row.indices.contains(index) ? row[index] : "",
                                        minWidth: 140,
                                        background: .clear,
                                        weight: .regular
                                    )
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 180, maxHeight: 220)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15))
                }
            }
        }
    }

    private func previewCell(_ text: String, minWidth: CGFloat, background: Color, weight: Font.Weight) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(.caption)
            .fontWeight(weight)
            .lineLimit(2)
            .frame(minWidth: minWidth, maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(background)
            .overlay(alignment: .trailing) {
                Divider()
            }
            .overlay(alignment: .bottom) {
                Divider()
            }
    }
}
