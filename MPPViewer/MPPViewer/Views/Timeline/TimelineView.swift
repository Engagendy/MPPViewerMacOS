import SwiftUI

struct TimelineView: View {
    let project: ProjectModel

    @State private var pixelsPerDay: CGFloat = 10
    @State private var timelineViewportWidth: CGFloat = 0
    @State private var shouldAutoFitTimeline = true
    @State private var preparedData: TimelinePreparedData?
    @State private var criticalPathOnly: Bool = false
    @State private var showDependencyLinks: Bool = true
    @State private var showBaseline: Bool = false
    @Environment(\.colorScheme) var colorScheme

    private let rowHeight: CGFloat = 44

    private let phaseColors: [Color] = [
        .blue, .purple, .teal, .indigo, .cyan, .green, .orange, .mint, .pink, .brown
    ]

    var body: some View {
        VStack(spacing: 0) {
            if let data = preparedData {
                // Toolbar
                HStack {
                    Image(systemName: "rectangle.split.3x1")
                        .foregroundStyle(.secondary)
                    Text("Timeline")
                        .font(.headline)

                    Spacer()

                    HStack(spacing: 12) {
                        Label("\(data.summaryCount) phases", systemImage: "folder.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label("\(data.milestoneCount) milestones", systemImage: "diamond.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider().frame(height: 16)

                    Toggle(isOn: $criticalPathOnly) {
                        Label("Critical Path", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                    }
                    .toggleStyle(.button)
                    .hoverHighlight()
                    .buttonStyle(.bordered)
                    .tint(criticalPathOnly ? .red : nil)
                    .help("Highlights critical timeline items and dims non-critical items.")

                    Toggle(isOn: $showDependencyLinks) {
                        Label("Links", systemImage: "link")
                            .font(.caption)
                    }
                    .toggleStyle(.button)
                    .hoverHighlight()
                    .buttonStyle(.bordered)
                    .tint(showDependencyLinks ? .blue : nil)
                    .help("Shows predecessor and successor dependency links between visible timeline items.")

                    Toggle(isOn: $showBaseline) {
                        Label("Baseline", systemImage: "clock.arrow.2.circlepath")
                            .font(.caption)
                    }
                    .toggleStyle(.button)
                    .hoverHighlight()
                    .buttonStyle(.bordered)
                    .tint(showBaseline ? .gray : nil)

                    Divider().frame(height: 16)

                    GanttZoomControls(
                        pixelsPerDay: pixelsPerDay,
                        totalDays: data.totalDays,
                        onFitAll: {
                            shouldAutoFitTimeline = true
                            applyAutoFitIfNeeded(totalDays: data.totalDays)
                        },
                        onShowWeek: {
                            shouldAutoFitTimeline = false
                            pixelsPerDay = 40
                        },
                        onShowMonth: {
                            shouldAutoFitTimeline = false
                            pixelsPerDay = 10
                        },
                        onZoomOut: {
                            shouldAutoFitTimeline = false
                            pixelsPerDay = max(2, pixelsPerDay / 1.5)
                        },
                        onZoomIn: {
                            shouldAutoFitTimeline = false
                            pixelsPerDay = min(100, pixelsPerDay * 1.5)
                        }
                    )
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)

                Divider()

                if data.items.isEmpty {
                    ContentUnavailableView("No Summary Tasks", systemImage: "rectangle.split.3x1",
                        description: Text("No summary tasks or milestones found."))
                        .topAlignedEmptyState()
                } else {
                    // Trailing area past the last activity keeps the final
                    // phase/milestone labels readable, matching the Gantt view.
                    let timelineWidth = CGFloat(data.totalDays) * pixelsPerDay + 420
                    let contentHeight = CGFloat(data.items.count) * rowHeight

                    GeometryReader { geometry in
                        let viewportWidth = max(geometry.size.width, 1)

                        ScrollView([.horizontal, .vertical]) {
                            VStack(alignment: .leading, spacing: 0) {
                                GanttHeaderView(
                                    dateRange: (data.startDate, data.endDate),
                                    pixelsPerDay: pixelsPerDay,
                                    totalWidth: timelineWidth
                                )

                                Canvas { context, size in
                                    drawTimeline(context: context, size: size, data: data)
                                }
                                .frame(width: timelineWidth, height: contentHeight)
                            }
                            .frame(minHeight: geometry.size.height, alignment: .topLeading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .onAppear {
                            timelineViewportWidth = viewportWidth
                            applyAutoFitIfNeeded(totalDays: data.totalDays)
                        }
                        .onChange(of: viewportWidth) { _, newWidth in
                            timelineViewportWidth = newWidth
                            applyAutoFitIfNeeded(totalDays: data.totalDays)
                        }
                        .onChange(of: data.totalDays) { _, newTotalDays in
                            applyAutoFitIfNeeded(totalDays: newTotalDays)
                        }
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            preparedData = prepareData()
        }
    }

    private func applyAutoFitIfNeeded(totalDays: Int) {
        guard shouldAutoFitTimeline, timelineViewportWidth > 0 else { return }
        pixelsPerDay = fittedPixelsPerDay(for: timelineViewportWidth, totalDays: totalDays)
    }

    private func fittedPixelsPerDay(for viewportWidth: CGFloat, totalDays: Int) -> CGFloat {
        max(2, min(100, viewportWidth / CGFloat(max(totalDays, 1))))
    }

    // MARK: - Pre-compute all data once

    private func prepareData() -> TimelinePreparedData {
        let timelineTasks: [ProjectTask] = {
            let emphasized = project.tasks.filter { $0.summary == true || $0.isDisplayMilestone }
            if !emphasized.isEmpty {
                return emphasized
            }
            // Native plans and smaller schedules may not have summary tasks yet.
            // Fall back to showing all top-level tasks so the timeline remains useful.
            if !project.rootTasks.isEmpty {
                return project.rootTasks
            }
            return project.tasks
        }()
        let range = GanttDateHelpers.dateRange(for: project.tasks)
        let totalDays = GanttDateHelpers.totalDays(for: range)
        let calendar = Calendar.current

        // Build level-1 task index lookup once
        let level1Tasks = project.tasks.filter { ($0.outlineLevel ?? 0) <= 1 && $0.summary == true }
        var level1Index: [Int: Int] = [:]
        for (i, t) in level1Tasks.enumerated() {
            level1Index[t.uniqueID] = i
        }

        // Cache ancestor lookups
        var ancestorCache: [Int: Int] = [:]

        func topAncestorID(_ task: ProjectTask) -> Int {
            if let cached = ancestorCache[task.uniqueID] { return cached }
            var current = task
            while let parentID = current.parentTaskUniqueID,
                  let parent = project.tasksByID[parentID],
                  (parent.outlineLevel ?? 0) >= 1 {
                current = parent
            }
            ancestorCache[task.uniqueID] = current.uniqueID
            return current.uniqueID
        }

        var items: [TimelineItem] = []
        var currentTopLevelID: Int? = nil
        var laneIndex = 0

        for task in timelineTasks {
            let topID = topAncestorID(task)
            if topID != currentTopLevelID {
                currentTopLevelID = topID
                laneIndex += 1
            }

            let colorIdx = level1Index[topID] ?? 0
            let color = phaseColors[colorIdx % phaseColors.count]

            var startDayOffset: Int = 0
            var endDayOffset: Int = 0
            if let s = task.startDate {
                startDayOffset = calendar.dateComponents([.day], from: range.start, to: s).day ?? 0
            }
            if let f = task.finishDate {
                endDayOffset = calendar.dateComponents([.day], from: range.start, to: f).day ?? 0
            }

            items.append(TimelineItem(
                uniqueID: task.uniqueID,
                name: task.displayName,
                isMilestone: task.isDisplayMilestone,
                isSummary: task.summary == true,
                outlineLevel: task.outlineLevel ?? 1,
                percentComplete: task.percentComplete ?? 0,
                startDayOffset: startDayOffset,
                endDayOffset: endDayOffset,
                hasStart: task.startDate != nil,
                hasEnd: task.finishDate != nil,
                startDateStr: task.startDate.map { _ in DateFormatting.shortDate(task.start) } ?? "",
                endDateStr: task.finishDate.map { _ in DateFormatting.shortDate(task.finish) } ?? "",
                baselineStartDayOffset: task.baselineStartDate.map { calendar.dateComponents([.day], from: range.start, to: $0).day ?? 0 },
                baselineEndDayOffset: task.baselineFinishDate.map { calendar.dateComponents([.day], from: range.start, to: $0).day ?? 0 },
                baselineDescriptor: task.baselineVarianceDescriptor,
                predecessorIDs: task.predecessors?.map(\.targetTaskUniqueID) ?? [],
                color: color,
                laneIndex: laneIndex,
                isLevel1: (task.outlineLevel ?? 1) <= 1 && task.summary == true,
                isCritical: task.critical == true
            ))
        }

        let itemIndexByID = Dictionary(nonThrowingUniquePairs: items.enumerated().map { ($1.uniqueID, $0) })
        let dependencies = items.flatMap { item -> [TimelineDependency] in
            item.predecessorIDs.compactMap { predecessorID in
                guard itemIndexByID[predecessorID] != nil else { return nil }
                return TimelineDependency(predecessorID: predecessorID, successorID: item.uniqueID)
            }
        }

        return TimelinePreparedData(
            items: items,
            dependencies: dependencies,
            startDate: range.start,
            endDate: range.end,
            totalDays: totalDays,
            summaryCount: timelineTasks.filter { $0.summary == true }.count,
            milestoneCount: timelineTasks.filter { $0.isDisplayMilestone }.count
        )
    }

    // MARK: - Canvas Drawing (uses pre-computed data only)

    private func drawTimeline(context: GraphicsContext, size: CGSize, data: TimelinePreparedData) {
        let isDark = colorScheme == .dark

        if showDependencyLinks {
            drawTimelineLinks(context: context, data: data)
        }

        for (index, item) in data.items.enumerated() {
            let y = CGFloat(index) * rowHeight
            let itemOpacity = (!criticalPathOnly || item.isCritical) ? 1.0 : 0.18

            // Alternating lane tint
            if item.laneIndex % 2 == 0 {
                let bg = CGRect(x: 0, y: y, width: size.width, height: rowHeight)
                context.fill(Path(bg), with: .color(item.color.opacity(isDark ? 0.06 : 0.03)))
            }

            // Row separator
            var sep = Path()
            sep.move(to: CGPoint(x: 0, y: y + rowHeight))
            sep.addLine(to: CGPoint(x: size.width, y: y + rowHeight))
            context.stroke(sep, with: .color(.gray.opacity(isDark ? 0.15 : 0.08)), lineWidth: 0.5)

            // Phase separator
            if item.isLevel1 {
                var topSep = Path()
                topSep.move(to: CGPoint(x: 0, y: y))
                topSep.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(topSep, with: .color(item.color.opacity(0.3)), lineWidth: 1)
            }

            let markerStyle = StrokeStyle(lineWidth: 1, dash: [3, 3])
            if let baselineStart = item.baselineStartDayOffset {
                let xBase = CGFloat(baselineStart) * pixelsPerDay
                var startLine = Path()
                startLine.move(to: CGPoint(x: xBase, y: y + rowHeight * 0.2))
                startLine.addLine(to: CGPoint(x: xBase, y: y + rowHeight * 0.8))
                context.stroke(startLine, with: .color(.gray.opacity(0.55)), style: markerStyle)
            }
            if let baselineEnd = item.baselineEndDayOffset {
                let xEnd = CGFloat(baselineEnd) * pixelsPerDay
                var endLine = Path()
                endLine.move(to: CGPoint(x: xEnd, y: y + rowHeight * 0.2))
                endLine.addLine(to: CGPoint(x: xEnd, y: y + rowHeight * 0.8))
                context.stroke(endLine, with: .color(.gray.opacity(0.55)), style: markerStyle)
            }

            guard item.hasStart else { continue }
            let xStart = CGFloat(item.startDayOffset) * pixelsPerDay
            let baselineBadgeAnchorX: CGFloat? = {
                guard item.baselineDescriptor?.days != 0 else { return nil }
                if item.isMilestone {
                    return xStart + 12
                }
                if item.hasEnd {
                    let width = CGFloat(max(1, item.endDayOffset - item.startDayOffset)) * pixelsPerDay
                    return xStart + width + 6
                }
                return xStart + 6
            }()

            if showBaseline, let baselineStart = item.baselineStartDayOffset {
                let xBase = CGFloat(baselineStart) * pixelsPerDay
                if item.isMilestone {
                    var basePath = Path()
                    let cy = y + rowHeight / 2
                    let size: CGFloat = 8
                    basePath.move(to: CGPoint(x: xBase, y: cy - size / 2))
                    basePath.addLine(to: CGPoint(x: xBase + size / 2, y: cy))
                    basePath.addLine(to: CGPoint(x: xBase, y: cy + size / 2))
                    basePath.addLine(to: CGPoint(x: xBase - size / 2, y: cy))
                    basePath.closeSubpath()
                    context.stroke(basePath, with: .color(.gray.opacity(0.55)), lineWidth: 1)
                } else if item.isSummary, let baselineEnd = item.baselineEndDayOffset {
                    let baselineWidth = max(6, CGFloat(max(1, baselineEnd - baselineStart)) * pixelsPerDay)
                    let baselineRect = CGRect(x: xBase, y: y + rowHeight * 0.68, width: baselineWidth, height: 4)
                    let baselinePath = RoundedRectangle(cornerRadius: 2).path(in: baselineRect)
                    context.fill(baselinePath, with: .color(.gray.opacity(isDark ? 0.45 : 0.25)))
                }
            }

            if item.isMilestone {
                drawMilestone(context: context, item: item, x: xStart, y: y, opacity: itemOpacity)
            } else if item.isSummary {
                guard item.hasEnd else { continue }
                let barWidth = max(6, CGFloat(max(1, item.endDayOffset - item.startDayOffset)) * pixelsPerDay)
                drawBar(context: context, item: item, x: xStart, y: y, width: barWidth, isDark: isDark, opacity: itemOpacity)
            }

            if let anchorX = baselineBadgeAnchorX,
               let descriptor = item.baselineDescriptor,
               descriptor.days != 0 {
                drawTimelineBaselineBadge(context: context, descriptor: descriptor, anchorX: anchorX, y: y)
            }
        }

        // Today line
        if let todayOffset = GanttDateHelpers.todayDayOffset(from: data.startDate) {
            let todayX = todayOffset * pixelsPerDay
            if todayX >= 0 && todayX <= size.width {
                var todayLine = Path()
                todayLine.move(to: CGPoint(x: todayX, y: 0))
                todayLine.addLine(to: CGPoint(x: todayX, y: size.height))
                context.stroke(todayLine, with: .color(.red), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        }
    }

    private func drawTimelineLinks(context: GraphicsContext, data: TimelinePreparedData) {
        let indexByID = Dictionary(nonThrowingUniquePairs: data.items.enumerated().map { ($1.uniqueID, $0) })
        for dependency in data.dependencies {
            guard let predecessorIndex = indexByID[dependency.predecessorID],
                  let successorIndex = indexByID[dependency.successorID] else { continue }
            let predecessor = data.items[predecessorIndex]
            let successor = data.items[successorIndex]
            guard predecessor.hasStart, successor.hasStart else { continue }

            let startX = CGFloat(predecessor.hasEnd ? predecessor.endDayOffset : predecessor.startDayOffset) * pixelsPerDay
            let startY = CGFloat(predecessorIndex) * rowHeight + rowHeight / 2
            let endX = CGFloat(successor.startDayOffset) * pixelsPerDay
            let endY = CGFloat(successorIndex) * rowHeight + rowHeight / 2
            let midX = startX + 10

            var path = Path()
            path.move(to: CGPoint(x: startX, y: startY))
            path.addLine(to: CGPoint(x: midX, y: startY))
            path.addLine(to: CGPoint(x: midX, y: endY))
            path.addLine(to: CGPoint(x: endX, y: endY))
            context.stroke(path, with: .color(.secondary.opacity(0.55)), style: StrokeStyle(lineWidth: 1.1))

            var head = Path()
            head.move(to: CGPoint(x: endX, y: endY))
            head.addLine(to: CGPoint(x: endX - 4, y: endY - 4))
            head.addLine(to: CGPoint(x: endX - 4, y: endY + 4))
            head.closeSubpath()
            context.fill(head, with: .color(.secondary.opacity(0.55)))
        }
    }

    private func drawMilestone(context: GraphicsContext, item: TimelineItem, x: CGFloat, y: CGFloat, opacity: Double) {
        let cy = y + rowHeight / 2
        let dSize: CGFloat = 12

        var diamond = Path()
        diamond.move(to: CGPoint(x: x, y: cy - dSize / 2))
        diamond.addLine(to: CGPoint(x: x + dSize / 2, y: cy))
        diamond.addLine(to: CGPoint(x: x, y: cy + dSize / 2))
        diamond.addLine(to: CGPoint(x: x - dSize / 2, y: cy))
        diamond.closeSubpath()
        context.fill(diamond, with: .color(.orange.opacity(opacity)))
        context.stroke(diamond, with: .color(.orange.opacity(0.8 * opacity)), lineWidth: 1)

        let label = Text("\(item.name)  \(item.startDateStr)")
            .font(.system(size: 9))
            .foregroundColor(.secondary.opacity(opacity))
        context.draw(context.resolve(label), at: CGPoint(x: x + dSize / 2 + 6, y: cy), anchor: .leading)
    }

    private func drawTimelineBaselineBadge(context: GraphicsContext, descriptor: BaselineVarianceDescriptor, anchorX: CGFloat, y: CGFloat) {
        let label = Text(descriptor.label)
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(.primary)
        let resolved = context.resolve(label)
        let badgeWidth = max(CGFloat(descriptor.label.count) * CGFloat(7) + CGFloat(10), CGFloat(32))
        let badgeHeight: CGFloat = 16
        let badgeRect = CGRect(x: anchorX, y: y + rowHeight * 0.18, width: badgeWidth, height: badgeHeight)
        let border = RoundedRectangle(cornerRadius: badgeHeight / 2).path(in: badgeRect)

        context.fill(border, with: .color(descriptor.color.opacity(0.2)))
        context.stroke(border, with: .color(descriptor.color.opacity(0.6)), lineWidth: 0.5)
        context.draw(resolved, at: CGPoint(x: badgeRect.midX, y: badgeRect.midY), anchor: .center)
    }

    private func drawBar(context: GraphicsContext, item: TimelineItem, x: CGFloat, y: CGFloat, width: CGFloat, isDark: Bool, opacity: Double) {
        let level = item.outlineLevel
        let barHeight: CGFloat = level <= 1 ? 24 : 18
        let barY = y + (rowHeight - barHeight) / 2
        let color = item.color

        let barRect = CGRect(x: x, y: barY, width: width, height: barHeight)
        let cornerRadius: CGFloat = level <= 1 ? 5 : 4
        let barPath = RoundedRectangle(cornerRadius: cornerRadius).path(in: barRect)

        let fillOpacity = isDark ? (level <= 1 ? 0.45 : 0.3) : (level <= 1 ? 0.3 : 0.2)
        context.fill(barPath, with: .color(color.opacity(fillOpacity * opacity)))
        context.stroke(barPath, with: .color(color.opacity((isDark ? 0.7 : 0.5) * opacity)), lineWidth: level <= 1 ? 1.0 : 0.5)

        // Progress
        let pct = item.percentComplete / 100.0
        if pct > 0 {
            let progressWidth = width * CGFloat(pct)
            let progressRect = CGRect(x: x, y: barY, width: progressWidth, height: barHeight)
            var progressCtx = context
            progressCtx.clip(to: barPath)
            progressCtx.fill(Path(progressRect), with: .color(color.opacity((isDark ? 0.6 : 0.5) * opacity)))
        }

        // Name
        let fontSize: CGFloat = level <= 1 ? 10 : 9
        let fontWeight: Font.Weight = level <= 1 ? .semibold : .regular

        if width > 80 {
            let label = Text(item.name)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundColor((isDark ? Color.white : Color.primary).opacity(opacity))
            context.draw(context.resolve(label), at: CGPoint(x: x + 6, y: barY + barHeight / 2), anchor: .leading)

            if pct > 0 && width > 120 {
                let pctLabel = Text("\(Int(item.percentComplete))%")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor((isDark ? Color.white.opacity(0.8) : Color.secondary).opacity(opacity))
                context.draw(context.resolve(pctLabel), at: CGPoint(x: x + width - 6, y: barY + barHeight / 2), anchor: .trailing)
            }
        } else {
            let label = Text(item.name)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundColor(.secondary.opacity(opacity))
            context.draw(context.resolve(label), at: CGPoint(x: x + width + 6, y: barY + barHeight / 2), anchor: .leading)
        }

        // Date range
        if !item.startDateStr.isEmpty && !item.endDateStr.isEmpty {
            let dateText = Text("\(item.startDateStr) – \(item.endDateStr)")
                .font(.system(size: 7))
                .foregroundColor(.secondary.opacity(0.7))
            context.draw(context.resolve(dateText), at: CGPoint(x: x, y: barY + barHeight + 2), anchor: .topLeading)
        }
    }
}

// MARK: - Pre-computed data structures

private struct TimelineItem {
    let uniqueID: Int
    let name: String
    let isMilestone: Bool
    let isSummary: Bool
    let outlineLevel: Int
    let percentComplete: Double
    let startDayOffset: Int
    let endDayOffset: Int
    let hasStart: Bool
    let hasEnd: Bool
    let startDateStr: String
    let endDateStr: String
    let baselineStartDayOffset: Int?
    let baselineEndDayOffset: Int?
    let baselineDescriptor: BaselineVarianceDescriptor?
    let predecessorIDs: [Int]
    let color: Color
    let laneIndex: Int
    let isLevel1: Bool
    let isCritical: Bool
}

private struct TimelineDependency {
    let predecessorID: Int
    let successorID: Int
}

private struct TimelinePreparedData {
    let items: [TimelineItem]
    let dependencies: [TimelineDependency]
    let startDate: Date
    let endDate: Date
    let totalDays: Int
    let summaryCount: Int
    let milestoneCount: Int
}
