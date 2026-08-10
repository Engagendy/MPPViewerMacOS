import SwiftUI

struct WorkloadView: View {
    let project: ProjectModel
    /// Visual-only leave windows, drawn as amber bands on each resource's row.
    var resourceLeaves: [PlanResourceLeave] = []

    @State private var workloads: [ResourceWorkload] = []
    @State private var pixelsPerDay: CGFloat = 8
    @State private var timelineViewportWidth: CGFloat = 0
    @State private var shouldAutoFitTimeline = true
    @State private var rowHeight: CGFloat = 32
    @GestureState private var magnifyBy: CGFloat = 1.0

    @State private var cachedDateRange: (start: Date, end: Date)?
    @State private var cachedTotalDays: Int = 0
    @State private var mondayOffsets: [Int] = []
    @State private var isLoadingWorkloads = false

    private var dateRange: (start: Date, end: Date) {
        cachedDateRange ?? (start: Date(), end: Date())
    }

    private var totalDays: Int { cachedTotalDays }

    private var timelineWidth: CGFloat {
        CGFloat(cachedTotalDays) * pixelsPerDay
    }

    private var timelineScrollableWidth: CGFloat {
        max(timelineWidth, timelineViewportWidth)
    }

    private var workloadRefreshKey: String {
        var parts: [String] = []
        parts.append(project.properties.projectTitle ?? "")
        parts.append(String(project.tasks.count))
        parts.append(String(project.resources.count))
        parts.append(String(project.assignments.count))
        parts.append(String(project.calendars.count))
        parts.append(project.properties.startDate ?? "")
        parts.append(project.properties.finishDate ?? "")
        parts.append(project.properties.defaultCalendarUniqueId.map(String.init) ?? "")
        return parts.joined(separator: "|")
    }

    @Environment(\.colorScheme) var colorScheme

    private var gridLineOpacity: Double { colorScheme == .dark ? 0.25 : 0.15 }
    private var barFillOpacity: Double { colorScheme == .dark ? 0.65 : 0.5 }
    private var barStrokeOpacity: Double { colorScheme == .dark ? 0.85 : 0.7 }

    private let nameColumnWidth: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Resource Workload")
                    .font(.headline)
                Text("(\(workloads.count) resources)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                HStack(spacing: 12) {
                    legendItem(color: .green, label: "Normal (<=100%)")
                    legendItem(color: .red, label: "Over-allocated")
                    if !resourceLeaves.isEmpty {
                        legendItem(color: .orange, label: "Leave")
                    }
                }
                .font(.caption2)

                Divider().frame(height: 16)

