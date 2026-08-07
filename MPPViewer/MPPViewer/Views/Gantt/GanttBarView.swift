import SwiftUI
import AppKit

enum GanttResizeEdge {
    case leading
    case trailing
}

/// Subtle trackpad tick when a Gantt drag crosses a whole-day (or row) snap
/// boundary, giving alignment a tactile feel on Force Touch trackpads.
@MainActor
enum GanttHaptics {
    static func snap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

struct GanttBarView: View {
    let task: ProjectTask
    let startDate: Date
    let pixelsPerDay: CGFloat
    let rowIndex: Int
    let rowHeight: CGFloat
    var coordinateSpaceName: String = "GanttCanvasViewSpace"
    var isEditable: Bool = false
    // Summary bars can be dragged vertically to reorder (moving the whole
    // subtree) but not moved in time or resized.
    var reorderOnly: Bool = false
    var isSelected: Bool = false
    var isLinkSource: Bool = false
    var onMoveTask: ((Int) -> Void)? = nil
    var onReorderTask: ((Int) -> Void)? = nil
    var onResizeTask: ((GanttResizeEdge, Int) -> Void)? = nil
    var onSelectTask: (() -> Void)? = nil
    var onShowTaskDetails: ((CGPoint) -> Void)? = nil
    var onStartLinkingFromTask: (() -> Void)? = nil

    private enum MoveDragAxis {
        case undecided
        case horizontal
        case vertical
    }

    @State private var moveTranslation: CGFloat = 0
    @State private var rowTranslation: CGFloat = 0
    @State private var moveDragAxis: MoveDragAxis = .undecided
    @State private var leadingResizeTranslation: CGFloat = 0
    @State private var trailingResizeTranslation: CGFloat = 0
    @State private var lastHapticStep = 0

    private func hapticIfStepChanged(_ step: Int) {
        guard step != lastHapticStep else { return }
        lastHapticStep = step
        GanttHaptics.snap()
    }

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

    // While a drag is in flight the bar tracks the cursor continuously;
    // snapping to whole days happens only when the gesture ends. Quantizing
    // the live preview made dragging feel jerky.
    private var previewOffsetX: CGFloat {
        taskStartOffset + moveTranslation + leadingResizeTranslation
    }

    private var previewWidth: CGFloat {
        let width = taskWidth + trailingResizeTranslation - leadingResizeTranslation
        return max(minBarWidth, width)
    }

    private var isDragging: Bool {
        moveTranslation != 0 || rowTranslation != 0 || leadingResizeTranslation != 0 || trailingResizeTranslation != 0
    }

    private var rowPreviewDelta: Int {
        guard rowHeight > 0 else { return 0 }
        return Int((rowTranslation / rowHeight).rounded())
    }

    private var dragBadgeText: String? {
        func signed(_ days: Int) -> String {
            days > 0 ? "+\(days)d" : "\(days)d"
        }
        if rowTranslation != 0 {
            let rows = rowPreviewDelta
            return "Row " + (rows > 0 ? "+\(rows)" : "\(rows)")
        }
        if moveTranslation != 0 {
            return signed(movePreviewDays)
        }
        if leadingResizeTranslation != 0 {
            return "Start \(signed(leadingPreviewDays))"
        }
        if trailingResizeTranslation != 0 {
            return "Finish \(signed(trailingPreviewDays))"
        }
        return nil
    }

    private var barHeight: CGFloat {
        rowHeight - barInset * 2
    }

    // A custom per-task color wins over the default critical/accent scheme.
    private var customColor: Color? {
        task.barColorHex.flatMap { Color(hex: $0) }
    }

    private var barBaseColor: Color {
        customColor ?? (task.critical == true ? .red : .accentColor)
    }

    private var isCritical: Bool { task.critical == true }

