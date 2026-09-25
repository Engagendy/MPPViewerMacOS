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

/// Live position of the bar being dragged, so dependency lines can follow it
/// before the drop commits. Only the small live-link layer observes the
/// per-tick offsets; the canvas itself reacts just to `taskID` changing at
/// drag start and end.
@Observable
final class GanttDragPreview {
    var taskID: Int?
    var offset: CGSize = .zero
    var leadingDelta: CGFloat = 0
    var trailingDelta: CGFloat = 0

    func update(taskID: Int, offset: CGSize, leadingDelta: CGFloat, trailingDelta: CGFloat) {
        if self.taskID != taskID { self.taskID = taskID }
        if self.offset != offset { self.offset = offset }
        if self.leadingDelta != leadingDelta { self.leadingDelta = leadingDelta }
        if self.trailingDelta != trailingDelta { self.trailingDelta = trailingDelta }
    }

    func clear() {
        guard taskID != nil else { return }
        taskID = nil
        offset = .zero
        leadingDelta = 0
        trailingDelta = 0
    }
}

/// Scrolls the Gantt's enclosing scroll views while a bar drag holds the
/// pointer near their edge. SwiftUI's ScrollView is backed by NSScrollView on
/// macOS, so the views under the pointer are found through AppKit and nudged
/// on a display-rate timer; each applied scroll is reported back so the drag
/// can add it to its translation and the bar stays under the pointer.
@MainActor
final class GanttAutoScroller {
    static let shared = GanttAutoScroller()

    /// Axes the current drag may scroll along (moving in time → horizontal,
    /// reordering → vertical).
    var axes: Axis.Set = []

    private weak var horizontalScrollView: NSScrollView?
    private weak var verticalScrollView: NSScrollView?
    private var timer: Timer?
    private var onScroll: ((CGSize) -> Void)?

    private let edgeBand: CGFloat = 40
    private let maxStep: CGFloat = 16

    var isActive: Bool { timer != nil }

    func begin(onScroll: @escaping (CGSize) -> Void) {
        end()
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let pointInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        guard let hitView = window.contentView?.superview?.hitTest(pointInWindow) else { return }

        var ancestor: NSView? = hitView
        while let view = ancestor {
            if let scrollView = view as? NSScrollView, let document = scrollView.documentView {
                let visible = scrollView.contentView.bounds.size
                if horizontalScrollView == nil, document.frame.width > visible.width + 1 {
                    horizontalScrollView = scrollView
                }
                if verticalScrollView == nil, document.frame.height > visible.height + 1 {
                    verticalScrollView = scrollView
                }
            }
            ancestor = view.superview
        }
        guard horizontalScrollView != nil || verticalScrollView != nil else { return }

        self.onScroll = onScroll
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func end() {
        timer?.invalidate()
        timer = nil
        onScroll = nil
        axes = []
        horizontalScrollView = nil
        verticalScrollView = nil
    }

    private func tick() {
        // The button went up without the gesture ending (e.g. cancelled):
        // stop scrolling rather than run on forever.
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            end()
            return
        }
        var applied = CGSize.zero
        if axes.contains(.horizontal), let scrollView = horizontalScrollView {
            applied.width = scroll(scrollView, horizontally: true)
        }
        if axes.contains(.vertical), let scrollView = verticalScrollView {
            applied.height = scroll(scrollView, horizontally: false)
        }
        if applied != .zero {
            onScroll?(applied)
        }
    }

