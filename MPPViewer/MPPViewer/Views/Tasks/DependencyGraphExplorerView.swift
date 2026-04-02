import SwiftUI

struct DependencyGraphExplorerView: View {
    let project: ProjectModel
    @Binding var navigateToTaskID: Int?
    @Binding var selectedNav: NavigationItem?

    @State private var centerTaskID: Int?
    @State private var selectedNodeID: Int?
    @State private var depth: Int = 2
    @State private var canvasScale: CGFloat = 1
    @State private var lastCanvasScale: CGFloat = 1
    @State private var panOffset = CGSize.zero
    @State private var lastPanOffset = CGSize.zero
    @State private var highlightMode = true
    @State private var breadcrumbs: [Breadcrumb] = []
    private var linkedTasks: [ProjectTask] {
        project.tasks
            .filter {
                $0.summary != true &&
                (($0.predecessors?.isEmpty == false) || ($0.successors?.isEmpty == false))
            }
            .sorted {
                ($0.startDate ?? Date.distantPast, $0.displayName) < ($1.startDate ?? Date.distantPast, $1.displayName)
            }
    }

    private var focusTasks: [ProjectTask] {
        let candidates = linkedTasks
        guard !candidates.isEmpty else {
            return project.tasks
                .filter { $0.summary != true }
                .sorted {
                    ($0.startDate ?? Date.distantPast, $0.displayName) < ($1.startDate ?? Date.distantPast, $1.displayName)
                }
        }
        return candidates
    }

    private var centerTask: ProjectTask? {
        let id = centerTaskID ?? focusTasks.first?.uniqueID ?? project.rootTasks.first?.uniqueID
        return id.flatMap { project.tasksByID[$0] }
    }

