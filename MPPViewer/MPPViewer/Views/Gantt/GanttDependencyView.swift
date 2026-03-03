import SwiftUI

struct GanttDependencyView: View {
    let tasks: [ProjectTask]
    let allTasks: [Int: ProjectTask]
    let startDate: Date
    let pixelsPerDay: CGFloat
    let rowHeight: CGFloat

    private var taskIndexMap: [Int: Int] {
        var map: [Int: Int] = [:]
        for (index, task) in tasks.enumerated() {
            map[task.uniqueID] = index
        }
        return map
    }

    var body: some View {
        Canvas { context, size in
            let indexMap = taskIndexMap

            for task in tasks {
                guard let predecessors = task.predecessors else { continue }
                guard let successorIndex = indexMap[task.uniqueID] else { continue }

                for relation in predecessors {
                    guard let predecessorIndex = indexMap[relation.targetTaskUniqueID] else { continue }
                    guard let predecessor = allTasks[relation.targetTaskUniqueID] else { continue }

                    let arrow = computeArrowPoints(
                        predecessor: predecessor,
                        successor: task,
                        predIndex: predecessorIndex,
                        succIndex: successorIndex,
                        relationType: relation.type ?? "FS"
                    )

                    var path = Path()
                    path.move(to: arrow.start)

                    // Route the line with right angles
                    let midX = (arrow.start.x + arrow.end.x) / 2
                    if abs(arrow.start.y - arrow.end.y) > 1 {
                        path.addLine(to: CGPoint(x: midX, y: arrow.start.y))
                        path.addLine(to: CGPoint(x: midX, y: arrow.end.y))
                        path.addLine(to: arrow.end)
                    } else {
                        path.addLine(to: arrow.end)
                    }

                    context.stroke(path, with: .color(.secondary.opacity(0.5)), style: StrokeStyle(lineWidth: 1))

                    // Arrowhead
                    let arrowSize: CGFloat = 4
                    var arrowHead = Path()
                    arrowHead.move(to: arrow.end)
                    arrowHead.addLine(to: CGPoint(x: arrow.end.x - arrowSize, y: arrow.end.y - arrowSize))
                    arrowHead.addLine(to: CGPoint(x: arrow.end.x - arrowSize, y: arrow.end.y + arrowSize))
                    arrowHead.closeSubpath()
                    context.fill(arrowHead, with: .color(.secondary.opacity(0.5)))
                }
            }
        }
    }

    private func computeArrowPoints(
        predecessor: ProjectTask,
        successor: ProjectTask,
        predIndex: Int,
        succIndex: Int,
        relationType: String
    ) -> (start: CGPoint, end: CGPoint) {
        let predStart = dayOffset(for: predecessor.startDate)
        let predEnd = dayOffset(for: predecessor.finishDate)
        let succStart = dayOffset(for: successor.startDate)
        let succEnd = dayOffset(for: successor.finishDate)

        let predY = CGFloat(predIndex) * rowHeight + rowHeight / 2
        let succY = CGFloat(succIndex) * rowHeight + rowHeight / 2

        let startPoint: CGPoint
        let endPoint: CGPoint

        switch relationType {
        case "SS":
            startPoint = CGPoint(x: predStart, y: predY)
            endPoint = CGPoint(x: succStart, y: succY)
        case "FF":
            startPoint = CGPoint(x: predEnd, y: predY)
            endPoint = CGPoint(x: succEnd, y: succY)
        case "SF":
            startPoint = CGPoint(x: predStart, y: predY)
            endPoint = CGPoint(x: succEnd, y: succY)
        default: // FS
            startPoint = CGPoint(x: predEnd, y: predY)
            endPoint = CGPoint(x: succStart, y: succY)
        }

        return (startPoint, endPoint)
    }

    private func dayOffset(for date: Date?) -> CGFloat {
        guard let date = date else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: startDate, to: date).day ?? 0
        return CGFloat(days) * pixelsPerDay
    }
}
