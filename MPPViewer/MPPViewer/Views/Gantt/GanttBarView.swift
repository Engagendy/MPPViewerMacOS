import SwiftUI

enum GanttResizeEdge {
    case leading
    case trailing
}

struct GanttBarView: View {
    let task: ProjectTask
    let startDate: Date
    let pixelsPerDay: CGFloat
    let rowIndex: Int
    let rowHeight: CGFloat
    var coordinateSpaceName: String = "GanttCanvasViewSpace"
    var isEditable: Bool = false
    var isSelected: Bool = false
    var isLinkSource: Bool = false
    var onMoveTask: ((Int) -> Void)? = nil
    var onResizeTask: ((GanttResizeEdge, Int) -> Void)? = nil
    var onSelectTask: (() -> Void)? = nil
    var onStartLinkingFromTask: (() -> Void)? = nil

    @State private var moveTranslation: CGFloat = 0
    @State private var leadingResizeTranslation: CGFloat = 0
    @State private var trailingResizeTranslation: CGFloat = 0

    private let barInset: CGFloat = 4
    private let minBarWidth: CGFloat = 4
    private let handleWidth: CGFloat = 8
    private let handleHitWidth: CGFloat = 20

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

    private var movePreviewDays: Int {
        roundedDayDelta(for: moveTranslation)
    }

    private var leadingPreviewDays: Int {
        roundedDayDelta(for: leadingResizeTranslation)
    }

    private var trailingPreviewDays: Int {
        roundedDayDelta(for: trailingResizeTranslation)
    }

    private var previewOffsetX: CGFloat {
        let totalDays = movePreviewDays + leadingPreviewDays
        return taskStartOffset + CGFloat(totalDays) * pixelsPerDay
    }

    private var previewWidth: CGFloat {
        let width = taskWidth + CGFloat(trailingPreviewDays - leadingPreviewDays) * pixelsPerDay
        return max(minBarWidth, width)
    }

    private var barHeight: CGFloat {
        rowHeight - barInset * 2
    }

    var body: some View {
        if task.milestone == true {
            milestoneBar
        } else if task.summary == true {
            summaryBar
        } else {
            regularBar
        }
    }