    private var inspectorTask: ProjectTask? {
        if let selected = selectedNodeID.flatMap({ project.tasksByID[$0] }) {
            return selected
        }
        return centerTask
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                breadcrumbBar
                Divider()
                GeometryReader { geometry in
                    if let centerTask {
                        let graphData = buildGraph(center: centerTask, maxDepth: depth)
                        let layout = layoutData(for: graphData.nodes, availableSize: geometry.size)
                        let connectedIDs = connectedTaskIDs(in: graphData)

                        ZStack {
                            graphCanvas(graphData: graphData, positions: layout.positions, size: geometry.size, selectedNode: selectedNodeID)
                            nodesOverlay(graphData: graphData, positions: layout.positions, size: geometry.size, connectedIDs: connectedIDs)
                            graphScrollIndicators(size: geometry.size, bounds: layout.bounds)
                                .allowsHitTesting(false)
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    panOffset = CGSize(
                                        width: lastPanOffset.width + value.translation.width,
                                        height: lastPanOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in lastPanOffset = panOffset }
                        )
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let clamped = min(2.5, max(0.6, lastCanvasScale * value))
                                    canvasScale = clamped
                                }
                                .onEnded { _ in lastCanvasScale = canvasScale }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.easeInOut) {
                                canvasScale = 1
                                lastCanvasScale = 1
                                panOffset = .zero
                                lastPanOffset = .zero
                            }
                        }
                    } else {
                        VStack {
                            Spacer()
                            Text("Select a focus task to explore dependencies.")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity)

            Divider()

            if let inspectorTask {
                TaskDetailView(
                    task: inspectorTask,
                    allTasks: project.tasksByID,
                    resources: project.resources,
                    assignments: project.assignments,
                    breadcrumbTaskIDs: [],
                    onSelectTask: { id in
                        selectedNodeID = id
                        navigateToTaskID = id
                    }
                )
                .frame(maxWidth: 420)
            } else {
                Text("No task selected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420, maxHeight: .infinity)
            }
        }
        .onAppear {
            if centerTaskID == nil {
                centerTaskID = focusTasks.first?.uniqueID ?? project.rootTasks.first?.uniqueID
            }
            if selectedNodeID == nil {
                selectedNodeID = centerTaskID
            }
        }
        .onChange(of: centerTaskID) { _, newValue in
            if let id = newValue, let task = project.tasksByID[id] {
                pushBreadcrumb(for: task)
            }
            if selectedNodeID == nil {
                selectedNodeID = newValue
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Dependency Explorer")
                .font(.headline)
            Spacer()
            Menu {
                ForEach(focusTasks) { task in
                    Button {
                        centerTaskID = task.uniqueID
                        selectedNodeID = task.uniqueID
                    } label: {
                        Text(task.displayName)
                    }
                }
            } label: {
                Label(centerTask?.displayName ?? "Select focus task", systemImage: "target")
                    .font(.caption)
            }
            Divider().frame(height: 24)
            Stepper("Depth: \(depth)", value: $depth, in: 1...4)
                .font(.caption)
            Button {
                if let selected = selectedNodeID {
                    centerTaskID = selected
                }
            } label: {
                Image(systemName: "scope")
            }
            .buttonStyle(.borderless)
            Divider().frame(height: 24)
            Text("Zoom")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $canvasScale, in: 0.6...2.5, onEditingChanged: { editing in
                if !editing {
                    lastCanvasScale = canvasScale
                }
            })
                .frame(width: 120)
            Button {
                resetView()
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .buttonStyle(.borderless)
            Button {
                highlightMode.toggle()
            } label: {
                Image(systemName: "wand.and.stars")
            .foregroundStyle(highlightMode ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if breadcrumbs.isEmpty {
                    Text("Focus any linked task to build a breadcrumb trail.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(breadcrumbs) { crumb in
                        Button {
                            centerTaskID = crumb.id
                            selectedNodeID = crumb.id
                        } label: {
                            Text(crumb.title)
                                .font(.caption2)
                                .lineLimit(1)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 12)
                                .background(
                                    Capsule()
                                        .fill(crumb.id == centerTaskID ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
                                )
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 34)
    }

    private func pushBreadcrumb(for task: ProjectTask) {
        let crumb = Breadcrumb(id: task.uniqueID, title: task.displayName)
        var updated = breadcrumbs.filter { $0.id != crumb.id }
        updated.insert(crumb, at: 0)
        breadcrumbs = Array(updated.prefix(8))
    }

    private func graphCanvas(graphData: GraphData, positions: [Int: CGPoint], size: CGSize, selectedNode: Int?) -> some View {
        Canvas { context, _ in
            for edge in graphData.edges {
                guard let from = positions[edge.fromID], let to = positions[edge.toID] else { continue }
                let transformedFrom = transform(from, size: size)
                let transformedTo = transform(to, size: size)

                var path = Path()
                path.move(to: transformedFrom)
                path.addLine(to: transformedTo)
                context.stroke(
                    path,
                    with: .color(edgeColor(edge, selected: selectedNode)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round)
                )
            }
        }
    }

    private func nodesOverlay(graphData: GraphData, positions: [Int: CGPoint], size: CGSize, connectedIDs: Set<Int>) -> some View {
        ForEach(graphData.nodes) { node in
            let pos = transform(positions[node.id] ?? .zero, size: size)
            nodeView(for: node, connected: connectedIDs.contains(node.id))
                .position(pos)
                .onTapGesture {
                    selectedNodeID = node.id
                    navigateToTaskID = node.id
                    centerTaskID = node.id
                }
        }
    }

    private func nodeView(for node: GraphNode, connected: Bool) -> some View {
        let isCenter = node.id == centerTaskID
        let isSelected = node.id == selectedNodeID
        let baseColor = node.task.critical == true ? Color.red : (node.task.isDisplayMilestone ? .orange : Color.accentColor)
        let spotlight = highlightMode ? (isSelected || connected || isCenter) : true
        let fillColor = highlightMode
            ? (spotlight ? baseColor.opacity(0.28) : Color(nsColor: .windowBackgroundColor).opacity(0.45))
            : (isSelected ? baseColor.opacity(0.18) : Color(nsColor: .windowBackgroundColor))
        let strokeColor = highlightMode
            ? (spotlight ? baseColor : Color.secondary.opacity(0.3))
            : (isCenter ? baseColor : (isSelected ? baseColor.opacity(0.8) : baseColor.opacity(0.4)))

        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(node.task.displayName)
                    .font(.caption)
                    .lineLimit(2)
                Spacer()
            }
            HStack {
                Text(node.task.id.map(String.init) ?? "\(node.task.uniqueID)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Hop \(abs(node.level))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(strokeColor, lineWidth: isSelected ? 1.5 : 0.8)
        )
        .frame(width: 180)
        .shadow(color: spotlight ? baseColor.opacity(0.25) : .clear, radius: 6, x: 0, y: 4)
    }

    private func transform(_ point: CGPoint, size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(
            x: center.x + point.x * canvasScale + panOffset.width,
            y: center.y + point.y * canvasScale + panOffset.height
        )
    }

    private func edgeColor(_ edge: GraphEdge, selected: Int?) -> Color {
        let inactive = edge.direction == .predecessor ? Color.gray.opacity(0.25) : Color.blue.opacity(0.25)
        let active = edge.direction == .predecessor ? Color.gray.opacity(0.95) : Color.blue.opacity(0.95)
        guard highlightMode, let selected = selected else {
            return edge.direction == .predecessor ? Color.gray.opacity(0.6) : Color.blue.opacity(0.6)
        }
        return (edge.fromID == selected || edge.toID == selected) ? active : inactive
    }

    private func buildGraph(center: ProjectTask, maxDepth: Int) -> GraphData {
        var nodes: [Int: GraphNode] = [:]
        var queue: [(task: ProjectTask, level: Int)] = [(center, 0)]
        var edges: [GraphEdge] = []
        nodes[center.uniqueID] = GraphNode(id: center.uniqueID, task: center, level: 0)
        var visited: Set<Int> = [center.uniqueID]

        while let current = queue.first {
            queue.removeFirst()
            guard abs(current.level) < maxDepth else { continue }

            let predecessorRelations = current.task.predecessors ?? []
            let successorRelations = current.task.successors ?? []

            for relation in predecessorRelations {
                guard let target = project.tasksByID[relation.targetTaskUniqueID] else { continue }
                let neighborLevel = current.level - 1
                nodes[target.uniqueID] = GraphNode(id: target.uniqueID, task: target, level: neighborLevel)
                edges.append(GraphEdge(id: "pred-\(current.task.uniqueID)-\(target.uniqueID)", fromID: target.uniqueID, toID: current.task.uniqueID, direction: .predecessor))
                if !visited.contains(target.uniqueID) {
                    visited.insert(target.uniqueID)
                    queue.append((target, neighborLevel))
                }
            }

            for relation in successorRelations {
                guard let target = project.tasksByID[relation.targetTaskUniqueID] else { continue }
                let neighborLevel = current.level + 1
                nodes[target.uniqueID] = GraphNode(id: target.uniqueID, task: target, level: neighborLevel)
                edges.append(GraphEdge(id: "succ-\(current.task.uniqueID)-\(target.uniqueID)", fromID: current.task.uniqueID, toID: target.uniqueID, direction: .successor))
                if !visited.contains(target.uniqueID) {
                    visited.insert(target.uniqueID)
                    queue.append((target, neighborLevel))
                }
            }
        }

        return GraphData(nodes: Array(nodes.values), edges: edges)
    }

    private func layoutData(for nodes: [GraphNode], availableSize: CGSize) -> (positions: [Int: CGPoint], bounds: CGRect) {
        guard !nodes.isEmpty else { return ([:], .zero) }

        let grouped = Dictionary(grouping: nodes) { $0.level }
        let sortedLevels = grouped.keys.sorted()
        let horizontalSpacing: CGFloat = 170
        let verticalSpacing: CGFloat = 120
        let nodeWidth: CGFloat = 180
        let nodeHeight: CGFloat = 90

        var positions: [Int: CGPoint] = [:]
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for level in sortedLevels {
            let levelNodes = grouped[level] ?? []
            let centerIndex = CGFloat(levelNodes.count - 1) / 2
            for (index, node) in levelNodes.enumerated() {
                let x = (CGFloat(index) - centerIndex) * horizontalSpacing
                let y = CGFloat(level) * verticalSpacing
                positions[node.id] = CGPoint(x: x, y: y)

                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }

        minX -= nodeWidth / 2
        maxX += nodeWidth / 2
        minY -= nodeHeight / 2
        maxY += nodeHeight / 2

        let bounds = CGRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX),
            height: max(1, maxY - minY)
        )

        return (positions, bounds)
    }

    private func connectedTaskIDs(in graphData: GraphData) -> Set<Int> {
        guard let selected = selectedNodeID else { return [] }
        return Set(
            graphData.edges
                .filter { $0.fromID == selected || $0.toID == selected }
                .flatMap { [$0.fromID, $0.toID] }
        )
    }

    private func graphScrollIndicators(size: CGSize, bounds: CGRect) -> some View {
        let contentWidth = max(bounds.width * canvasScale, size.width)
        let contentHeight = max(bounds.height * canvasScale, size.height)
        let horizontalRatio = size.width / max(contentWidth, 1)
        let verticalRatio = size.height / max(contentHeight, 1)
        let horizontalWidth = size.width * horizontalRatio
        let verticalHeight = size.height * verticalRatio

        let horizontalTrackWidth = max(size.width - horizontalWidth, 1)
        let verticalTrackHeight = max(size.height - verticalHeight, 1)
        let normalizedX = clamp(panOffset.width / max(contentWidth - size.width, 1), min: -1, maxValue: 1)
        let normalizedY = clamp(panOffset.height / max(contentHeight - size.height, 1), min: -1, maxValue: 1)
        let offsetX = normalizedX * horizontalTrackWidth / 2
        let offsetY = normalizedY * verticalTrackHeight / 2

        return ZStack {
            VStack {
                Spacer()
                HStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: horizontalWidth, height: 4)
                        .offset(x: offsetX)
                        .padding(.trailing, 4)
                    Spacer()
                }
            }
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 4, height: verticalHeight)
                        .offset(y: offsetY)
                        .padding(.bottom, 4)
                }
            }
        }
    }

    private func clamp(_ value: CGFloat, min: CGFloat, maxValue: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(value, maxValue))
    }

    private func resetView() {
        withAnimation(.easeInOut) {
            canvasScale = 1
            lastCanvasScale = 1
            panOffset = .zero
            lastPanOffset = .zero
        }
    }

}

private struct Breadcrumb: Identifiable {
    let id: Int
    let title: String
}

private struct GraphNode: Identifiable {
    let id: Int
    let task: ProjectTask
    let level: Int
}

private struct GraphEdge: Identifiable {
    let id: String
    let fromID: Int
    let toID: Int
    let direction: DependencyDirection
}

private struct GraphData {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
}

private enum DependencyDirection {
    case predecessor
    case successor
}