    /// Scrolls one axis toward the edge the pointer is near and returns the
    /// distance actually scrolled, in document (canvas) points.
    private func scroll(_ scrollView: NSScrollView, horizontally: Bool) -> CGFloat {
        guard let window = scrollView.window, let document = scrollView.documentView else { return 0 }
        let clip = scrollView.contentView
        let pointer = clip.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let bounds = clip.bounds

        // Distance past each edge band, as a signed step toward that edge.
        func step(distanceToLow: CGFloat, distanceToHigh: CGFloat) -> CGFloat {
            if distanceToLow < edgeBand {
                return -maxStep * min(1, (edgeBand - distanceToLow) / edgeBand)
            }
            if distanceToHigh < edgeBand {
                return maxStep * min(1, (edgeBand - distanceToHigh) / edgeBand)
            }
            return 0
        }

        var origin = bounds.origin
        let delta: CGFloat
        if horizontally {
            let proposed = step(distanceToLow: pointer.x - bounds.minX, distanceToHigh: bounds.maxX - pointer.x)
            guard proposed != 0 else { return 0 }
            let maxX = max(0, document.frame.width - bounds.width)
            origin.x = min(max(0, bounds.origin.x + proposed), maxX)
            delta = origin.x - bounds.origin.x
        } else {
            // In a flipped document the top edge is minY; otherwise maxY.
            let flipped = document.isFlipped
            let towardTop = flipped ? pointer.y - bounds.minY : bounds.maxY - pointer.y
            let towardBottom = flipped ? bounds.maxY - pointer.y : pointer.y - bounds.minY
            let downward = step(distanceToLow: towardTop, distanceToHigh: towardBottom)
            guard downward != 0 else { return 0 }
            let maxY = max(0, document.frame.height - bounds.height)
            let proposedY = bounds.origin.y + (flipped ? downward : -downward)
            origin.y = min(max(0, proposedY), maxY)
            let scrolled = origin.y - bounds.origin.y
            delta = flipped ? scrolled : -scrolled
        }
        guard delta != 0 else { return 0 }
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
        return delta
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
    var dragPreview: GanttDragPreview? = nil

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
    // Raw pointer translation of the current drag, plus how far auto-scroll
    // has moved the canvas under the pointer since the drag began.
    @State private var pointerTranslation: CGSize = .zero
    @State private var autoScrollOffset: CGSize = .zero
    @State private var activeResizeEdge: GanttResizeEdge?

    private var effectiveTranslation: CGSize {
        CGSize(
            width: pointerTranslation.width + autoScrollOffset.width,
            height: pointerTranslation.height + autoScrollOffset.height
        )
    }

    private func hapticIfStepChanged(_ step: Int) {
        guard step != lastHapticStep else { return }
        lastHapticStep = step
        GanttHaptics.snap()
    }

    private let barInset: CGFloat = 4
    private let minBarWidth: CGFloat = 4
    private let handleWidth: CGFloat = 5
    // Resize grips straddle the bar edge and reach only a few points inside
    // it, so the body of even a short bar stays grabbable for moving.
    private let handleHitWidth: CGFloat = 12
    private let maxHandleInset: CGFloat = 4
    // Movement (in points) before a drag commits to moving in time or
    // reordering; horizontal wins unless the drag is clearly vertical.
    private let axisDecisionDistance: CGFloat = 4
    private let verticalAxisBias: CGFloat = 1.5

    /// Drags are measured in the canvas space so the translation stays
    /// stable while the bar itself moves under the pointer.
    private var dragCoordinateSpace: NamedCoordinateSpace {
        .named(coordinateSpaceName)
    }

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
            // The diamond alone is a small target; grab anywhere in its box
            // plus a few points of slack.
            .contentShape(Rectangle().inset(by: -barInset))
            .offset(
                x: taskStartOffset + moveTranslation - size / 2,
                y: yPosition + (rowHeight - size) / 2 + rowTranslation
            )
            .gesture(
                isEditable ? DragGesture(minimumDistance: 2, coordinateSpace: dragCoordinateSpace)
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
                (isEditable && reorderOnly) ? DragGesture(minimumDistance: 2, coordinateSpace: dragCoordinateSpace)
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
        // Grab the full row height (and a little either side) so short,
        // thin bars are easy to pick up.
        .contentShape(Rectangle().inset(by: -barInset))
        .overlay(alignment: .leading) {
            if isEditable, activeResizeEdge.map({ $0 == .leading }) ?? !isDragging {
                resizeHandleZone(for: .leading)
            }
        }
        .overlay(alignment: .trailing) {
            if isEditable, activeResizeEdge.map({ $0 == .trailing }) ?? !isDragging {
                resizeHandleZone(for: .trailing)
            }
        }
        .offset(
            x: previewOffsetX,
            y: yPosition + barInset + rowTranslation
        )
        .gesture(
            isEditable ? DragGesture(minimumDistance: 2, coordinateSpace: dragCoordinateSpace)
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
        // Only a sliver of the grip overlaps the bar (at most a fifth of a
        // short bar); the rest sits just outside the edge.
        let inside = min(maxHandleInset, previewWidth * 0.2)
        let outside = handleHitWidth - inside
        let edgeOffsetInZone = (edge == .leading ? outside : inside) - handleHitWidth / 2

        Color.clear
            .frame(width: handleHitWidth, height: rowHeight)
            .overlay {
                if previewWidth >= 16 || isSelected {
                    resizeHandle
                        .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 0)
                        .offset(x: edgeOffsetInZone)
                }
            }
            .contentShape(Rectangle())
            .offset(x: edge == .leading ? -outside : outside)
            .gesture(resizeGesture(for: edge))
            .cursor(.resizeLeftRight)
    }

    private func resizeGesture(for edge: GanttResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: dragCoordinateSpace)
            .onChanged { value in
                pointerTranslation = value.translation
                if activeResizeEdge == nil {
                    activeResizeEdge = edge
                    beginAutoScroll(axes: .horizontal)
                }
                applyResizeTranslation()
            }
            .onEnded { value in
                pointerTranslation = value.translation
                let delta = roundedDayDelta(for: effectiveTranslation.width)
                finishDrag()
                guard delta != 0 else { return }
                onResizeTask?(edge, delta)
            }
    }