    private var milestoneBar: some View {
        let size: CGFloat = barHeight * 0.7
        return DiamondShape()
            .fill(Color.orange)
            .frame(width: size, height: size)
            .overlay {
                if isEditable {
                    DiamondShape()
                        .stroke(Color.orange.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
                if isLinkSource {
                    DiamondShape()
                        .stroke(Color.orange, lineWidth: 2.5)
                }
                if isSelected {
                    DiamondShape()
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .shadow(color: isLinkSource ? Color.orange.opacity(0.28) : .clear, radius: 6, x: 0, y: 0)
            .offset(
                x: taskStartOffset + CGFloat(movePreviewDays) * pixelsPerDay - size / 2,
                y: yPosition + (rowHeight - size) / 2
            )
            .gesture(
                isEditable ? DragGesture()
                    .onChanged { value in
                        moveTranslation = value.translation.width
                    }
                    .onEnded { value in
                    let delta = roundedDayDelta(for: value.translation.width)
                    moveTranslation = 0
                    guard delta != 0 else { return }
                    onMoveTask?(delta)
                } : nil
            )
            .simultaneousGesture(TapGesture().onEnded { onSelectTask?() })
            .simultaneousGesture(
                TapGesture()
                    .modifiers(.control)
                    .onEnded { onStartLinkingFromTask?() }
            )
            .help(editTooltipText)
        }

    private var summaryBar: some View {
        SummaryBarShape()
            .fill(Color.primary.opacity(0.7))
            .frame(width: taskWidth, height: barHeight * 0.4)
            .overlay {
                if isSelected {
                    SummaryBarShape()
                        .stroke(Color.accentColor, lineWidth: 2)
                }
                if isLinkSource {
                    SummaryBarShape()
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, dash: [5, 3]))
                }
            }
            .shadow(color: isLinkSource ? Color.orange.opacity(0.28) : .clear, radius: 6, x: 0, y: 0)
            .offset(
                x: taskStartOffset,
                y: yPosition + barInset + barHeight * 0.3
            )
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { onSelectTask?() })
            .simultaneousGesture(
                TapGesture()
                    .modifiers(.control)
                    .onEnded { onStartLinkingFromTask?() }
            )
            .help(tooltipText)
    }

    private var regularBar: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(task.critical == true ? Color.red.opacity(0.3) : Color.accentColor.opacity(0.3))

            let pct = (task.percentComplete ?? 0) / 100.0
            let fillWidth = previewWidth * CGFloat(pct)
            if fillWidth > 0 {
                RoundedRectangle(cornerRadius: 3)
                    .fill(task.critical == true ? Color.red : Color.accentColor)
                    .frame(width: fillWidth, height: barHeight)
            }

            if previewWidth > 80 {
                Text(task.displayName)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .frame(width: previewWidth, height: barHeight)
        .overlay {
            if isEditable {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.accentColor.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
            if isLinkSource {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.orange, lineWidth: 2.5)
            }
            if isSelected {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .overlay(alignment: .leading) {
            if isEditable {
                resizeHandleZone(for: .leading)
            }
        }
        .overlay(alignment: .trailing) {
            if isEditable {
                resizeHandleZone(for: .trailing)
            }
        }
        .offset(
            x: previewOffsetX,
            y: yPosition + barInset
        )
        .gesture(
            isEditable ? DragGesture(minimumDistance: 2)
                .onChanged { value in
                    moveTranslation = value.translation.width
                }
                .onEnded { value in
                    let delta = roundedDayDelta(for: value.translation.width)
                    moveTranslation = 0
                    guard delta != 0 else { return }
                    onMoveTask?(delta)
                } : nil
        )
        .simultaneousGesture(TapGesture().onEnded { onSelectTask?() })
        .simultaneousGesture(
            TapGesture()
                .modifiers(.control)
                .onEnded { onStartLinkingFromTask?() }
        )
        .overlay(alignment: .trailing) {
            if let descriptor = task.baselineVarianceDescriptor, !isEditable, descriptor.days != 0 {
                Text(descriptor.label)
                    .font(.system(size: 8, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(descriptor.color.opacity(0.2))
                    .overlay(
                        Capsule()
                            .stroke(descriptor.color.opacity(0.6), lineWidth: 0.5)
                    )
                    .clipShape(Capsule())
                    .foregroundStyle(.primary)
                    .offset(x: 52)
            }
        }
        .shadow(color: isLinkSource ? Color.orange.opacity(0.26) : .clear, radius: 7, x: 0, y: 0)
        .help(editTooltipText)
    }

    private var resizeHandle: some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.9))
            .frame(width: handleWidth, height: barHeight - 2)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.accentColor.opacity(0.8), lineWidth: 0.8)
            )
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func resizeHandleZone(for edge: GanttResizeEdge) -> some View {
        let alignment: Alignment = edge == .leading ? .leading : .trailing

        Color.clear
            .frame(width: handleHitWidth, height: rowHeight)
            .overlay(alignment: alignment) {
                resizeHandle
                    .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 0)
            }
            .contentShape(Rectangle())
            .gesture(resizeGesture(for: edge))
    }

    private func resizeGesture(for edge: GanttResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                switch edge {
                case .leading:
                    leadingResizeTranslation = value.translation.width
                case .trailing:
                    trailingResizeTranslation = value.translation.width
                }
            }
            .onEnded { value in
                let delta = roundedDayDelta(for: value.translation.width)
                leadingResizeTranslation = 0
                trailingResizeTranslation = 0
                guard delta != 0 else { return }
                onResizeTask?(edge, delta)
            }
    }

    private func roundedDayDelta(for translation: CGFloat) -> Int {
        guard pixelsPerDay > 0 else { return 0 }
        return Int((translation / pixelsPerDay).rounded())
    }

    private var editTooltipText: String {
        guard isEditable else { return tooltipText }
        return tooltipText + "\n\nDrag the bar to move. Grab the larger edge handles to change start or finish. Control-click a task bar to start dependency linking instantly."
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

        path.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.5))
        path.addRect(CGRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + tick, y: rect.maxY - tick))
        path.addRect(CGRect(x: rect.maxX - 2, y: rect.minY, width: 2, height: rect.height))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - tick, y: rect.maxY - tick))

        return path
    }
}
