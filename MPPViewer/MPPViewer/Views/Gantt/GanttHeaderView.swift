import SwiftUI

struct GanttHeaderView: View {
    let dateRange: (start: Date, end: Date)
    let pixelsPerDay: CGFloat
    let totalWidth: CGFloat
    var showsTodayMarker: Bool = true

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
            if showsTodayMarker, let todayOffset = GanttDateHelpers.todayDayOffset(from: dateRange.start) {
                let todayX = todayOffset * pixelsPerDay
                if todayX >= 0 && todayX <= size.width {
                    let triSize: CGFloat = 6
                    let triangleTipY = size.height - 3
                    var triangle = Path()
                    triangle.move(to: CGPoint(x: todayX, y: triangleTipY))
                    triangle.addLine(to: CGPoint(x: todayX - triSize, y: triangleTipY - triSize))
                    triangle.addLine(to: CGPoint(x: todayX + triSize, y: triangleTipY - triSize))
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

    // MARK: - Responsive Month Label Drawing

    private func drawMonthLabelResponsive(
        context: GraphicsContext,
        date: Date,
        startX: CGFloat,
        endX: CGFloat,
        topRowHeight: CGFloat,
        valid: Bool
    ) {
        guard valid else { return }
        let availableWidth = endX - startX
        guard availableWidth >= 10 else { return }

        let font = Font.caption2

        let fullFormatter = DateFormatter()
        fullFormatter.dateFormat = "MMM yyyy"

        let shortFormatter = DateFormatter()
        shortFormatter.dateFormat = "MMM ''yy"

        let miniFormatter = DateFormatter()
        miniFormatter.dateFormat = "MMM"

        let fullText = fullFormatter.string(from: date)
        let shortText = shortFormatter.string(from: date)
        let miniText = miniFormatter.string(from: date)

        let fullResolved = context.resolve(Text(fullText).font(font).foregroundColor(.secondary))
        let fullWidth = fullResolved.measure(in: CGSize(width: .greatestFiniteMagnitude, height: topRowHeight)).width

        let textToDraw: String
        if availableWidth >= fullWidth + 6 {
            textToDraw = fullText
        } else {
            let shortResolved = context.resolve(Text(shortText).font(font).foregroundColor(.secondary))
            let shortWidth = shortResolved.measure(in: CGSize(width: .greatestFiniteMagnitude, height: topRowHeight)).width
            if availableWidth >= shortWidth + 4 {
                textToDraw = shortText
            } else {
                let miniResolved = context.resolve(Text(miniText).font(.system(size: 8)).foregroundColor(.secondary))
                let miniWidth = miniResolved.measure(in: CGSize(width: .greatestFiniteMagnitude, height: topRowHeight)).width
                if availableWidth >= miniWidth + 2 {
                    textToDraw = miniText
                } else {
                    return
                }
            }
        }

        let resolved = context.resolve(Text(textToDraw).font(font).foregroundColor(.secondary))
        context.draw(resolved, at: CGPoint(x: startX + 4, y: topRowHeight / 2), anchor: .leading)
    }

    private func drawMonthsAndDays(context: GraphicsContext, size: CGSize, calendar: Calendar, totalDays: Int) {
        let topRowHeight = size.height * 0.5
        let bottomRowHeight = size.height * 0.5
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "d"

        var currentMonth: Int = -1
        var pendingDate: Date?
        var pendingStartX: CGFloat = 0
        var hasPending = false

        for day in 0..<totalDays {
            let x = CGFloat(day) * pixelsPerDay
            let date = calendar.date(byAdding: .day, value: day, to: dateRange.start) ?? dateRange.start
            let month = calendar.component(.month, from: date)
            let dayNum = calendar.component(.day, from: date)

            if month != currentMonth {
                currentMonth = month
                if let pendingDate {
                    drawMonthLabelResponsive(context: context, date: pendingDate, startX: pendingStartX, endX: x, topRowHeight: topRowHeight, valid: hasPending)
                }
                pendingDate = date
                pendingStartX = x
                hasPending = true

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
        if let pendingDate {
            drawMonthLabelResponsive(context: context, date: pendingDate, startX: pendingStartX, endX: CGFloat(totalDays) * pixelsPerDay, topRowHeight: topRowHeight, valid: hasPending)
        }
    }

    private func drawMonthsAndWeeksVertical(context: GraphicsContext, size: CGSize, calendar: Calendar, totalDays: Int) {
        let topRowHeight: CGFloat = 20
        let weekFormatter = DateFormatter()
        weekFormatter.dateFormat = "d MMM"

        var currentMonth: Int = -1
        var pendingDate: Date?
        var pendingStartX: CGFloat = 0
        var hasPending = false

        let weekPixels = 7 * pixelsPerDay
        let labelEveryNWeeks: Int = weekPixels >= 30 ? 1 : (weekPixels >= 15 ? 2 : 4)
        var weekCounter = 0

        for day in 0..<totalDays {
            let x = CGFloat(day) * pixelsPerDay
            let date = calendar.date(byAdding: .day, value: day, to: dateRange.start) ?? dateRange.start
            let month = calendar.component(.month, from: date)
            let weekday = calendar.component(.weekday, from: date)

            if month != currentMonth {
                currentMonth = month
                if let pendingDate {
                    drawMonthLabelResponsive(context: context, date: pendingDate, startX: pendingStartX, endX: x, topRowHeight: topRowHeight, valid: hasPending)
                }
                pendingDate = date
                pendingStartX = x
                hasPending = true

                var monthLine = Path()
                monthLine.move(to: CGPoint(x: x, y: 0))
                monthLine.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(monthLine, with: .color(.gray.opacity(gridLineOpacity)), lineWidth: 0.5)
            }

            if weekday == 2 {
                weekCounter += 1
                if weekCounter % labelEveryNWeeks == 0 {
                    let label = weekFormatter.string(from: date)
                    let text = Text(label).font(.system(size: 8)).foregroundColor(.secondary)
                    let resolved = context.resolve(text)

                    var rotatedContext = context
                    let anchorX = x + 2
                    let anchorY = size.height - 2
                    rotatedContext.translateBy(x: anchorX, y: anchorY)
                    rotatedContext.rotate(by: .degrees(-90))
                    rotatedContext.draw(resolved, at: .zero, anchor: .leading)
                }
            }
        }
        if let pendingDate {
            drawMonthLabelResponsive(context: context, date: pendingDate, startX: pendingStartX, endX: CGFloat(totalDays) * pixelsPerDay, topRowHeight: topRowHeight, valid: hasPending)
        }
    }
}