    var body: some View {
        Group {
            if task.milestone == true {
                milestoneBar
            } else if task.summary == true {
                summaryBar
            } else {
                regularBar
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(isEditable ? "Drag to move or reorder; use the edge handles to change start or finish" : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityLabelText: String {
        let kind = task.milestone == true ? "Milestone" : (task.summary == true ? "Summary task" : "Task")
        var parts = ["\(kind): \(task.displayName)"]
        if let start = task.start {
            parts.append("starts \(DateFormatting.shortDate(start))")
        }
        if let finish = task.finish {
            parts.append("finishes \(DateFormatting.shortDate(finish))")
        }
        parts.append("\(task.percentCompleteDisplay) complete")
        if task.critical == true {
            parts.append("on the critical path")
        }
        return parts.joined(separator: ", ")
    }

    private var milestoneBar: some View {
        let size: CGFloat = barHeight * 0.7
        return DiamondShape()
            .fill(customColor ?? Color.orange)
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
                x: taskStartOffset + moveTranslation - size / 2,
                y: yPosition + (rowHeight - size) / 2 + rowTranslation
            )
            .gesture(
                isEditable ? DragGesture()
                    .onChanged(handleMoveDragChanged)
                    .onEnded(handleMoveDragEnded) : nil
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 2)
                    .onEnded { value in
                        guard isEditable else { return }
                        onShowTaskDetails?(
                            CGPoint(
                                x: taskStartOffset - size / 2 + value.location.x,
                                y: yPosition + (rowHeight - size) / 2 + value.location.y
                            )
                        )
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        onSelectTask?()
                        // In edit mode a plain click only selects so the
                        // details card never blocks dragging; use double-click
                        // for details instead.
                        guard !isEditable else { return }
                        onShowTaskDetails?(
                            CGPoint(
                                x: taskStartOffset - size / 2 + value.location.x,
                                y: yPosition + (rowHeight - size) / 2 + value.location.y
                            )
                        )
                    }
            )
            .simultaneousGesture(
                TapGesture()
                    .modifiers(.control)
                    .onEnded { onStartLinkingFromTask?() }
            )
            .help(editTooltipText)
        }

    private var summaryBar: some View {
        SummaryBarShape()
            .fill(customColor ?? Color.primary.opacity(0.7))
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
            // Taller transparent hit area so the thin bracket is easy to grab
            // for the reorder drag.
            .frame(height: rowHeight, alignment: .center)
            .contentShape(Rectangle())
            .overlay(alignment: .topLeading) {
                if isDragging, let dragBadgeText {
                    Text(dragBadgeText)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.9))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .offset(x: taskStartOffset, y: -6)
                        .fixedSize()
                }
            }
            .shadow(color: isLinkSource ? Color.orange.opacity(0.28) : .clear, radius: 6, x: 0, y: 0)
            .offset(
                x: taskStartOffset,
                y: yPosition + rowTranslation
            )
            .gesture(
                (isEditable && reorderOnly) ? DragGesture(minimumDistance: 3)
                    .onChanged(handleMoveDragChanged)
                    .onEnded(handleMoveDragEnded) : nil
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 2)
                    .onEnded { value in
                        guard isEditable else { return }
                        onShowTaskDetails?(
                            CGPoint(
                                x: taskStartOffset + value.location.x,
                                y: yPosition + value.location.y
                            )
                        )
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        onSelectTask?()
                        // In edit mode a plain click only selects so it never
                        // pops the details card while you're reordering.
                        guard !isEditable else { return }
                        onShowTaskDetails?(
                            CGPoint(
                                x: taskStartOffset + value.location.x,
                                y: yPosition + value.location.y
                            )
                        )
                    }
            )
            .simultaneousGesture(
                TapGesture()
                    .modifiers(.control)
                    .onEnded { onStartLinkingFromTask?() }
            )
            .help(isEditable ? tooltipText + "\n\nDrag up or down to reorder this phase and everything under it." : tooltipText)
    }

    private var regularBar: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(barBaseColor.opacity(0.3))

