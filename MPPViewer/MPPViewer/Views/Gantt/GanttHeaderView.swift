import SwiftUI

struct GanttHeaderView: View {
    let dateRange: (start: Date, end: Date)
    let pixelsPerDay: CGFloat
    let totalWidth: CGFloat

    @Environment(\.colorScheme) var colorScheme

    private var gridLineOpacity: Double { colorScheme == .dark ? 0.45 : 0.3 }

    /// Use a taller header when labels need to be vertical
    private var headerHeight: CGFloat {
        pixelsPerDay < 15 ? 64 : 44
    }

    var body: some View {
        Canvas { context, size in
            let calendar = Calendar.current
            let totalDays = calendar.dateComponents([.day], from: dateRange.start, to: dateRange.end).day ?? 30

            // Background
            let bgRect = CGRect(origin: .zero, size: size)
            context.fill(Path(bgRect), with: .color(Color(nsColor: .controlBackgroundColor)))

            // Bottom border
            var borderPath = Path()
            borderPath.move(to: CGPoint(x: 0, y: size.height))
            borderPath.addLine(to: CGPoint(x: size.width, y: size.height))
            context.stroke(borderPath, with: .color(.gray.opacity(0.4)), lineWidth: 1)

            // Today marker in header
            if let todayOffset = GanttDateHelpers.todayDayOffset(from: dateRange.start) {
                let todayX = todayOffset * pixelsPerDay
                if todayX >= 0 && todayX <= size.width {
                    let triSize: CGFloat = 6
                    var triangle = Path()
                    triangle.move(to: CGPoint(x: todayX, y: size.height))
                    triangle.addLine(to: CGPoint(x: todayX - triSize, y: size.height - triSize))
                    triangle.addLine(to: CGPoint(x: todayX + triSize, y: size.height - triSize))
                    triangle.closeSubpath()
                    context.fill(triangle, with: .color(.red))

                    var todayLine = Path()
                    todayLine.move(to: CGPoint(x: todayX, y: 0))
                    todayLine.addLine(to: CGPoint(x: todayX, y: size.height))
                    context.stroke(
                        todayLine,
                        with: .color(.red.opacity(0.5)),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
                }
            }

            if pixelsPerDay >= 15 {
                drawMonthsAndDays(context: context, size: size, calendar: calendar, totalDays: totalDays)
            } else {
                drawMonthsAndWeeksVertical(context: context, size: size, calendar: calendar, totalDays: totalDays)
            }
        }
        .frame(width: totalWidth, height: headerHeight)
    }

    // MARK: - Zoomed in: horizontal day labels

    private func drawMonthsAndDays(context: GraphicsContext, size: CGSize, calendar: Calendar, totalDays: Int) {
        let topRowHeight = size.height * 0.5
        let bottomRowHeight = size.height * 0.5
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "d"
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM yyyy"

        var currentMonth: Int = -1

        for day in 0..<totalDays {
            let x = CGFloat(day) * pixelsPerDay
            let date = calendar.date(byAdding: .day, value: day, to: dateRange.start) ?? dateRange.start
            let month = calendar.component(.month, from: date)
            let dayNum = calendar.component(.day, from: date)

            if month != currentMonth {
                currentMonth = month
                let label = monthFormatter.string(from: date)
                let text = Text(label).font(.caption2).foregroundColor(.secondary)
                context.draw(
                    context.resolve(text),
                    at: CGPoint(x: x + 4, y: topRowHeight / 2),
                    anchor: .leading
                )

                var monthLine = Path()
                monthLine.move(to: CGPoint(x: x, y: 0))
                monthLine.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(monthLine, with: .color(.gray.opacity(gridLineOpacity)), lineWidth: 0.5)
            }

            if pixelsPerDay >= 20 || dayNum % 2 == 1 {
                let dayText = Text(dayFormatter.string(from: date)).font(.system(size: 9)).foregroundColor(.secondary)
                context.draw(
                    context.resolve(dayText),
                    at: CGPoint(x: x + pixelsPerDay / 2, y: topRowHeight + bottomRowHeight / 2),
                    anchor: .center
                )
            }
        }
    }

    // MARK: - Zoomed out: vertical week/day labels

    private func drawMonthsAndWeeksVertical(context: GraphicsContext, size: CGSize, calendar: Calendar, totalDays: Int) {
        let topRowHeight: CGFloat = 20
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM yyyy"
        let weekFormatter = DateFormatter()
        weekFormatter.dateFormat = "d MMM"

        var currentMonth: Int = -1

        // Determine label interval based on how tight the zoom is
        let weekPixels = 7 * pixelsPerDay
        let labelEveryNWeeks: Int = weekPixels >= 30 ? 1 : (weekPixels >= 15 ? 2 : 4)
        var weekCounter = 0

        for day in 0..<totalDays {
            let x = CGFloat(day) * pixelsPerDay
            let date = calendar.date(byAdding: .day, value: day, to: dateRange.start) ?? dateRange.start
            let month = calendar.component(.month, from: date)
            let weekday = calendar.component(.weekday, from: date)

            // Month labels (top row, horizontal)
            if month != currentMonth {
                currentMonth = month
                let label = monthFormatter.string(from: date)
                let text = Text(label).font(.caption2).foregroundColor(.secondary)
                context.draw(
                    context.resolve(text),
                    at: CGPoint(x: x + 4, y: topRowHeight / 2),
                    anchor: .leading
                )

                var monthLine = Path()
                monthLine.move(to: CGPoint(x: x, y: 0))
                monthLine.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(monthLine, with: .color(.gray.opacity(gridLineOpacity)), lineWidth: 0.5)
            }

            // Week labels (on Mondays) — drawn vertically
            if weekday == 2 {
                weekCounter += 1
                if weekCounter % labelEveryNWeeks == 0 {
                    let label = weekFormatter.string(from: date)
                    let text = Text(label).font(.system(size: 8)).foregroundColor(.secondary)
                    let resolved = context.resolve(text)

                    // Draw rotated -90 degrees (bottom-to-top)
                    var rotatedContext = context
                    let anchorX = x + 2
                    let anchorY = size.height - 2
                    rotatedContext.translateBy(x: anchorX, y: anchorY)
                    rotatedContext.rotate(by: .degrees(-90))
                    rotatedContext.draw(resolved, at: .zero, anchor: .leading)
                }
            }
        }
    }
}
