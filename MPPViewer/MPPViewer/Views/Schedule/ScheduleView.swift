import SwiftUI
import AppKit

/// Keeps the task-list pane and the timeline pane scrolling in lockstep.
/// Both panes are AppKit `NSScrollView`s; when either scrolls vertically we
/// mirror the offset onto the other — accounting for the date header that sits
/// inside the timeline's scroll area but not the list's — and publish the
/// timeline's visible rect so the Gantt canvas can cull off-screen rows/days.
final class ScheduleScrollCoordinator: ObservableObject {
    /// Timeline's visible rectangle in document coordinates (drives culling).
    @Published var timelineVisibleRect: CGRect = .zero
    /// Task list's vertical scroll offset (drives its own row culling).
    @Published var listOffsetY: CGFloat = 0

    /// Height of the date header above the rows inside the timeline scroll
    /// area. The list has no equivalent, so row N aligns when the list offset
    /// equals the timeline offset minus this header height.
    var headerHeight: CGFloat = 44

    private weak var timeline: NSScrollView?
    private weak var list: NSScrollView?
    private var suppress = false
    private var tokens: [NSObjectProtocol] = []

    func attachTimeline(_ scrollView: NSScrollView) {
        if timeline !== scrollView {
            timeline = scrollView
            observe(scrollView, isTimeline: true)
            observeFrame(scrollView)
        }
        // Re-read on every attach. updateNSView calls this whenever the content
        // resizes (auto-fit, zoom), and the first synchronous read happens
        // before layout settles, so refresh async to capture the real rect.
        refreshTimelineRect()
    }

    func attachList(_ scrollView: NSScrollView) {
        guard list !== scrollView else { return }
        list = scrollView
        observe(scrollView, isTimeline: false)
    }

    /// Reads the timeline's current visible rect after the layout pass and
    /// publishes it so the Gantt canvas culls against the correct viewport.
    /// Without this, the initial (pre-layout) rect would stick and most bars
    /// would stay culled until a zoom change forced a relayout.
    func refreshTimelineRect() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let timeline = self.timeline else { return }
            let rect = timeline.documentVisibleRect
            if rect != self.timelineVisibleRect {
                self.timelineVisibleRect = rect
            }
        }
    }

    private func observeFrame(_ scrollView: NSScrollView) {
        scrollView.postsFrameChangedNotifications = true
        let token = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.refreshTimelineRect()
        }
        tokens.append(token)
    }

    private func observe(_ scrollView: NSScrollView, isTimeline: Bool) {
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        let token = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clip,
            queue: .main
        ) { [weak self, weak scrollView] _ in
            guard let self, let scrollView else { return }
            self.handleScroll(scrollView, isTimeline: isTimeline)
        }
        tokens.append(token)
    }

    private func handleScroll(_ scrollView: NSScrollView, isTimeline: Bool) {
        let originY = scrollView.contentView.bounds.origin.y
        // Keep the visible rect fresh even during a mirrored scroll so culling
        // tracks continuously.
        if isTimeline {
            timelineVisibleRect = scrollView.documentVisibleRect
        }
        guard !suppress else { return }
        suppress = true
        defer { suppress = false }
        if isTimeline {
            let target = max(0, originY - headerHeight)
            listOffsetY = target
            if let list { setOriginY(list, target) }
        } else {
            listOffsetY = originY
            if let timeline {
                setOriginY(timeline, originY + headerHeight)
                timelineVisibleRect = timeline.documentVisibleRect
            }
        }
    }

    private func setOriginY(_ scrollView: NSScrollView, _ y: CGFloat) {
        let clip = scrollView.contentView
        let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height)
        let clamped = min(max(0, y), maxY)
        guard abs(clamped - clip.bounds.origin.y) > 0.01 else { return }
        clip.scroll(to: CGPoint(x: clip.bounds.origin.x, y: clamped))
        scrollView.reflectScrolledClipView(clip)
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}

private struct ScheduleDerivedContent {
    let visibleTasks: [ProjectTask]
    let rowIndexByTaskID: [Int: Int]
    let totalDays: Int
    let dateRange: (start: Date, end: Date)

    static func build(project: ProjectModel, searchText: String, collapsedIDs: Set<Int>) -> ScheduleDerivedContent {
        let filteredTasks: [ProjectTask]
        if searchText.isEmpty {
            filteredTasks = project.rootTasks
        } else {
            filteredTasks = filterTasks(project.rootTasks, searchText: searchText.lowercased())
        }

        let visibleTasks = flattenTasks(filteredTasks, collapsedIDs: collapsedIDs)
        let rowIndexByTaskID = Dictionary(nonThrowingUniquePairs: visibleTasks.enumerated().map { ($1.uniqueID, $0) })
        let dateRange = GanttDateHelpers.dateRange(for: project.tasks)
        return ScheduleDerivedContent(
            visibleTasks: visibleTasks,
            rowIndexByTaskID: rowIndexByTaskID,
            totalDays: GanttDateHelpers.totalDays(for: dateRange),
            dateRange: dateRange
        )
    }

