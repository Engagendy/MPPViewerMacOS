import SwiftUI

struct GanttChartView: View {
    let project: ProjectModel
    let searchText: String

    @State private var pixelsPerDay: CGFloat = 8
    @State private var rowHeight: CGFloat = 24
    @State private var criticalPathOnly: Bool = false
    @State private var showBaseline: Bool = false
    @GestureState private var magnifyBy: CGFloat = 1.0

    private var flatTasks: [ProjectTask] {
        let tasks = searchText.isEmpty ? project.rootTasks : project.tasks.filter {
            $0.name?.lowercased().contains(searchText.lowercased()) == true
        }
        return flattenVisible(tasks)
    }

    private var dateRange: (start: Date, end: Date) {
        GanttDateHelpers.dateRange(for: project.tasks)
    }

    private var totalDays: Int {
        GanttDateHelpers.totalDays(for: dateRange)
    }

    private var timelineWidth: CGFloat {
        CGFloat(totalDays) * pixelsPerDay
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Gantt Chart")
                    .font(.headline)
                Text("(\(flatTasks.count) tasks)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                Button {
                    exportToPDF()
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Button {
                    printGantt()
                } label: {
                    Label("Print", systemImage: "printer")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Divider().frame(height: 16)

                Toggle(isOn: $criticalPathOnly) {
                    Label("Critical Path", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(criticalPathOnly ? .red : nil)

                Toggle(isOn: $showBaseline) {
                    Label("Baseline", systemImage: "clock.arrow.2.circlepath")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(showBaseline ? .gray : nil)

                Divider().frame(height: 16)

                GanttZoomControls(pixelsPerDay: $pixelsPerDay, totalDays: totalDays)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Legend
            GanttLegendBar()

            Divider()

            if flatTasks.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "chart.bar.xaxis")
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        GanttHeaderView(
                            dateRange: dateRange,
                            pixelsPerDay: pixelsPerDay,
                            totalWidth: timelineWidth
                        )

                        // Single Canvas for everything: grid + bars + dependencies
                        GanttCanvasView(
                            tasks: flatTasks,
                            allTasks: project.tasksByID,
                            startDate: dateRange.start,
                            totalDays: totalDays,
                            pixelsPerDay: pixelsPerDay,
                            rowHeight: rowHeight,
                            criticalPathOnly: criticalPathOnly,
                            showBaseline: showBaseline
                        )
                        .frame(width: timelineWidth, height: CGFloat(flatTasks.count) * rowHeight)
                    }
                }
                .gesture(
                    MagnifyGesture()
                        .updating($magnifyBy) { value, state, _ in
                            state = value.magnification
                        }
                        .onEnded { value in
                            pixelsPerDay = min(100, max(2, pixelsPerDay * value.magnification))
                        }
                )
            }
        }
    }

    private func exportToPDF() {
        let ganttContent = VStack(alignment: .leading, spacing: 0) {
            GanttHeaderView(
                dateRange: dateRange,
                pixelsPerDay: pixelsPerDay,
                totalWidth: timelineWidth
            )
            GanttCanvasView(
                tasks: flatTasks,
                allTasks: project.tasksByID,
                startDate: dateRange.start,
                totalDays: totalDays,
                pixelsPerDay: pixelsPerDay,
                rowHeight: rowHeight,
                criticalPathOnly: criticalPathOnly
            )
            .frame(width: timelineWidth, height: CGFloat(flatTasks.count) * rowHeight)
        }

        let contentSize = CGSize(width: timelineWidth, height: CGFloat(flatTasks.count) * rowHeight + 44)
        let title = project.properties.projectTitle ?? "Gantt Chart"
        PDFExporter.exportGanttToPDF(
            view: ganttContent,
            contentSize: contentSize,
            fileName: "\(title) - Gantt \(PDFExporter.fileNameTimestamp).pdf"
        )
    }

