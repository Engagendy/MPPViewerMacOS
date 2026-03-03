import SwiftUI

struct WorkloadView: View {
    let project: ProjectModel

    @State private var workloads: [ResourceWorkload] = []
    @State private var pixelsPerDay: CGFloat = 8
    @State private var rowHeight: CGFloat = 32
    @GestureState private var magnifyBy: CGFloat = 1.0

    @State private var cachedDateRange: (start: Date, end: Date)?
    @State private var cachedTotalDays: Int = 0
    @State private var mondayOffsets: [Int] = []

    private var dateRange: (start: Date, end: Date) {
        cachedDateRange ?? (start: Date(), end: Date())
    }

    private var totalDays: Int { cachedTotalDays }

    private var timelineWidth: CGFloat {
        CGFloat(cachedTotalDays) * pixelsPerDay
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
                }
                .font(.caption2)

                Divider().frame(height: 16)

                GanttZoomControls(pixelsPerDay: $pixelsPerDay, totalDays: totalDays)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if workloads.isEmpty {
                ContentUnavailableView(
                    "No Resource Data",
                    systemImage: "person.badge.clock",
                    description: Text("No work resources with assignments found.")
                )
            } else {
                ScrollView([.horizontal, .vertical]) {
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
                                totalWidth: timelineWidth
                            )

                            workloadCanvas
                                .frame(
                                    width: timelineWidth,
                                    height: CGFloat(workloads.count) * rowHeight
                                )
                        }
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
        .task {
            let range = GanttDateHelpers.dateRange(for: project.tasks)
            let days = GanttDateHelpers.totalDays(for: range)
            cachedDateRange = range
            cachedTotalDays = days

            // Pre-compute Monday day offsets for grid lines
            let calendar = Calendar.current
            var mondays: [Int] = []
            var current = calendar.startOfDay(for: range.start)
            // Find first Monday
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
            mondayOffsets = mondays

            workloads = WorkloadCalculator.compute(
                resources: project.resources,
                assignments: project.assignments,
                tasks: project.tasks,
                calendars: project.calendars,
                defaultCalendarID: project.properties.defaultCalendarUniqueId,
                dateRange: range
            )
        }
    }

    // MARK: - Canvas

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

                    // Height proportional to allocation (cap visual at 200%)
                    let pct = min(2.0, load.allocationPercent / 100.0)
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

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.5))
                .frame(width: 12, height: 8)
            Text(label)
        }
    }
}