    private static func flattenTasks(_ tasks: [ProjectTask], collapsedIDs: Set<Int>) -> [ProjectTask] {
        var result: [ProjectTask] = []
        for task in tasks {
            result.append(task)
            if !task.children.isEmpty && !collapsedIDs.contains(task.uniqueID) {
                result.append(contentsOf: flattenTasks(task.children, collapsedIDs: collapsedIDs))
            }
        }
        return result
    }

    private static func filterTasks(_ tasks: [ProjectTask], searchText: String) -> [ProjectTask] {
        var result: [ProjectTask] = []
        for task in tasks {
            let childMatches = filterTasks(task.children, searchText: searchText)
            let selfMatches = task.name?.lowercased().contains(searchText) == true
            if selfMatches || !childMatches.isEmpty {
                result.append(task)
            }
        }
        return result
    }
}

struct ScheduleView: View {
    let project: ProjectModel
    let searchText: String

    @State private var derivedContent: ScheduleDerivedContent
    @State private var pixelsPerDay: CGFloat = 8
    @State private var timelineViewportWidth: CGFloat = 0
    @State private var shouldAutoFitTimeline = true
    @State private var collapsedIDs: Set<Int> = []
    @StateObject private var scrollCoordinator = ScheduleScrollCoordinator()
    @AppStorage("scheduleTaskListWidth") private var taskListWidth: Double = 470
    @State private var dividerDragStartWidth: CGFloat?
    @State private var criticalPathOnly: Bool = false
    @State private var showDependencyLinks: Bool = true
    @State private var showBaseline: Bool = false
    @State private var searchDebounceWorkItem: DispatchWorkItem?
    @State private var selectedScheduleTaskID: Int?
    private let rowHeight: CGFloat = 24

    private var visibleTasks: [ProjectTask] {
        derivedContent.visibleTasks
    }

    private var dateRange: (start: Date, end: Date) {
        derivedContent.dateRange
    }

    private var totalDays: Int {
        derivedContent.totalDays
    }

    private var timelineWidth: CGFloat {
        CGFloat(totalDays) * pixelsPerDay
    }

    private var chartScrollableWidth: CGFloat {
        timelineWidth + 460
    }

    private var ganttHeaderHeight: CGFloat {
        pixelsPerDay < 15 ? 64 : 44
    }

    private var taskRowsContentHeight: CGFloat {
        CGFloat(visibleTasks.count) * rowHeight
    }

