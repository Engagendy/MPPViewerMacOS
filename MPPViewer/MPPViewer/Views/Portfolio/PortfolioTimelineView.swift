import SwiftUI
import SwiftData
import AppKit

/// Portfolio-level Gantt: one summary bar per registered project
/// (start→finish rollup, health/stage coloring from governance metadata),
/// optional milestone diamonds, and cross-project dependency links drawn
/// between project bars. Zoom follows the shared Gantt idiom
/// (pixels-per-day + GanttZoomControls + pinch).
struct PortfolioTimelineView: View {
    let plans: [PortfolioProjectPlan]
    let dependencies: [PortfolioCrossProjectDependency]
    @Binding var selectedPlanID: UUID?

    @State private var pixelsPerDay: CGFloat = 6
    @State private var showMilestones = true
    @State private var showDependencies = true
    @State private var didFitInitialZoom = false

    private struct TimelineMilestone: Identifiable {
        let id: UUID
        let name: String
        let date: Date
    }

    private struct TimelineRow: Identifiable {
        let planID: UUID
        let title: String
        let health: String?
        let stage: String?
        let startDate: Date
        let finishDate: Date
        let averagePercentComplete: Double
        let milestones: [TimelineMilestone]
        /// Task anchor dates used to place cross-project dependency endpoints.
        let taskStartDates: [UUID: Date]
        let taskFinishDates: [UUID: Date]

        var id: UUID { planID }
    }

    private struct DependencyLink: Identifiable {
        let id: UUID
        let sourceRowIndex: Int
        let targetRowIndex: Int
        let sourceDate: Date
        let targetDate: Date
        let relationType: String
    }

    private static let rowHeight: CGFloat = 36
    private static let headerHeight: CGFloat = 26
    private static let labelWidth: CGFloat = 230
    private static let barHeight: CGFloat = 16
    private static let paddingDays = 7

