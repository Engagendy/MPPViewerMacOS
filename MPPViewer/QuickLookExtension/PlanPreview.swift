import SwiftUI

/// A self-contained, lightweight reader for `.mppplan` files used only by the
/// Quick Look preview. It decodes just the handful of fields the preview needs
/// so the extension stays small and fast and doesn't depend on the app's full
/// data model.
struct PlanPreview {
    var title: String
    var manager: String?
    var company: String?
    var taskCount: Int
    var milestoneCount: Int
    var percentComplete: Int
    var startDate: Date?
    var finishDate: Date?
    var milestones: [Milestone]

    struct Milestone: Identifiable {
        let id = UUID()
        let name: String
        let date: Date?
    }

    private struct RawPlan: Decodable {
        var title: String?
        var manager: String?
        var company: String?
        var tasks: [RawTask]?
    }

    private struct RawTask: Decodable {
        var name: String?
        var startDate: Date?
        var finishDate: Date?
        var isMilestone: Bool?
        var percentComplete: Double?
        var outlineLevel: Int?
    }

    static func load(from url: URL) -> PlanPreview? {
        guard let rawData = try? Data(contentsOf: url) else { return nil }
        // Tolerate a UTF-8 BOM just in case.
        let data = rawData.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(rawData.dropFirst(3)) : rawData

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let plan = try? decoder.decode(RawPlan.self, from: data) else { return nil }

        let tasks = plan.tasks ?? []
        let leafTasks = tasks.filter { ($0.isMilestone ?? false) == false }
        let milestoneTasks = tasks.filter { $0.isMilestone ?? false }

        let completions = leafTasks.compactMap { $0.percentComplete }
        let averageComplete = completions.isEmpty ? 0 : completions.reduce(0, +) / Double(completions.count)

        let starts = tasks.compactMap { $0.startDate }
        let finishes = tasks.compactMap { $0.finishDate }

        let milestones = milestoneTasks
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            .prefix(12)
            .map { Milestone(name: $0.name ?? "Milestone", date: $0.startDate ?? $0.finishDate) }

        return PlanPreview(
            title: plan.title?.isEmpty == false ? plan.title! : url.deletingPathExtension().lastPathComponent,
            manager: plan.manager?.isEmpty == false ? plan.manager : nil,
            company: plan.company?.isEmpty == false ? plan.company : nil,
            taskCount: leafTasks.count,
            milestoneCount: milestoneTasks.count,
            percentComplete: Int(averageComplete.rounded()),
            startDate: starts.min(),
            finishDate: finishes.max(),
            milestones: Array(milestones)
        )
    }
}

/// The visual Quick Look card: project header, key metrics, and a milestone
/// timeline. Kept intentionally simple and legible for a Finder preview.
struct PlanPreviewView: View {
    let plan: PlanPreview

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            metrics
            if !plan.milestones.isEmpty {
                milestoneList
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundStyle(.tint)
                Text(plan.title)
                    .font(.system(size: 24, weight: .bold))
                    .lineLimit(2)
            }
            let subtitle = [plan.company, plan.manager].compactMap { $0 }.joined(separator: " · ")
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            metricChip(value: "\(plan.taskCount)", label: "Tasks")
            metricChip(value: "\(plan.milestoneCount)", label: "Milestones")
            metricChip(value: "\(plan.percentComplete)%", label: "Complete")
            if let range = dateRangeText {
                metricChip(value: range, label: "Schedule", wide: true)
            }
        }
    }

    private var dateRangeText: String? {
        switch (plan.startDate, plan.finishDate) {
        case let (start?, finish?):
            return "\(Self.dateFormatter.string(from: start)) – \(Self.dateFormatter.string(from: finish))"
        case let (start?, nil):
            return Self.dateFormatter.string(from: start)
        case let (nil, finish?):
            return Self.dateFormatter.string(from: finish)
        default:
            return nil
        }
    }

    private func metricChip(value: String, label: String, wide: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: wide ? 15 : 20, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: wide ? 220 : 90, alignment: .leading)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private var milestoneList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Milestones")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.milestones) { milestone in
                    HStack(spacing: 8) {
                        Image(systemName: "diamond.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(milestone.name)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        if let date = milestone.date {
                            Text(Self.dateFormatter.string(from: date))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .font(.callout)
                }
            }
        }
    }
}