    init(project: ProjectModel, searchText: String) {
        self.project = project
        self.searchText = searchText
        self._derivedContent = State(initialValue: ScheduleDerivedContent.build(project: project, searchText: searchText, collapsedIDs: []))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Schedule")
                    .font(.headline)
                Text("(\(visibleTasks.count) tasks)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    Button("Expand All") {
                        collapsedIDs.removeAll()
                    }
                    .buttonStyle(.accessoryBar)
                    .font(.caption)
                    .disabled(collapsedIDs.isEmpty)

                    Button("Collapse All") {
                        for task in allTasksFlat(project.rootTasks) where task.summary == true && !task.children.isEmpty {
                            collapsedIDs.insert(task.uniqueID)
                        }
                    }
                    .buttonStyle(.accessoryBar)
                    .font(.caption)

                    Divider().frame(height: 16)

                    Toggle(isOn: $criticalPathOnly) {
                        Label("Critical Path", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                    }
                    .toggleStyle(.button)
                    .hoverHighlight()
                    .buttonStyle(.bordered)
                    .tint(criticalPathOnly ? .red : nil)
                    .help("Highlights tasks marked critical by the imported schedule and dims non-critical tasks.")

                    Toggle(isOn: $showDependencyLinks) {
                        Label("Links", systemImage: "link")
                            .font(.caption)
                    }
                    .toggleStyle(.button)
                    .hoverHighlight()
                    .buttonStyle(.bordered)
                    .tint(showDependencyLinks ? .blue : nil)
                    .help("Shows predecessor and successor dependency links between tasks.")

                    Toggle(isOn: $showBaseline) {
                        Label("Baseline", systemImage: "clock.arrow.2.circlepath")
                            .font(.caption)
                    }
                    .toggleStyle(.button)
                    .hoverHighlight()
                    .buttonStyle(.bordered)
                    .tint(showBaseline ? .gray : nil)
                    .help("Shows the saved baseline schedule as gray bars below the current bars, with start/finish variance badges.")

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
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if visibleTasks.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "rectangle.split.2x1")
                    .topAlignedEmptyState()
            } else {
                scheduleContent
            }
        }
        .onAppear {
            refreshDerivedContent()
        }
        .onChange(of: collapsedIDs) { _, _ in
            refreshDerivedContent()
        }
        .onChange(of: searchText) { _, _ in
            scheduleSearchRefresh()
        }
        .onChange(of: scheduleRefreshSignature) { _, _ in
            refreshDerivedContent()
        }
    }

    // MARK: - Combined Schedule Content

    /// Matches GanttChartView: trailing area past the last activity so bar
    /// labels of the final tasks stay readable and the chart always has
    /// horizontal room to scroll into.
    private let timelineTrailingLabelWidth: CGFloat = 420

    private var timelineScrollableWidth: CGFloat {
        timelineWidth + timelineTrailingLabelWidth
    }

    /// Two panes side by side, each with its own native scroller: the task
    /// list scrolls vertically on its own, and the timeline scrolls both
    /// axes on its own. Pure SwiftUI, so it stays inside the safe area.
    private var scheduleContent: some View {
        GeometryReader { geometry in
            let width = CGFloat(taskListWidth)
            let viewportWidth = max(geometry.size.width - width - 1, 1)
            let maxListWidth = max(300, geometry.size.width - 360)

            HStack(spacing: 0) {
                taskListPane(availableHeight: geometry.size.height)

                resizableDivider(maxWidth: maxListWidth)

                timelinePane
            }
            .onAppear {
                timelineViewportWidth = viewportWidth
                scrollCoordinator.headerHeight = ganttHeaderHeight
                applyAutoFitIfNeeded()
            }
            .onChange(of: viewportWidth) { _, newWidth in
                timelineViewportWidth = newWidth
                applyAutoFitIfNeeded()
            }
            .onChange(of: totalDays) { _, _ in
                applyAutoFitIfNeeded()
            }
            .onChange(of: ganttHeaderHeight) { _, newHeight in
                scrollCoordinator.headerHeight = newHeight
            }
            .onChange(of: pixelsPerDay) { _, _ in
                // Zoom changes the day span of the same viewport; refresh so the
                // canvas culls against the new layout.
                scrollCoordinator.refreshTimelineRect()
            }
        }
    }

    /// A draggable handle over the pane divider. Drag to resize the task list,
    /// double-click to reset to the default width.
    private func resizableDivider(maxWidth: CGFloat) -> some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(width: 10)
                    .contentShape(Rectangle())
                    .cursor(.resizeLeftRight)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let start = dividerDragStartWidth ?? CGFloat(taskListWidth)
                                if dividerDragStartWidth == nil { dividerDragStartWidth = start }
                                taskListWidth = Double(min(max(300, start + value.translation.width), maxWidth))
                            }
                            .onEnded { _ in dividerDragStartWidth = nil }
                    )
                    .onTapGesture(count: 2) { taskListWidth = 470 }
            }
    }

    private func taskListPane(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Column headers stay pinned while the rows scroll below them.
            HStack(spacing: 0) {
                Text("ID")
                    .frame(width: 40, alignment: .leading)
                Text("Name")
                    .frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)
                Text("Duration")
                    .frame(width: 70, alignment: .trailing)
                Text("Start")
                    .frame(width: 80, alignment: .trailing)
                Text("Finish")
                    .frame(width: 80, alignment: .trailing)
                Text("% Done")
                    .frame(width: 50, alignment: .trailing)
            }
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Hosted in an AppKit scroll view synced to the timeline so rows
            // and bars stay aligned when either side scrolls.
            ListScrollView(
                contentSize: CGSize(width: CGFloat(taskListWidth), height: taskRowsContentHeight),
                coordinator: scrollCoordinator
            ) {
                taskListRows(availableHeight: availableHeight)
            }
        }
        .frame(width: CGFloat(taskListWidth), alignment: .topLeading)
    }

    /// Only materializes the rows within the scrolled viewport (plus overscan),
    /// positioned absolutely inside a full-height container.
    private func taskListRows(availableHeight: CGFloat) -> some View {
        let width = CGFloat(taskListWidth)
        let offsetY = scrollCoordinator.listOffsetY
        let viewportH = max(scrollCoordinator.timelineVisibleRect.height, availableHeight)
        let overscan = 4
        let count = visibleTasks.count
        let first = max(0, Int(offsetY / rowHeight) - overscan)
        let last = min(count, Int((offsetY + viewportH) / rowHeight) + overscan)

        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: width, height: taskRowsContentHeight)
            ForEach(first..<max(first, last), id: \.self) { index in
                scheduleTaskRow(task: visibleTasks[index], index: index)
                    .frame(width: width)
                    .offset(y: CGFloat(index) * rowHeight)
            }
        }
        .frame(width: width, height: taskRowsContentHeight, alignment: .topLeading)
    }

    private var timelineCanvasVisibleRect: CGRect {
        let rect = scrollCoordinator.timelineVisibleRect
        guard rect.height > 0 else {
            // Before the scroll view reports, render everything (no culling).
            return CGRect(x: 0, y: 0, width: timelineScrollableWidth, height: taskRowsContentHeight)
        }
        return CGRect(
            x: rect.minX,
            y: max(0, rect.minY - ganttHeaderHeight),
            width: rect.width,
            height: rect.height
        )
    }

    private var timelinePane: some View {
        BothAxesScrollView(
            contentSize: CGSize(
                width: timelineScrollableWidth,
                height: ganttHeaderHeight + taskRowsContentHeight
            ),
            onAttach: { scrollCoordinator.attachTimeline($0) }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                GanttHeaderView(
                    dateRange: dateRange,
                    pixelsPerDay: pixelsPerDay,
                    totalWidth: timelineScrollableWidth
                )
                .frame(height: ganttHeaderHeight)

                GanttCanvasView(
                    tasks: visibleTasks,
                    allTasks: project.tasksByID,
                    rowIndexByTaskID: derivedContent.rowIndexByTaskID,
                    startDate: dateRange.start,
                    totalDays: totalDays,
                    pixelsPerDay: pixelsPerDay,
                    rowHeight: rowHeight,
                    visibleRect: timelineCanvasVisibleRect,
                    criticalPathOnly: criticalPathOnly,
                    showBaseline: showBaseline,
                    showDependencyLinks: showDependencyLinks,
                    selectedTaskID: selectedScheduleTaskID,
                    onSelectTask: { selectedScheduleTaskID = $0 }
                )
                .frame(width: timelineScrollableWidth, height: taskRowsContentHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func scheduleTaskRow(task: ProjectTask, index: Int) -> some View {
        let isSummaryWithChildren = task.summary == true && !task.children.isEmpty
        let isCollapsed = collapsedIDs.contains(task.uniqueID)

        return HStack(spacing: 0) {
            Text(task.id.map(String.init) ?? "")
                .monospacedDigit()
                .frame(width: 40, alignment: .leading)

            HStack(spacing: 2) {
                let indent = CGFloat((task.outlineLevel ?? 1) - 1) * 12
                Spacer().frame(width: max(0, indent))

                if isSummaryWithChildren {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                } else {
                    Spacer().frame(width: 10)
                }

                if task.summary == true {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.blue)
                } else if task.milestone == true {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                }

                if task.critical == true {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.red)
                        .help("On the critical path")
                }

                Text(task.displayName)
                    .fontWeight(task.summary == true ? .semibold : .regular)
                    .foregroundStyle(task.critical == true ? .red : .primary)
                    .lineLimit(1)
            }
            .frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)

            Text(task.durationDisplay)
                .frame(width: 70, alignment: .trailing)

            Text(DateFormatting.shortDate(task.start))
                .frame(width: 80, alignment: .trailing)

            Text(DateFormatting.shortDate(task.finish))
                .frame(width: 80, alignment: .trailing)

            Text(task.percentCompleteDisplay)
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 8)
        .frame(height: rowHeight)
        .background(
            selectedScheduleTaskID == task.uniqueID
                ? Color.accentColor.opacity(0.16)
                : (index % 2 == 0 ? Color.gray.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedScheduleTaskID = task.uniqueID
            if isSummaryWithChildren {
                if isCollapsed {
                    collapsedIDs.remove(task.uniqueID)
                } else {
                    collapsedIDs.insert(task.uniqueID)
                }
            }
        }
    }

    // MARK: - Right Pane: Gantt

    // MARK: - Helpers

    private func allTasksFlat(_ tasks: [ProjectTask]) -> [ProjectTask] {
        var result: [ProjectTask] = []
        for task in tasks {
            result.append(task)
            if !task.children.isEmpty {
                result.append(contentsOf: allTasksFlat(task.children))
            }
        }
        return result
    }

    private func applyAutoFitIfNeeded() {
        guard shouldAutoFitTimeline, timelineViewportWidth > 0 else { return }
        pixelsPerDay = fittedPixelsPerDay(for: timelineViewportWidth)
    }

    private func fittedPixelsPerDay(for viewportWidth: CGFloat) -> CGFloat {
        max(2, min(100, viewportWidth / CGFloat(max(totalDays, 1))))
    }

    private var scheduleRefreshSignature: Int {
        var hasher = Hasher()
        hasher.combine(project.tasks.count)
        for task in project.tasks {
            hasher.combine(task.uniqueID)
            hasher.combine(task.start ?? "")
            hasher.combine(task.finish ?? "")
            hasher.combine(task.percentComplete ?? 0)
            hasher.combine(task.summary == true)
            hasher.combine(task.children.count)
        }
        return hasher.finalize()
    }

    private func refreshDerivedContent() {
        withAnimation(nil) {
            derivedContent = ScheduleDerivedContent.build(project: project, searchText: searchText, collapsedIDs: collapsedIDs)
        }
    }

    private func scheduleSearchRefresh() {
        searchDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            refreshDerivedContent()
        }
        searchDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }
}