    private func applyResizeTranslation() {
        switch activeResizeEdge {
        case .leading:
            leadingResizeTranslation = effectiveTranslation.width
            hapticIfStepChanged(leadingPreviewDays)
        case .trailing:
            trailingResizeTranslation = effectiveTranslation.width
            hapticIfStepChanged(trailingPreviewDays)
        case nil:
            return
        }
        publishDragPreview()
    }

    private func beginAutoScroll(axes: Axis.Set) {
        autoScrollOffset = .zero
        GanttAutoScroller.shared.begin { delta in
            autoScrollOffset.width += delta.width
            autoScrollOffset.height += delta.height
            if activeResizeEdge != nil {
                applyResizeTranslation()
            } else {
                applyMoveTranslation()
            }
        }
        GanttAutoScroller.shared.axes = axes
    }

    private func publishDragPreview() {
        dragPreview?.update(
            taskID: task.uniqueID,
            offset: CGSize(width: moveTranslation, height: rowTranslation),
            leadingDelta: leadingResizeTranslation,
            trailingDelta: trailingResizeTranslation
        )
    }

    /// Resets all in-flight drag state once a move, reorder or resize ends.
    private func finishDrag() {
        GanttAutoScroller.shared.end()
        dragPreview?.clear()
        moveDragAxis = .undecided
        activeResizeEdge = nil
        moveTranslation = 0
        rowTranslation = 0
        leadingResizeTranslation = 0
        trailingResizeTranslation = 0
        pointerTranslation = .zero
        autoScrollOffset = .zero
        lastHapticStep = 0
    }

    private func handleMoveDragChanged(_ value: DragGesture.Value) {
        pointerTranslation = value.translation
        if !GanttAutoScroller.shared.isActive, moveDragAxis == .undecided {
            beginAutoScroll(axes: [])
        }
        applyMoveTranslation()
    }

    private func applyMoveTranslation() {
        let translation = effectiveTranslation
        let dx = abs(translation.width)
        let dy = abs(translation.height)
        let canReorder = onReorderTask != nil
        let canMove = onMoveTask != nil
        if moveDragAxis == .undecided {
            guard dx > axisDecisionDistance || dy > axisDecisionDistance else { return }
            // Summaries only reorder; other bars move in time unless the drag
            // is clearly vertical, so a slightly wobbly sideways drag never
            // turns into a reorder.
            if reorderOnly || !canMove {
                moveDragAxis = .vertical
            } else {
                moveDragAxis = (canReorder && dy > dx * verticalAxisBias) ? .vertical : .horizontal
            }
        } else if !reorderOnly, canMove, canReorder {
            // Let the drag change its mind when the pointer clearly heads the
            // other way, instead of forcing a release and re-grab.
            if moveDragAxis == .horizontal, dy > rowHeight, dy > dx * 2 {
                moveDragAxis = .vertical
                moveTranslation = 0
            } else if moveDragAxis == .vertical, dx > pixelsPerDay * 2, dx > max(rowHeight, dy * 2) {
                moveDragAxis = .horizontal
                rowTranslation = 0
            }
        }
        switch moveDragAxis {
        case .horizontal:
            GanttAutoScroller.shared.axes = .horizontal
            moveTranslation = translation.width
            hapticIfStepChanged(movePreviewDays)
        case .vertical:
            GanttAutoScroller.shared.axes = .vertical
            rowTranslation = translation.height
            hapticIfStepChanged(rowPreviewDelta)
        case .undecided:
            return
        }
        publishDragPreview()
    }

    private func handleMoveDragEnded(_ value: DragGesture.Value) {
        pointerTranslation = value.translation
        let translation = effectiveTranslation
        let axis = moveDragAxis
        finishDrag()
        switch axis {
        case .horizontal:
            let delta = roundedDayDelta(for: translation.width)
            guard delta != 0 else { return }
            onMoveTask?(delta)
        case .vertical:
            let rows = Int((translation.height / max(1, rowHeight)).rounded())
            guard rows != 0 else { return }
            onReorderTask?(rows)
        case .undecided:
            break
        }
    }

    private func roundedDayDelta(for translation: CGFloat) -> Int {
        guard pixelsPerDay > 0 else { return 0 }
        return Int((translation / pixelsPerDay).rounded())
    }

    private var editTooltipText: String {
        guard isEditable else { return tooltipText }
        return tooltipText + "\n\nDrag the bar sideways to move it in time, or up and down to reorder it in the task list. Grab just past either end of the bar to change start or finish. Drag toward the chart's edge to scroll. Double-click for task details. Command-click to select several bars, then move them together with the arrow keys (Shift for a week) or by dragging any selected bar. Control-click a task bar to start dependency linking instantly."
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
