import SwiftUI
import UniformTypeIdentifiers

struct DiffView: View {
    let project: ProjectModel

    @State private var baselineProject: ProjectModel?
    @State private var baselineFileName: String?
    @State private var diffs: [TaskDiff] = []
    @State private var diffSummary: ProjectDiffSummary?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showFilePicker = false

    private var addedCount: Int { diffs.filter { $0.changeType == .added }.count }
    private var removedCount: Int { diffs.filter { $0.changeType == .removed }.count }
    private var modifiedCount: Int { diffs.filter { $0.changeType == .modified }.count }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Compare Versions")
                    .font(.headline)

                if let name = baselineFileName {
                    Text("vs \(name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showFilePicker = true
                } label: {
                    Label(
                        baselineProject != nil ? "Change Baseline File" : "Select Baseline File",
                        systemImage: "doc.badge.plus"
                    )
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Converting and loading baseline file...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text("Failed to load baseline")
                        .font(.headline)
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    Button("Try Again") {
                        showFilePicker = true
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if baselineProject == nil {
                ContentUnavailableView(
                    "No Baseline Selected",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text("Select a baseline .mpp file to compare against the current project.")
                )
            } else if diffs.isEmpty {
                ContentUnavailableView(
                    "No Differences",
                    systemImage: "checkmark.circle",
                    description: Text("The two project files are identical.")
                )
            } else {
                VStack(spacing: 0) {
                    if let diffSummary {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12),
                            ],
                            spacing: 12
                        ) {
                            diffSummaryCard(
                                title: "Project Finish",
                                value: finishDeltaValue(diffSummary.projectFinishDeltaDays),
                                subtitle: finishDeltaSubtitle(diffSummary),
                                color: finishDeltaColor(diffSummary.projectFinishDeltaDays),
                                systemImage: "calendar.badge.clock"
                            )

                            diffSummaryCard(
                                title: "Cost Delta",
                                value: formattedCurrencyDelta(diffSummary.totalCostDelta),
                                subtitle: diffSummary.changedCostTaskCount == 0
                                    ? "No task cost changes"
                                    : "\(diffSummary.changedCostTaskCount) task cost changes",
                                color: costDeltaColor(diffSummary.totalCostDelta),
                                systemImage: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90"
                            )

                            diffSummaryCard(
                                title: "Critical Path",
                                value: criticalDeltaValue(diffSummary),
                                subtitle: criticalDeltaSubtitle(diffSummary),
                                color: criticalDeltaColor(diffSummary),
                                systemImage: "exclamationmark.triangle"
                            )

                            diffSummaryCard(
                                title: "Largest Slip",
                                value: largestSlipValue(diffSummary),
                                subtitle: largestSlipSubtitle(diffSummary),
                                color: diffSummary.largestFinishSlip == nil ? .secondary : .orange,
                                systemImage: "arrow.turn.down.right"
                            )
                        }
                        .padding(12)
                    }

                    HStack(spacing: 20) {
                        HStack(spacing: 4) {
                            Circle().fill(.green).frame(width: 8, height: 8)
                            Text("\(addedCount) Added")
                        }
                        HStack(spacing: 4) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("\(removedCount) Removed")
                        }
                        HStack(spacing: 4) {
                            Circle().fill(.yellow).frame(width: 8, height: 8)
                            Text("\(modifiedCount) Modified")
                        }
                        Spacer()
                        Text("\(diffs.count) total changes")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                }

                Divider()

                // Diff table
                Table(diffs) {
                    TableColumn("ID") { diff in
                        Text("\(diff.id)")
                            .monospacedDigit()
                    }
                    .width(min: 40, ideal: 60, max: 80)

                    TableColumn("Name") { diff in
                        Text(diff.taskName)
                            .lineLimit(1)
                    }
                    .width(min: 150, ideal: 250)

                    TableColumn("Change") { diff in
                        Text(diff.changeType.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(colorForChangeType(diff.changeType).opacity(0.15))
                            .foregroundStyle(colorForChangeType(diff.changeType))
                            .clipShape(Capsule())
                    }
                    .width(min: 80, ideal: 100, max: 120)

                    TableColumn("Finish Delta") { diff in
                        finishDeltaView(diff.finishDeltaDays)
                    }
                    .width(min: 90, ideal: 110, max: 130)

                    TableColumn("Cost Delta") { diff in
                        costDeltaView(diff.costDelta)
                    }
                    .width(min: 110, ideal: 130, max: 150)

                    TableColumn("Criticality") { diff in
                        criticalityDeltaView(diff.criticalityDelta)
                    }
                    .width(min: 90, ideal: 120, max: 140)

                    TableColumn("Details") { diff in
                        if diff.changes.isEmpty {
                            Text("-")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(diff.changes.map { "\($0.field): \($0.oldValue) \u{2192} \($0.newValue)" }.joined(separator: "; "))
                                .font(.caption)
                                .lineLimit(2)
                        }
                    }
                    .width(min: 200, ideal: 400)
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.mpp, .mppplan],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                loadBaseline(from: url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func colorForChangeType(_ type: DiffChangeType) -> Color {
        switch type {
        case .added: return .green
        case .removed: return .red
        case .modified: return .yellow
        }
    }

    private func loadBaseline(from url: URL) {
        let fileName = url.lastPathComponent
        let didStart = url.startAccessingSecurityScopedResource()

        // Copy to temp so the converter can access it after the security scope ends
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension.isEmpty ? "mpp" : url.pathExtension)
        do {
            try FileManager.default.copyItem(at: url, to: tempURL)
        } catch {
            if didStart { url.stopAccessingSecurityScopedResource() }
            errorMessage = "Could not read file: \(error.localizedDescription)"
            return
        }

        if didStart { url.stopAccessingSecurityScopedResource() }

        isLoading = true
        errorMessage = nil
        baselineFileName = fileName

        Task {
            do {
                let model: ProjectModel
                if url.pathExtension.lowercased() == "mppplan" {
                    let data = try Data(contentsOf: tempURL)
                    let nativePlan = try NativeProjectPlan.decode(from: data)
                    model = nativePlan.asProjectModel()
                } else {
                    let converter = MPPConverterService()
                    let jsonData = try await converter.convert(mppFileURL: tempURL)
                    model = try await JSONProjectParser.parseDetached(jsonData: jsonData)
                }
                try? FileManager.default.removeItem(at: tempURL)

                let analysis = ProjectDiffCalculator.analyze(baseline: model, current: project)

                await MainActor.run {
                    baselineProject = model
                    diffs = analysis.diffs
                    diffSummary = analysis.summary
                    isLoading = false
                }
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    diffSummary = nil
                    isLoading = false
                }
            }
        }
    }

    private func diffSummaryCard(title: String, value: String, subtitle: String, color: Color, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func finishDeltaView(_ deltaDays: Int?) -> some View {
        if let deltaDays {
            Text(deltaDays > 0 ? "+\(deltaDays)d" : "\(deltaDays)d")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(deltaDays > 0 ? .red : .green)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background((deltaDays > 0 ? Color.red : Color.green).opacity(0.12))
                .clipShape(Capsule())
        } else {
            Text("-")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func costDeltaView(_ delta: Double?) -> some View {
        if let delta {
            Text(formattedCurrencyDelta(delta))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(costDeltaColor(delta))
        } else {
            Text("-")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func criticalityDeltaView(_ delta: CriticalityDelta) -> some View {
        switch delta {
        case .none:
            Text("-")
                .foregroundStyle(.secondary)
        case .entered:
            diffPill("Entered", color: .red)
        case .exited:
            diffPill("Exited", color: .green)
        }
    }

    private func diffPill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func finishDeltaValue(_ deltaDays: Int?) -> String {
        guard let deltaDays else { return "No project finish date" }
        if deltaDays == 0 { return "No finish change" }
        return deltaDays > 0 ? "+\(deltaDays)d later" : "\(deltaDays)d earlier"
    }

    private func finishDeltaSubtitle(_ summary: ProjectDiffSummary) -> String {
        let largestSlip = summary.largestFinishSlip.map { "\($0.taskName) +\($0.deltaDays)d" } ?? "No slipped finish dates"
        return "\(summary.finishMovedLaterCount) later, \(summary.finishMovedEarlierCount) earlier. Biggest slip: \(largestSlip)"
    }

    private func finishDeltaColor(_ deltaDays: Int?) -> Color {
        guard let deltaDays else { return .secondary }
        if deltaDays > 0 { return .red }
        if deltaDays < 0 { return .green }
        return .secondary
    }

    private func formattedCurrencyDelta(_ value: Double) -> String {
        let amount = CurrencyFormatting.string(from: abs(value), maximumFractionDigits: 2, minimumFractionDigits: 0)
        if value == 0 { return "No cost change" }
        return value > 0 ? "+\(amount)" : "-\(amount)"
    }

    private func costDeltaColor(_ value: Double) -> Color {
        if value > 0 { return .red }
        if value < 0 { return .green }
        return .secondary
    }

    private func criticalDeltaValue(_ summary: ProjectDiffSummary) -> String {
        if summary.criticalAddedCount == 0 && summary.criticalRemovedCount == 0 {
            return "No critical churn"
        }
        return "+\(summary.criticalAddedCount) / -\(summary.criticalRemovedCount)"
    }

    private func criticalDeltaSubtitle(_ summary: ProjectDiffSummary) -> String {
        let entered = summary.enteredCriticalTasks.prefix(2).joined(separator: ", ")
        let exited = summary.exitedCriticalTasks.prefix(2).joined(separator: ", ")

        if !entered.isEmpty {
            return "Now \(summary.currentCriticalCount) critical. Entered: \(entered)"
        }
        if !exited.isEmpty {
            return "Now \(summary.currentCriticalCount) critical. Exited: \(exited)"
        }
        return "Current critical tasks: \(summary.currentCriticalCount)"
    }

    private func criticalDeltaColor(_ summary: ProjectDiffSummary) -> Color {
        if summary.criticalAddedCount > 0 { return .red }
        if summary.criticalRemovedCount > 0 { return .green }
        return .secondary
    }

    private func largestSlipValue(_ summary: ProjectDiffSummary) -> String {
        guard let largestFinishSlip = summary.largestFinishSlip else { return "No slipped tasks" }
        return "+\(largestFinishSlip.deltaDays)d"
    }

    private func largestSlipSubtitle(_ summary: ProjectDiffSummary) -> String {
        summary.largestFinishSlip?.taskName ?? "No finish movement to summarize"
    }
}