            let pct = (task.percentComplete ?? 0) / 100.0
            let fillWidth = previewWidth * CGFloat(pct)
            if fillWidth > 0 {
                RoundedRectangle(cornerRadius: 3)
                    .fill(barBaseColor)
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
            // Hue-independent cue for critical tasks: a diagonal hatch plus a
            // high-contrast dashed border so the critical path stays legible
            // under red–green color blindness and high-contrast mode, not by
            // red fill alone.
            if isCritical {
                DiagonalHatch()
                    .stroke(Color.primary.opacity(0.30), lineWidth: 0.7)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .allowsHitTesting(false)
                if !isEditable && !isSelected {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.primary.opacity(0.55), style: StrokeStyle(lineWidth: 1.1, dash: [2, 2]))
                }
            }
        }
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
            y: yPosition + barInset + rowTranslation
        )
        .gesture(
            isEditable ? DragGesture(minimumDistance: 2)
                .onChanged(handleMoveDragChanged)
                .onEnded(handleMoveDragEnded) : nil
        )
        .simultaneousGesture(
            SpatialTapGesture(count: 2)
                .onEnded { value in
                    guard isEditable else { return }
                    onShowTaskDetails?(
                        CGPoint(
                            x: previewOffsetX + value.location.x,
                            y: yPosition + barInset + value.location.y
                        )
                    )
                }
        )
        .simultaneousGesture(
            SpatialTapGesture()
                .onEnded { value in
                    onSelectTask?()
                    // In edit mode a plain click only selects so the details
                    // card never blocks dragging or the resize handles; use
                    // double-click for details instead.
                    guard !isEditable else { return }
                    onShowTaskDetails?(
                        CGPoint(
                            x: previewOffsetX + value.location.x,
                            y: yPosition + barInset + value.location.y
                        )
                    )
                }
        )
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
        .overlay(alignment: .topLeading) {
            if isDragging, let dragBadgeText {
                Text(dragBadgeText)
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.9))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .offset(y: -(rowHeight - barInset))
                    .fixedSize()
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
                    hapticIfStepChanged(leadingPreviewDays)
                case .trailing:
                    trailingResizeTranslation = value.translation.width
                    hapticIfStepChanged(trailingPreviewDays)
                }
            }
            .onEnded { value in
                let delta = roundedDayDelta(for: value.translation.width)
                leadingResizeTranslation = 0
                trailingResizeTranslation = 0
                lastHapticStep = 0
                guard delta != 0 else { return }
                onResizeTask?(edge, delta)
            }
    }

    private func handleMoveDragChanged(_ value: DragGesture.Value) {
        if moveDragAxis == .undecided {
            let dx = abs(value.translation.width)
            let dy = abs(value.translation.height)
            guard dx > 3 || dy > 3 else { return }
            // Summaries only reorder; regular bars pick the dominant axis.
            moveDragAxis = reorderOnly ? .vertical : ((dy > dx && onReorderTask != nil) ? .vertical : .horizontal)
        }
        switch moveDragAxis {
        case .horizontal:
            moveTranslation = value.translation.width
            hapticIfStepChanged(movePreviewDays)
        case .vertical:
            rowTranslation = value.translation.height
            hapticIfStepChanged(rowPreviewDelta)
        case .undecided:
            break
        }
    }

    private func handleMoveDragEnded(_ value: DragGesture.Value) {
        let axis = moveDragAxis
        moveDragAxis = .undecided
        lastHapticStep = 0
        switch axis {
        case .horizontal:
            let delta = roundedDayDelta(for: value.translation.width)
            moveTranslation = 0
            guard delta != 0 else { return }
            onMoveTask?(delta)
        case .vertical:
            let rows = Int((value.translation.height / max(1, rowHeight)).rounded())
            rowTranslation = 0
            guard rows != 0 else { return }
            onReorderTask?(rows)
        case .undecided:
            moveTranslation = 0
            rowTranslation = 0
        }
    }

    private func roundedDayDelta(for translation: CGFloat) -> Int {
        guard pixelsPerDay > 0 else { return 0 }
        return Int((translation / pixelsPerDay).rounded())
    }

    private var editTooltipText: String {
        guard isEditable else { return tooltipText }
        return tooltipText + "\n\nDrag the bar sideways to move it in time, or up and down to reorder it in the task list. Grab the larger edge handles to change start or finish. Double-click for task details. Command-click to select several bars, then move them together with the arrow keys (Shift for a week) or by dragging any selected bar. Control-click a task bar to start dependency linking instantly."
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

/// Evenly spaced diagonal lines used as a hue-independent texture cue for
/// critical-path bars.
struct DiagonalHatch: Shape {
    var spacing: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
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