private struct ScheduleScrollWheelCapture: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelView {
        let view = ScrollWheelView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelView, context: Context) {
        nsView.onScroll = onScroll
    }

    final class ScrollWheelView: NSView {
        var onScroll: ((CGFloat) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            if abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) {
                onScroll?(event.scrollingDeltaY)
            } else {
                super.scrollWheel(with: event)
            }
        }
    }
}

/// Vertical-only AppKit scroll view for the task list. Hosts fixed-size
/// SwiftUI content and registers with the shared coordinator so it mirrors the
/// timeline pane's vertical scrolling.
private struct ListScrollView<Content: View>: NSViewRepresentable {
    private let contentSize: CGSize
    private let coordinator: ScheduleScrollCoordinator
    private let content: Content

    init(contentSize: CGSize, coordinator: ScheduleScrollCoordinator, @ViewBuilder content: () -> Content) {
        self.contentSize = contentSize
        self.coordinator = coordinator
        self.content = content()
    }

    final class Box {
        var hosting: NSHostingView<AnyView>?
        var document: FlippedDocumentView?
    }

    func makeCoordinator() -> Box { Box() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let document = FlippedDocumentView()
        let hosting = NSHostingView(rootView: anchoredContent)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: document.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        document.setFrameSize(contentSize)
        scrollView.documentView = document

        context.coordinator.hosting = hosting
        context.coordinator.document = document
        coordinator.attachList(scrollView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let hosting = context.coordinator.hosting,
              let document = context.coordinator.document else { return }
        hosting.rootView = anchoredContent
        document.setFrameSize(contentSize)
        coordinator.attachList(nsView)
    }

    private var anchoredContent: AnyView {
        AnyView(
            content.frame(
                width: contentSize.width,
                height: contentSize.height,
                alignment: .topLeading
            )
        )
    }

    final class FlippedDocumentView: NSView {
        override var isFlipped: Bool { true }
    }
}

/// AppKit-backed scroll view with genuine two-axis native scrolling.
/// SwiftUI's ScrollView([.horizontal, .vertical]) fails to provide a working
/// horizontal scroller in this layout on macOS 26, so the timeline pane hosts
/// its SwiftUI content inside an NSScrollView instead.
private struct BothAxesScrollView<Content: View>: NSViewRepresentable {
    private let contentSize: CGSize
    private let onAttach: ((NSScrollView) -> Void)?
    private let content: Content

    init(contentSize: CGSize, onAttach: ((NSScrollView) -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.contentSize = contentSize
        self.onAttach = onAttach
        self.content = content()
    }

    final class Coordinator {
        var hosting: NSHostingView<AnyView>?
        var document: FlippedDocumentView?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let document = FlippedDocumentView()
        let hosting = NSHostingView(rootView: anchoredContent)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: document.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        document.setFrameSize(contentSize)
        scrollView.documentView = document

        context.coordinator.hosting = hosting
        context.coordinator.document = document
        onAttach?(scrollView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let hosting = context.coordinator.hosting,
              let document = context.coordinator.document else { return }
        hosting.rootView = anchoredContent
        document.setFrameSize(contentSize)
        onAttach?(nsView)
    }

    /// The hosting view centers its root view when its bounds exceed the
    /// content's fixed size (which happens transiently while auto-fit
    /// settles); anchoring top-leading keeps the chart pinned to the origin.
    private var anchoredContent: AnyView {
        AnyView(
            content.frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        )
    }

    /// Anchors the document at the top-left so scrolling starts at the top.
    final class FlippedDocumentView: NSView {
        override var isFlipped: Bool { true }
    }
}
