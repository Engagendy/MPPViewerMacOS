import SwiftUI
import UniformTypeIdentifiers

struct DiffView: View {
    let project: ProjectModel

    @State private var baselineProject: ProjectModel?
    @State private var baselineFileName: String?
    @State private var diffs: [TaskDiff] = []
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
                // Summary bar
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
            allowedContentTypes: [UTType(filenameExtension: "mpp") ?? .data],
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
            .appendingPathExtension("mpp")
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
                let converter = MPPConverterService()
                let jsonData = try await converter.convert(mppFileURL: tempURL)
                try? FileManager.default.removeItem(at: tempURL)

                let parser = JSONProjectParser()
                let model = try parser.parse(jsonData: jsonData)

                await MainActor.run {
                    baselineProject = model
                    diffs = ProjectDiffCalculator.diff(baseline: model, current: project)
                    isLoading = false
                }
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
