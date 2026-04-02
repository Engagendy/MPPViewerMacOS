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

    private var focusTasks: [ProjectTask] {
        project.rootTasks
    }

    private var centerTask: ProjectTask? {
        let id = centerTaskID ?? project.rootTasks.first?.uniqueID
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
                Divider()
                GeometryReader { geometry in
            if let centerTask {
                let graphData = buildGraph(center: centerTask, maxDepth: depth)
                let nodePositions = layoutPositions(for: graphData.nodes)

                        ZStack {
                            graphCanvas(graphData: graphData, positions: nodePositions, size: geometry.size)
                            nodesOverlay(graphData: graphData, positions: nodePositions, size: geometry.size)
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
                centerTaskID = project.rootTasks.first?.uniqueID
            }
            if selectedNodeID == nil {
                selectedNodeID = centerTaskID
            }
        }
        .onChange(of: centerTaskID) { _, newValue in
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
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func graphCanvas(graphData: GraphData, positions: [Int: CGPoint], size: CGSize) -> some View {
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
                    with: .color(edge.direction == .predecessor ? .gray.opacity(0.6) : .blue.opacity(0.6)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round)
                )
            }
        }
    }

    private func nodesOverlay(graphData: GraphData, positions: [Int: CGPoint], size: CGSize) -> some View {
        ForEach(graphData.nodes) { node in
            let pos = transform(positions[node.id] ?? .zero, size: size)
            nodeView(for: node)
                .position(pos)
                .onTapGesture {
                    selectedNodeID = node.id
                    navigateToTaskID = node.id
                }
        }
    }

    private func nodeView(for node: GraphNode) -> some View {
        let isCenter = node.id == centerTaskID
        let isSelected = node.id == selectedNodeID
        let baseColor = node.task.critical == true ? Color.red : (node.task.isDisplayMilestone ? .orange : .accentColor)

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
                .fill(isSelected ? baseColor.opacity(0.18) : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isCenter ? baseColor : (isSelected ? baseColor.opacity(0.8) : baseColor.opacity(0.4)), lineWidth: isSelected ? 1.5 : 0.8)
        )
        .frame(width: 180)
    }

    private func transform(_ point: CGPoint, size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(
            x: center.x + point.x * canvasScale + panOffset.width,
            y: center.y + point.y * canvasScale + panOffset.height
        )
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

    private func layoutPositions(for nodes: [GraphNode]) -> [Int: CGPoint] {
        let grouped = Dictionary(grouping: nodes.sorted { $0.level < $1.level }) { $0.level }
        var positions: [Int: CGPoint] = [:]
        let verticalSpacing: CGFloat = 90
        let horizontalSpacing: CGFloat = 200

        for (level, levelNodes) in grouped {
            let centerIndex = CGFloat(levelNodes.count - 1) / 2
            for (index, node) in levelNodes.enumerated() {
                let y = (CGFloat(index) - centerIndex) * verticalSpacing
                let x = CGFloat(level) * horizontalSpacing
                positions[node.id] = CGPoint(x: x, y: y)
            }
        }

        return positions
    }
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
