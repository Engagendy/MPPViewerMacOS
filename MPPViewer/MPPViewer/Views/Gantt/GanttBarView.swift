import SwiftUI

struct GanttBarView: View {
    let task: ProjectTask
    let startDate: Date
    let pixelsPerDay: CGFloat
    let rowIndex: Int
    let rowHeight: CGFloat

    private let barInset: CGFloat = 4
    private let minBarWidth: CGFloat = 4

    private var taskStartOffset: CGFloat {
        guard let taskStart = task.startDate else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: startDate, to: taskStart).day ?? 0
        return CGFloat(days) * pixelsPerDay
    }

    private var taskWidth: CGFloat {
        guard let taskStart = task.startDate, let taskFinish = task.finishDate else { return minBarWidth }
        let days = Calendar.current.dateComponents([.day], from: taskStart, to: taskFinish).day ?? 0
        return max(minBarWidth, CGFloat(max(1, days)) * pixelsPerDay)
    }

    private var yPosition: CGFloat {
        CGFloat(rowIndex) * rowHeight
    }

    var body: some View {
        let barHeight = rowHeight - barInset * 2

        if task.milestone == true {
            // Diamond for milestones
            let size: CGFloat = barHeight * 0.7
            DiamondShape()
                .fill(Color.orange)
                .frame(width: size, height: size)
                .offset(
                    x: taskStartOffset - size / 2,
                    y: yPosition + (rowHeight - size) / 2
                )
        } else if task.summary == true {
            // Summary bar (bracket shape)
            SummaryBarShape()
                .fill(Color.primary.opacity(0.7))
                .frame(width: taskWidth, height: barHeight * 0.4)
                .offset(
                    x: taskStartOffset,
                    y: yPosition + barInset + barHeight * 0.3
                )
        } else {
            // Regular task bar
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 3)
                    .fill(task.critical == true ? Color.red.opacity(0.3) : Color.accentColor.opacity(0.3))
                    .frame(width: taskWidth, height: barHeight)

                // Progress fill
                let pct = (task.percentComplete ?? 0) / 100.0
                let fillWidth = taskWidth * CGFloat(pct)
                if fillWidth > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(task.critical == true ? Color.red : Color.accentColor)
                        .frame(width: fillWidth, height: barHeight)
                }

                // Task name label (if bar is wide enough)
                if taskWidth > 80 {
                    Text(task.displayName)
                        .font(.caption2)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
            }
            .frame(width: taskWidth, height: barHeight)
            .offset(
                x: taskStartOffset,
                y: yPosition + barInset
            )
            .help(tooltipText)
        }
    }

    private var tooltipText: String {
        var parts: [String] = [task.displayName]
        if let start = task.start {
            parts.append("Start: \(DateFormatting.shortDate(start))")
        }
        if let finish = task.finish {
            parts.append("Finish: \(DateFormatting.shortDate(finish))")
        }
        parts.append("Duration: \(task.durationDisplay)")
        parts.append("Complete: \(task.percentCompleteDisplay)")
        return parts.joined(separator: "\n")
    }
}

// MARK: - Shapes

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: CGPoint(x: mid.x, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: mid.y))
        path.addLine(to: CGPoint(x: mid.x, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: mid.y))
        path.closeSubpath()
        return path
    }
}

struct SummaryBarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tick: CGFloat = 4

        // Top bar
        path.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.5))

        // Left tick
        path.addRect(CGRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + tick, y: rect.maxY - tick))

        // Right tick
        path.addRect(CGRect(x: rect.maxX - 2, y: rect.minY, width: 2, height: rect.height))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - tick, y: rect.maxY - tick))

        return path
    }
}