    private func printGantt() {
        let ganttContent = VStack(alignment: .leading, spacing: 0) {
            GanttHeaderView(
                dateRange: dateRange,
                pixelsPerDay: pixelsPerDay,
                totalWidth: timelineWidth
            )
            GanttCanvasView(
                tasks: flatTasks,
                allTasks: project.tasksByID,
                startDate: dateRange.start,
                totalDays: totalDays,
                pixelsPerDay: pixelsPerDay,
                rowHeight: rowHeight,
                criticalPathOnly: criticalPathOnly
            )
            .frame(width: timelineWidth, height: CGFloat(flatTasks.count) * rowHeight)
        }

        let contentSize = CGSize(width: timelineWidth, height: CGFloat(flatTasks.count) * rowHeight + 44)
        let title = project.properties.projectTitle ?? "Gantt Chart"
        PrintManager.printView(ganttContent, size: contentSize, title: title)
    }

    private func flattenVisible(_ tasks: [ProjectTask]) -> [ProjectTask] {
        var result: [ProjectTask] = []
        for task in tasks {
            result.append(task)
            result.append(contentsOf: flattenVisible(task.children))
        }
        return result
    }
}

// MARK: - Gantt Date Helpers (shared between views)

enum GanttDateHelpers {
    static func dateRange(for tasks: [ProjectTask]) -> (start: Date, end: Date) {
        let allDates = tasks.compactMap { $0.startDate } + tasks.compactMap { $0.finishDate }
        guard let minDate = allDates.min(), let maxDate = allDates.max() else {
            let now = Date()
            return (now, now.addingTimeInterval(86400 * 30))
        }
        let paddedStart = Calendar.current.date(byAdding: .day, value: -3, to: minDate) ?? minDate
        let paddedEnd = Calendar.current.date(byAdding: .day, value: 7, to: maxDate) ?? maxDate
        return (paddedStart, paddedEnd)
    }

    static func totalDays(for dateRange: (start: Date, end: Date)) -> Int {
        max(1, Calendar.current.dateComponents([.day], from: dateRange.start, to: dateRange.end).day ?? 30)
    }

    static func todayDayOffset(from startDate: Date) -> CGFloat? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: startDate)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return CGFloat(days)
    }
}

// MARK: - Legend Bar

struct GanttLegendBar: View {
    var body: some View {
        HStack(spacing: 16) {
            legendItem(color: .blue, label: "Normal")
            legendItem(color: .red, label: "Critical")
            summaryLegendItem()
            milestoneLegendItem()
            progressLegendItem()
            baselineLegendItem()
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.5))
                .frame(width: 16, height: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(color.opacity(0.6), lineWidth: 0.5)
                )
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func summaryLegendItem() -> some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(Color.primary.opacity(0.6))
                .frame(width: 16, height: 4)
            Text("Summary").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func milestoneLegendItem() -> some View {
        HStack(spacing: 4) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 8))
                .foregroundStyle(.orange)
            Text("Milestone").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func progressLegendItem() -> some View {
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.25))
                    .frame(width: 16, height: 8)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.6))
                    .frame(width: 10, height: 8)
            }
            Text("Progress").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func baselineLegendItem() -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 16, height: 6)
            Text("Baseline").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Zoom Controls

struct GanttZoomControls: View {
    @Binding var pixelsPerDay: CGFloat
    let totalDays: Int