                Menu {
                    Button {
                        exportToPDF()
                    } label: {
                        Label("Export PDF…", systemImage: "doc.richtext")
                    }
                    Button {
                        exportToSVG()
                    } label: {
                        Label("Export SVG (Vector)…", systemImage: "square.on.square.dashed")
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(workloads.isEmpty)
                .help("Export the resource workload as a PDF or scalable SVG, including leave bands.")

                Divider().frame(height: 16)

                GanttZoomControls(
                    pixelsPerDay: pixelsPerDay,
                    totalDays: totalDays,
                    onFitAll: {
                        shouldAutoFitTimeline = true
                        applyAutoFitIfNeeded()
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

            if isLoadingWorkloads && workloads.isEmpty {
                ContentUnavailableView(
                    "Loading Workload",
                    systemImage: "person.badge.clock",
                    description: Text("Calculating resource allocation for this plan.")
                )
                .topAlignedEmptyState()
            } else if workloads.isEmpty {
                ContentUnavailableView(
                    "No Resource Data",
                    systemImage: "person.badge.clock",
                    description: Text("No work resources with assignments found.")
                )
                .topAlignedEmptyState()
            } else {
                GeometryReader { geometry in
                    let viewportWidth = max(geometry.size.width - nameColumnWidth - 1, 1)

                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        HStack(alignment: .top, spacing: 0) {
                            // Left pane: resource names
                            VStack(alignment: .leading, spacing: 0) {
                                // Header spacer
                                Color.clear
                                    .frame(width: nameColumnWidth, height: 44)
                                    .background(Color(nsColor: .controlBackgroundColor))

                                ForEach(workloads) { workload in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(workload.resource.name ?? "Unknown")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .lineLimit(1)
                                            Text("Peak: \(Int(workload.peakAllocation))%")
                                                .font(.caption2)
                                                .foregroundStyle(workload.isOverAllocated ? .red : .secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .frame(width: nameColumnWidth, height: rowHeight)
                                    .background(workload.isOverAllocated ? Color.red.opacity(0.05) : Color.clear)
                                    Divider()
                                }
                            }

                            Divider()

                            // Right pane: timeline
                            VStack(alignment: .leading, spacing: 0) {
                                GanttHeaderView(
                                    dateRange: dateRange,
                                    pixelsPerDay: pixelsPerDay,
                                    totalWidth: timelineScrollableWidth
                                )

                                workloadCanvas
                                    .frame(
                                        width: timelineScrollableWidth,
                                        height: CGFloat(workloads.count) * rowHeight
                                    )
                            }
                        }
                        .frame(minHeight: geometry.size.height, alignment: .topLeading)
                    }
                    .onAppear {
                        timelineViewportWidth = viewportWidth
                        applyAutoFitIfNeeded()
                    }
                    .onChange(of: viewportWidth) { _, newWidth in
                        timelineViewportWidth = newWidth
                        applyAutoFitIfNeeded()
                    }
                    .onChange(of: totalDays) { _, _ in
                        applyAutoFitIfNeeded()
                    }
                    .gesture(
                        MagnifyGesture()
                            .updating($magnifyBy) { value, state, _ in
                                state = value.magnification
                            }
                            .onEnded { value in
                                shouldAutoFitTimeline = false
                                pixelsPerDay = min(100, max(2, pixelsPerDay * value.magnification))
                            }
                    )
                }
            }
        }
        .task(id: workloadRefreshKey) {
            await refreshWorkloads()
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func applyAutoFitIfNeeded() {
        guard shouldAutoFitTimeline, timelineViewportWidth > 0 else { return }
        pixelsPerDay = fittedPixelsPerDay(for: timelineViewportWidth)
    }

    private func fittedPixelsPerDay(for viewportWidth: CGFloat) -> CGFloat {
        max(2, min(100, viewportWidth / CGFloat(max(totalDays, 1))))
    }

    @MainActor
    private func refreshWorkloads() async {
        // Debounce: .task(id:) cancels this task when the refresh key changes
        // again, so rapid model edits coalesce into one recomputation.
        if !workloads.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
        }
        isLoadingWorkloads = true

        let tasks = project.tasks
        let resources = project.resources
        let assignments = project.assignments
        let calendars = project.calendars
        let defaultCalendarID = project.properties.defaultCalendarUniqueId

        let result = await Task.detached(priority: .userInitiated) {
            let range = GanttDateHelpers.dateRange(for: tasks)
            let days = GanttDateHelpers.totalDays(for: range)
            let mondays = Self.mondayOffsets(in: range, days: days)
            let workloads = WorkloadCalculator.compute(
                resources: resources,
                assignments: assignments,
                tasks: tasks,
                calendars: calendars,
                defaultCalendarID: defaultCalendarID,
                dateRange: range
            )
            return (range, days, mondays, workloads)
        }.value

        cachedDateRange = result.0
        cachedTotalDays = result.1
        mondayOffsets = result.2
        workloads = result.3
        isLoadingWorkloads = false
        applyAutoFitIfNeeded()
    }

    nonisolated private static func mondayOffsets(in range: (start: Date, end: Date), days: Int) -> [Int] {
        let calendar = Calendar.current
        var mondays: [Int] = []
        var current = calendar.startOfDay(for: range.start)
        let wd = calendar.component(.weekday, from: current)
        let toMonday = (wd == 1) ? 1 : (9 - wd)
        if toMonday > 0 && toMonday < 7 {
            current = calendar.date(byAdding: .day, value: toMonday, to: current) ?? current
        }
        let startDay = calendar.startOfDay(for: range.start)
        while current <= range.end {
            let offset = calendar.dateComponents([.day], from: startDay, to: current).day ?? 0
            if offset >= 0 && offset < days {
                mondays.append(offset)
            }
            current = calendar.date(byAdding: .day, value: 7, to: current) ?? range.end
        }
        return mondays
    }

    // MARK: - Canvas

    /// Inclusive [from...to] date span → x/width in canvas coordinates, clipped
    /// to the visible timeline. Nil when the span is entirely off-chart.
    private func leaveBandGeometry(from: Date, to: Date) -> (x: CGFloat, width: CGFloat)? {
        guard totalDays > 0 else { return nil }
        let cal = Calendar.current
        let origin = cal.startOfDay(for: dateRange.start)
        let startOffset = cal.dateComponents([.day], from: origin, to: cal.startOfDay(for: from)).day ?? 0
        let endOffset = cal.dateComponents([.day], from: origin, to: cal.startOfDay(for: to)).day ?? 0
        let lo = max(0, min(startOffset, endOffset))
        let hi = min(totalDays - 1, max(startOffset, endOffset))
        guard hi >= lo else { return nil }
        return (CGFloat(lo) * pixelsPerDay, CGFloat(hi - lo + 1) * pixelsPerDay)
    }

    private var workloadCanvas: some View {
        Canvas { context, size in
            // Grid lines
            for row in 0...workloads.count {
                let y = CGFloat(row) * rowHeight
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.gray.opacity(gridLineOpacity)), lineWidth: 0.5)
            }

            // Vertical week lines (pre-computed Monday offsets)
            for dayOffset in mondayOffsets {
                let x = CGFloat(dayOffset) * pixelsPerDay
                var vline = Path()
                vline.move(to: CGPoint(x: x, y: 0))
                vline.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(vline, with: .color(.gray.opacity(gridLineOpacity)), lineWidth: 0.5)
            }

            // Resource leave bands (drawn behind the allocation bars).
            if !resourceLeaves.isEmpty {
                let leavesByResourceID = Dictionary(grouping: resourceLeaves, by: \.resourceID)
                for (rowIndex, workload) in workloads.enumerated() {
                    guard let resourceID = workload.resource.uniqueID,
                          let leaves = leavesByResourceID[resourceID] else { continue }
                    let y = CGFloat(rowIndex) * rowHeight
                    for leave in leaves {
                        guard let band = leaveBandGeometry(from: leave.startDate, to: leave.endDate) else { continue }
                        let color = Color(hex: leave.effectiveColorHex) ?? .orange
                        let rect = CGRect(x: band.x, y: y + 1, width: band.width, height: rowHeight - 2)
                        context.fill(Path(rect), with: .color(color.opacity(colorScheme == .dark ? 0.28 : 0.20)))
                        for edgeX in [band.x, band.x + band.width] {
                            var edge = Path()
                            edge.move(to: CGPoint(x: edgeX, y: y + 1))
                            edge.addLine(to: CGPoint(x: edgeX, y: y + rowHeight - 1))
                            context.stroke(edge, with: .color(color.opacity(0.6)), lineWidth: 1)
                        }
                        // Label the band with the reason when it fits.
                        let reason = leave.name.trimmingCharacters(in: .whitespaces)
                        if band.width > 34 {
                            let text = Text(reason.isEmpty ? "Leave" : reason)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(color)
                            context.draw(context.resolve(text), at: CGPoint(x: band.x + 4, y: y + rowHeight / 2), anchor: .leading)
                        }
                    }
                }
            }

            // Resource bars
            for (rowIndex, workload) in workloads.enumerated() {
                let y = CGFloat(rowIndex) * rowHeight
                let barInset: CGFloat = 4
                let maxBarHeight = rowHeight - barInset * 2

                // Capacity line at 100%
                var capacityLine = Path()
                capacityLine.move(to: CGPoint(x: 0, y: y + barInset))
                capacityLine.addLine(to: CGPoint(x: size.width, y: y + barInset))
                context.stroke(
                    capacityLine,
                    with: .color(.gray.opacity(0.3)),
                    style: StrokeStyle(lineWidth: 0.5, dash: [4, 3])
                )

                for load in workload.weeklyLoads {
                    guard load.totalHours > 0 else { continue }

                    let xStart = CGFloat(load.dayOffset) * pixelsPerDay
                    let barWidth = max(2, 7 * pixelsPerDay - 2) // 7 days wide minus gap

                    // Height proportional to allocation, clamped to the row so
                    // over-allocated bars never spill into the row above or the
                    // date header. Over-allocation is shown by the red fill.
                    let pct = min(1.0, load.allocationPercent / 100.0)
                    let barHeight = maxBarHeight * CGFloat(pct)
                    let barY = y + barInset + (maxBarHeight - barHeight)

                    let color: Color = load.isOverAllocated ? .red : .green
                    let barRect = CGRect(x: xStart, y: barY, width: barWidth, height: barHeight)
                    let rr = RoundedRectangle(cornerRadius: 2).path(in: barRect)
                    context.fill(rr, with: .color(color.opacity(barFillOpacity)))
                    context.stroke(rr, with: .color(color.opacity(barStrokeOpacity)), lineWidth: 0.5)
                }
            }

            // Today line
            if let todayOffset = GanttDateHelpers.todayDayOffset(from: dateRange.start) {
                let todayX = todayOffset * pixelsPerDay
                if todayX >= 0 && todayX <= size.width {
                    var todayLine = Path()
                    todayLine.move(to: CGPoint(x: todayX, y: 0))
                    todayLine.addLine(to: CGPoint(x: todayX, y: size.height))
                    context.stroke(todayLine, with: .color(.red), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
            }
        }
    }

    // MARK: - Export

    private var exportContentSize: CGSize {
        CGSize(
            width: nameColumnWidth + 1 + timelineWidth,
            height: 44 + CGFloat(workloads.count) * rowHeight
        )
    }

    /// A fixed-size, non-scrolling composition (name column + header + canvas)
    /// captured for PDF export.
    private var workloadExportContent: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(width: nameColumnWidth, height: 44)
                    .background(Color(nsColor: .controlBackgroundColor))
                ForEach(workloads) { workload in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workload.resource.name ?? "Unknown")
                                .font(.caption).fontWeight(.medium).lineLimit(1)
                            Text("Peak: \(Int(workload.peakAllocation))%")
                                .font(.caption2)
                                .foregroundStyle(workload.isOverAllocated ? .red : .secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .frame(width: nameColumnWidth, height: rowHeight)
                    Divider()
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                GanttHeaderView(dateRange: dateRange, pixelsPerDay: pixelsPerDay, totalWidth: timelineWidth)
                workloadCanvas
                    .frame(width: timelineWidth, height: CGFloat(workloads.count) * rowHeight)
            }
        }
        .frame(width: exportContentSize.width, height: exportContentSize.height, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    @MainActor
    private func exportToPDF() {
        guard !workloads.isEmpty else { return }
        let title = project.properties.projectTitle ?? "Workload"
        PDFExporter.exportGanttToPDF(
            view: workloadExportContent,
            contentSize: exportContentSize,
            fileName: "\(title) - Workload \(PDFExporter.fileNameTimestamp).pdf"
        )
    }

    @MainActor
    private func exportToSVG() {
        guard !workloads.isEmpty else { return }
        let rows: [SVGExporter.WorkloadRow] = workloads.map { workload in
            let resourceID = workload.resource.uniqueID ?? -1
            return SVGExporter.WorkloadRow(
                name: workload.resource.name ?? "Unknown",
                peakPercent: workload.peakAllocation,
                isOverAllocated: workload.isOverAllocated,
                weeks: workload.weeklyLoads.map {
                    SVGExporter.WorkloadWeek(dayOffset: $0.dayOffset, allocationPercent: $0.allocationPercent, isOver: $0.isOverAllocated)
                },
                leaves: resourceLeaves.filter { $0.resourceID == resourceID }.map {
                    SVGExporter.WorkloadLeave(start: $0.startDate, finish: $0.endDate, name: $0.name, colorHex: $0.effectiveColorHex)
                }
            )
        }
        let title = project.properties.projectTitle ?? "Workload"
        SVGExporter.exportWorkload(
            rows: rows,
            rangeStart: dateRange.start,
            rangeEnd: dateRange.end,
            pixelsPerDay: max(2, pixelsPerDay),
            rowHeight: max(28, rowHeight),
            title: title,
            fileName: "\(title) - Workload \(PDFExporter.fileNameTimestamp).svg"
        )
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.5))
                .frame(width: 12, height: 8)
            Text(label)
        }
    }
}