    private var rows: [TimelineRow] {
        plans.compactMap { plan in
            let tasks = plan.tasks.filter { $0.isActive }
            guard let start = tasks.map(\.startDate).min(),
                  let finish = tasks.map(\.finishDate).max() else {
                return nil
            }
            let milestones = tasks
                .filter(\.isMilestone)
                .map { TimelineMilestone(id: $0.uniqueID, name: $0.name, date: $0.finishDate) }
                .sorted { $0.date < $1.date }
            let completion = tasks.isEmpty
                ? 0
                : tasks.map(\.percentComplete).reduce(0, +) / Double(tasks.count)
            return TimelineRow(
                planID: plan.portfolioID,
                title: trimmedOrFallback(plan.title, fallback: "Untitled Plan"),
                health: normalizedMetadata(plan.portfolioHealth),
                stage: normalizedMetadata(plan.portfolioStage),
                startDate: min(start, finish),
                finishDate: max(start, finish),
                averagePercentComplete: completion,
                milestones: milestones,
                taskStartDates: Dictionary(uniqueKeysWithValues: tasks.map { ($0.uniqueID, $0.startDate) }),
                taskFinishDates: Dictionary(uniqueKeysWithValues: tasks.map { ($0.uniqueID, $0.finishDate) })
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }

    private func dependencyLinks(for rows: [TimelineRow]) -> [DependencyLink] {
        let rowIndexByPlanID = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.planID, $0.offset) })
        return dependencies.compactMap { dependency in
            guard let sourceIndex = rowIndexByPlanID[dependency.sourcePlanID],
                  let targetIndex = rowIndexByPlanID[dependency.targetPlanID],
                  sourceIndex != targetIndex else {
                return nil
            }
            let sourceRow = rows[sourceIndex]
            let targetRow = rows[targetIndex]
            let sourceDate = sourceRow.taskFinishDates[dependency.sourceTaskUniqueID] ?? sourceRow.finishDate
            let targetDate = targetRow.taskStartDates[dependency.targetTaskUniqueID] ?? targetRow.startDate
            return DependencyLink(
                id: dependency.uniqueID,
                sourceRowIndex: sourceIndex,
                targetRowIndex: targetIndex,
                sourceDate: sourceDate,
                targetDate: targetDate,
                relationType: dependency.relationType
            )
        }
    }

    private func timelineRange(for rows: [TimelineRow]) -> (start: Date, totalDays: Int)? {
        guard let earliest = rows.map(\.startDate).min(),
              let latest = rows.flatMap({ [$0.finishDate] + $0.milestones.map(\.date) }).max() else {
            return nil
        }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -Self.paddingDays, to: calendar.startOfDay(for: earliest)) ?? earliest
        let end = calendar.date(byAdding: .day, value: Self.paddingDays, to: calendar.startOfDay(for: latest)) ?? latest
        let days = max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 1) + 1)
        return (start, days)
    }

    var body: some View {
        let rows = rows
        if rows.isEmpty {
            ContentUnavailableView(
                "No scheduled projects",
                systemImage: "chart.bar.xaxis",
                description: Text("Register plans with scheduled tasks to see the portfolio timeline.")
            )
            .frame(maxWidth: .infinity, minHeight: 140)
        } else if let range = timelineRange(for: rows) {
            let links = dependencyLinks(for: rows)
            VStack(alignment: .leading, spacing: 10) {
                controlBar(totalDays: range.totalDays)

                HStack(alignment: .top, spacing: 0) {
                    labelColumn(rows: rows)
                        .frame(width: Self.labelWidth, alignment: .leading)

                    Divider()

                    ScrollView(.horizontal, showsIndicators: true) {
                        timelineCanvas(rows: rows, links: links, rangeStart: range.start, totalDays: range.totalDays)
                            .frame(
                                width: CGFloat(range.totalDays) * pixelsPerDay,
                                height: Self.headerHeight + CGFloat(rows.count) * Self.rowHeight
                            )
                    }
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                pixelsPerDay = min(100, max(2, pixelsPerDay * value.magnification))
                            }
                    )
                }
                .frame(height: Self.headerHeight + CGFloat(rows.count) * Self.rowHeight)

                legend(links: links)
            }
            .onAppear {
                guard !didFitInitialZoom else { return }
                didFitInitialZoom = true
                pixelsPerDay = max(2, min(100, 900.0 / CGFloat(max(range.totalDays, 1))))
            }
        }
    }

    private func controlBar(totalDays: Int) -> some View {
        HStack(spacing: 12) {
            Toggle("Milestones", isOn: $showMilestones)
                .toggleStyle(.checkbox)
                .font(.caption)
            Toggle("Dependencies", isOn: $showDependencies)
                .toggleStyle(.checkbox)
                .font(.caption)
            Spacer()
            GanttZoomControls(pixelsPerDay: $pixelsPerDay, totalDays: totalDays)
        }
    }

    private func labelColumn(rows: [TimelineRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Project")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(height: Self.headerHeight)

            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Circle()
                        .fill(healthColor(for: row.health))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text(row.stage ?? "No stage")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .frame(height: Self.rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selectedPlanID == row.planID ? Color.accentColor.opacity(0.14) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPlanID = row.planID
                }
                .help("\(row.title) — \(row.startDate.formatted(date: .abbreviated, time: .omitted)) → \(row.finishDate.formatted(date: .abbreviated, time: .omitted))")
            }
        }
    }

    private func timelineCanvas(rows: [TimelineRow], links: [DependencyLink], rangeStart: Date, totalDays: Int) -> some View {
        Canvas { context, size in
            let calendar = Calendar.current

            func xPosition(for date: Date) -> CGFloat {
                let days = calendar.dateComponents([.day], from: rangeStart, to: calendar.startOfDay(for: date)).day ?? 0
                return CGFloat(days) * pixelsPerDay
            }

            func rowMidY(_ index: Int) -> CGFloat {
                Self.headerHeight + CGFloat(index) * Self.rowHeight + Self.rowHeight / 2
            }

            // Month grid + header labels.
            var monthCursor = calendar.date(from: calendar.dateComponents([.year, .month], from: rangeStart)) ?? rangeStart
            let rangeEnd = calendar.date(byAdding: .day, value: totalDays, to: rangeStart) ?? rangeStart
            let monthFormatter = pixelsPerDay >= 4 ? Date.FormatStyle().month(.abbreviated).year(.twoDigits) : Date.FormatStyle().month(.narrow)
            while monthCursor < rangeEnd {
                let x = xPosition(for: monthCursor)
                if x >= 0 {
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: Self.headerHeight))
                    line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: .color(Color.secondary.opacity(0.18)), lineWidth: 1)

                    let label = Text(monthCursor.formatted(monthFormatter))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    context.draw(context.resolve(label), at: CGPoint(x: x + 4, y: Self.headerHeight / 2), anchor: .leading)
                }
                monthCursor = calendar.date(byAdding: .month, value: 1, to: monthCursor) ?? rangeEnd
            }

            // Row separators.
            for index in 0...rows.count {
                let y = Self.headerHeight + CGFloat(index) * Self.rowHeight
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(Color.secondary.opacity(0.1)), lineWidth: 1)
            }

            // Today marker.
            let todayX = xPosition(for: Date())
            if todayX >= 0, todayX <= size.width {
                var line = Path()
                line.move(to: CGPoint(x: todayX, y: Self.headerHeight))
                line.addLine(to: CGPoint(x: todayX, y: size.height))
                context.stroke(line, with: .color(.red.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            // Project summary bars.
            for (index, row) in rows.enumerated() {
                let startX = xPosition(for: row.startDate)
                let endX = max(startX + 3, xPosition(for: row.finishDate) + pixelsPerDay)
                let midY = rowMidY(index)
                let barRect = CGRect(
                    x: startX,
                    y: midY - Self.barHeight / 2,
                    width: endX - startX,
                    height: Self.barHeight
                )
                let barColor = healthColor(for: row.health)
                let barPath = Path(roundedRect: barRect, cornerRadius: 4)
                context.fill(barPath, with: .color(barColor.opacity(0.32)))

                // Completion fill inside the summary bar.
                let progressWidth = barRect.width * min(1, max(0, row.averagePercentComplete / 100))
                if progressWidth > 1 {
                    let progressRect = CGRect(x: barRect.minX, y: barRect.minY, width: progressWidth, height: barRect.height)
                    context.fill(Path(roundedRect: progressRect, cornerRadius: 4), with: .color(barColor.opacity(0.75)))
                }
                context.stroke(barPath, with: .color(barColor.opacity(0.9)), lineWidth: selectedPlanID == row.planID ? 2 : 1)

                // Stage caption alongside the bar when there is room.
                if let stage = row.stage, pixelsPerDay >= 3 {
                    let label = Text(stage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    context.draw(context.resolve(label), at: CGPoint(x: barRect.maxX + 6, y: midY), anchor: .leading)
                }

                // Milestone diamonds.
                if showMilestones {
                    for milestone in row.milestones {
                        let x = xPosition(for: milestone.date) + pixelsPerDay / 2
                        let diamondSize: CGFloat = 8
                        var diamond = Path()
                        diamond.move(to: CGPoint(x: x, y: midY - diamondSize / 2))
                        diamond.addLine(to: CGPoint(x: x + diamondSize / 2, y: midY))
                        diamond.addLine(to: CGPoint(x: x, y: midY + diamondSize / 2))
                        diamond.addLine(to: CGPoint(x: x - diamondSize / 2, y: midY))
                        diamond.closeSubpath()
                        context.fill(diamond, with: .color(.purple))
                        context.stroke(diamond, with: .color(.white.opacity(0.8)), lineWidth: 0.5)
                    }
                }
            }

            // Cross-project dependency links.
            if showDependencies {
                for link in links {
                    let startPoint = CGPoint(
                        x: xPosition(for: link.sourceDate) + pixelsPerDay,
                        y: rowMidY(link.sourceRowIndex)
                    )
                    let endPoint = CGPoint(
                        x: xPosition(for: link.targetDate),
                        y: rowMidY(link.targetRowIndex)
                    )
                    var path = Path()
                    path.move(to: startPoint)
                    let elbow = max(14, abs(endPoint.x - startPoint.x) / 3)
                    path.addCurve(
                        to: endPoint,
                        control1: CGPoint(x: startPoint.x + elbow, y: startPoint.y),
                        control2: CGPoint(x: endPoint.x - elbow, y: endPoint.y)
                    )
                    context.stroke(path, with: .color(.indigo.opacity(0.75)), style: StrokeStyle(lineWidth: 1.5))

                    // Arrowhead at the target end.
                    let arrowSize: CGFloat = 5
                    var arrow = Path()
                    arrow.move(to: endPoint)
                    arrow.addLine(to: CGPoint(x: endPoint.x - arrowSize, y: endPoint.y - arrowSize))
                    arrow.addLine(to: CGPoint(x: endPoint.x - arrowSize, y: endPoint.y + arrowSize))
                    arrow.closeSubpath()
                    context.fill(arrow, with: .color(.indigo.opacity(0.85)))
                }
            }
        }
    }

    private func legend(links: [DependencyLink]) -> some View {
        HStack(spacing: 14) {
            legendSwatch(color: .green, label: "Green")
            legendSwatch(color: .orange, label: "Amber")
            legendSwatch(color: .red, label: "Red")
            legendSwatch(color: .secondary, label: "On Hold / Unset")
            if showMilestones {
                HStack(spacing: 4) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.purple)
                    Text("Milestone")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if showDependencies {
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(Color.indigo.opacity(0.75))
                        .frame(width: 14, height: 2)
                    Text("Cross-project link (\(links.count))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func legendSwatch(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.6))
                .frame(width: 14, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func healthColor(for rawHealth: String?) -> Color {
        switch rawHealth?.lowercased() {
        case "green":
            return .green
        case "amber":
            return .orange
        case "red":
            return .red
        default:
            return .secondary
        }
    }

    private func normalizedMetadata(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func trimmedOrFallback(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