    var body: some View {
        HStack(spacing: 8) {
            Button("Fit All") {
                // This will be adjusted by the parent based on available width;
                // use a reasonable default that fits all days in ~900px
                let fitPx = max(2, min(100, 900.0 / CGFloat(totalDays)))
                pixelsPerDay = fitPx
            }
            .buttonStyle(.borderless)
            .font(.caption)

            Button("Week") {
                pixelsPerDay = 40
            }
            .buttonStyle(.borderless)
            .font(.caption)

            Button("Month") {
                pixelsPerDay = 10
            }
            .buttonStyle(.borderless)
            .font(.caption)

            Divider().frame(height: 16)

            Button(action: { pixelsPerDay = max(2, pixelsPerDay / 1.5) }) {
                Image(systemName: "minus.magnifyingglass")
            }
            Text("\(Int(pixelsPerDay)) px/day")
                .monospacedDigit()
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70)
            Button(action: { pixelsPerDay = min(100, pixelsPerDay * 1.5) }) {
                Image(systemName: "plus.magnifyingglass")
            }
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Single Canvas for Grid + Bars + Dependencies

struct GanttCanvasView: View {
    let tasks: [ProjectTask]
    let allTasks: [Int: ProjectTask]
    let startDate: Date
    let totalDays: Int
    let pixelsPerDay: CGFloat
    let rowHeight: CGFloat
    var criticalPathOnly: Bool = false
    var showBaseline: Bool = false

    @Environment(\.colorScheme) var colorScheme

    private var rowShadingOpacity: Double { colorScheme == .dark ? 0.08 : 0.04 }
    private var gridLineOpacity: Double { colorScheme == .dark ? 0.25 : 0.15 }
    private var weekendOpacity: Double { colorScheme == .dark ? 0.12 : 0.06 }
    private var barBgOpacity: Double { colorScheme == .dark ? 0.35 : 0.25 }
    private var baselineOpacity: Double { colorScheme == .dark ? 0.4 : 0.25 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            canvas
            // Invisible overlay for hover tooltips
            tooltipOverlay
        }
    }

    private var tooltipOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.uniqueID) { _, task in
                Color.clear
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
                    .help(tooltipFor(task))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tooltipFor(_ task: ProjectTask) -> String {
        var parts: [String] = [task.displayName]
        if let s = task.start {
            parts.append("Start: \(DateFormatting.shortDate(s))")
        }
        if let f = task.finish {
            parts.append("Finish: \(DateFormatting.shortDate(f))")
        }
        let dur = task.durationDisplay
        if !dur.isEmpty {
            parts.append("Duration: \(dur)")
        }
        if let pct = task.percentComplete {
            parts.append("Complete: \(Int(pct))%")
        }
        if task.critical == true {
            parts.append("Critical Path")
        }
        if task.hasBaseline {
            if let sv = task.startVarianceDays {
                parts.append("Start Variance: \(sv > 0 ? "+" : "")\(sv)d")
            }
            if let fv = task.finishVarianceDays {
                parts.append("Finish Variance: \(fv > 0 ? "+" : "")\(fv)d")
            }
        }
        return parts.joined(separator: "\n")
    }

    private var canvas: some View {
        Canvas { context, size in
            let calendar = Calendar.current
            let barInset: CGFloat = 4
            let barHeight = rowHeight - barInset * 2
            let dimOpacity: CGFloat = criticalPathOnly ? 0.15 : 1.0

            // --- Alternate Row Shading ---
            for row in 0..<tasks.count {
                if row % 2 == 0 {
                    let rowRect = CGRect(x: 0, y: CGFloat(row) * rowHeight, width: size.width, height: rowHeight)
                    context.fill(Path(rowRect), with: .color(.gray.opacity(rowShadingOpacity)))
                }
            }

            // --- Grid ---
            for row in 0...tasks.count {
                let y = CGFloat(row) * rowHeight
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.gray.opacity(gridLineOpacity)), lineWidth: 0.5)
            }

            for day in 0..<totalDays {
                let x = CGFloat(day) * pixelsPerDay
                let date = calendar.date(byAdding: .day, value: day, to: startDate) ?? startDate
                let weekday = calendar.component(.weekday, from: date)

                if weekday == 1 || weekday == 7 {
                    let rect = CGRect(x: x, y: 0, width: pixelsPerDay, height: size.height)
                    context.fill(Path(rect), with: .color(.gray.opacity(weekendOpacity)))
                }

                if weekday == 2 || pixelsPerDay >= 30 {
                    var vline = Path()
                    vline.move(to: CGPoint(x: x, y: 0))
                    vline.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(vline, with: .color(.gray.opacity(weekday == 2 ? gridLineOpacity + 0.05 : gridLineOpacity - 0.07)), lineWidth: 0.5)
                }
            }

            // --- Baseline Bars (behind actual bars) ---
            if showBaseline {
                for (index, task) in tasks.enumerated() {
                    guard task.hasBaseline,
                          let bsDate = task.baselineStartDate,
                          let bfDate = task.baselineFinishDate,
                          task.milestone != true,
                          task.summary != true else { continue }

                    let y = CGFloat(index) * rowHeight
                    let bsOffset = calendar.dateComponents([.day], from: startDate, to: bsDate).day ?? 0
                    let bfOffset = calendar.dateComponents([.day], from: startDate, to: bfDate).day ?? 0
                    let xStart = CGFloat(bsOffset) * pixelsPerDay
                    let width = max(4, CGFloat(max(1, bfOffset - bsOffset)) * pixelsPerDay)

                    let baselineBarHeight = barHeight * 0.5
                    let baselineY = y + barInset + barHeight - baselineBarHeight // bottom-aligned
                    let baseRect = CGRect(x: xStart, y: baselineY, width: width, height: baselineBarHeight)
                    let rr = RoundedRectangle(cornerRadius: 2).path(in: baseRect)
                    context.fill(rr, with: .color(.gray.opacity(baselineOpacity)))
                    context.stroke(rr, with: .color(.gray.opacity(baselineOpacity + 0.15)), lineWidth: 0.5)
                }
            }

            // --- Task Bars ---
            var taskIndexMap: [Int: Int] = [:]
            for (index, task) in tasks.enumerated() {
                taskIndexMap[task.uniqueID] = index
                let y = CGFloat(index) * rowHeight
                let isCritical = task.critical == true
                let taskOpacity = (!criticalPathOnly || isCritical) ? 1.0 : dimOpacity

                guard let taskStart = task.startDate else { continue }
                let startDays = calendar.dateComponents([.day], from: startDate, to: taskStart).day ?? 0
                let xStart = CGFloat(startDays) * pixelsPerDay

                if task.milestone == true {
                    // Diamond
                    let dSize: CGFloat = barHeight * 0.6
                    let cx = xStart
                    let cy = y + rowHeight / 2
                    var diamond = Path()
                    diamond.move(to: CGPoint(x: cx, y: cy - dSize / 2))
                    diamond.addLine(to: CGPoint(x: cx + dSize / 2, y: cy))
                    diamond.addLine(to: CGPoint(x: cx, y: cy + dSize / 2))
                    diamond.addLine(to: CGPoint(x: cx - dSize / 2, y: cy))
                    diamond.closeSubpath()
                    context.fill(diamond, with: .color(.orange.opacity(taskOpacity)))

                    // Right-side label for milestones
                    let label = Text(task.displayName).font(.system(size: 9)).foregroundColor(.primary.opacity(taskOpacity))
                    context.draw(
                        context.resolve(label),
                        at: CGPoint(x: cx + dSize / 2 + 4, y: y + rowHeight / 2),
                        anchor: .leading
                    )
                    continue
                }

                guard let taskFinish = task.finishDate else { continue }
                let endDays = calendar.dateComponents([.day], from: startDate, to: taskFinish).day ?? 0
                let width = max(4, CGFloat(max(1, endDays - startDays)) * pixelsPerDay)

                if task.summary == true {
                    // Summary bracket
                    let bracketH: CGFloat = barHeight * 0.3
                    let bracketY = y + barInset + barHeight * 0.35
                    let rect = CGRect(x: xStart, y: bracketY, width: width, height: bracketH)
                    context.fill(Path(rect), with: .color(.primary.opacity(0.6 * taskOpacity)))

                    // Left/right ticks
                    let tick: CGFloat = 3
                    var leftTick = Path()
                    leftTick.move(to: CGPoint(x: xStart, y: bracketY))
                    leftTick.addLine(to: CGPoint(x: xStart, y: bracketY + bracketH + tick))
                    context.stroke(leftTick, with: .color(.primary.opacity(0.6 * taskOpacity)), lineWidth: 1.5)

                    var rightTick = Path()
                    rightTick.move(to: CGPoint(x: xStart + width, y: bracketY))
                    rightTick.addLine(to: CGPoint(x: xStart + width, y: bracketY + bracketH + tick))
                    context.stroke(rightTick, with: .color(.primary.opacity(0.6 * taskOpacity)), lineWidth: 1.5)
                } else {
                    // Regular bar
                    let bgColor: Color = isCritical ? .red.opacity(barBgOpacity * taskOpacity) : .blue.opacity(barBgOpacity * taskOpacity)
                    let fgColor: Color = isCritical ? .red : .blue

                    let barRect = CGRect(x: xStart, y: y + barInset, width: width, height: barHeight)
                    let rr = RoundedRectangle(cornerRadius: 3).path(in: barRect)
                    context.fill(rr, with: .color(bgColor))
                    context.stroke(rr, with: .color(fgColor.opacity(0.4 * taskOpacity)), lineWidth: isCritical && criticalPathOnly ? 1.5 : 0.5)

                    // Progress fill
                    let pct = (task.percentComplete ?? 0) / 100.0
                    if pct > 0 {
                        let fillWidth = width * CGFloat(pct)
                        let fillRect = CGRect(x: xStart, y: y + barInset, width: fillWidth, height: barHeight)
                        let fillRR = RoundedRectangle(cornerRadius: 3).path(in: fillRect)
                        context.fill(fillRR, with: .color(fgColor.opacity(0.6 * taskOpacity)))
                    }

                    // Task name: inline if enough space, otherwise right of bar
                    if width > 60 {
                        let label = Text(task.displayName).font(.system(size: 9)).foregroundColor(.primary.opacity(taskOpacity))
                        context.draw(
                            context.resolve(label),
                            at: CGPoint(x: xStart + 4, y: y + rowHeight / 2),
                            anchor: .leading
                        )
                    } else {
                        let label = Text(task.displayName).font(.system(size: 9)).foregroundColor(.secondary.opacity(taskOpacity))
                        context.draw(
                            context.resolve(label),
                            at: CGPoint(x: xStart + width + 4, y: y + rowHeight / 2),
                            anchor: .leading
                        )
                    }
                }
            }

            // --- Today Marker ---
            if let todayOffset = GanttDateHelpers.todayDayOffset(from: startDate) {
                let todayX = todayOffset * pixelsPerDay
                if todayX >= 0 && todayX <= size.width {
                    let dashPattern: [CGFloat] = [4, 3]
                    var todayLine = Path()
                    todayLine.move(to: CGPoint(x: todayX, y: 0))
                    todayLine.addLine(to: CGPoint(x: todayX, y: size.height))
                    context.stroke(
                        todayLine,
                        with: .color(.red),
                        style: StrokeStyle(lineWidth: 1.5, dash: dashPattern)
                    )
                }
            }

            // --- Dependency Arrows ---
            for task in tasks {
                guard let predecessors = task.predecessors else { continue }
                guard let succIdx = taskIndexMap[task.uniqueID] else { continue }

                for relation in predecessors {
                    guard let predIdx = taskIndexMap[relation.targetTaskUniqueID] else { continue }
                    guard let pred = allTasks[relation.targetTaskUniqueID] else { continue }

                    let predEnd = dayOffsetX(for: pred.finishDate, calendar: calendar)
                    let succStart = dayOffsetX(for: task.startDate, calendar: calendar)
                    let predY = CGFloat(predIdx) * rowHeight + rowHeight / 2
                    let succY = CGFloat(succIdx) * rowHeight + rowHeight / 2

                    var arrow = Path()
                    arrow.move(to: CGPoint(x: predEnd, y: predY))

                    let midX = predEnd + 6
                    arrow.addLine(to: CGPoint(x: midX, y: predY))
                    arrow.addLine(to: CGPoint(x: midX, y: succY))
                    arrow.addLine(to: CGPoint(x: succStart, y: succY))

                    context.stroke(arrow, with: .color(.gray.opacity(0.5)), style: StrokeStyle(lineWidth: 0.8))

                    // Arrowhead
                    let aSize: CGFloat = 3
                    var head = Path()
                    head.move(to: CGPoint(x: succStart, y: succY))
                    head.addLine(to: CGPoint(x: succStart - aSize, y: succY - aSize))
                    head.addLine(to: CGPoint(x: succStart - aSize, y: succY + aSize))
                    head.closeSubpath()
                    context.fill(head, with: .color(.gray.opacity(0.5)))
                }
            }
        }
    } // end canvas

    private func dayOffsetX(for date: Date?, calendar: Calendar) -> CGFloat {
        guard let date = date else { return 0 }
        let days = calendar.dateComponents([.day], from: startDate, to: date).day ?? 0
        return CGFloat(days) * pixelsPerDay
    }
}
