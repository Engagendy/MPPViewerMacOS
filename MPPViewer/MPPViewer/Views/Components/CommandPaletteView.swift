import SwiftUI

/// A lightweight ⌘K overlay for jumping to any view or task by keyboard,
/// in the spirit of Xcode's Open Quickly.
struct CommandPaletteView: View {
    let views: [NavigationItem]
    let tasks: [ProjectTask]
    let onSelectView: (NavigationItem) -> Void
    let onSelectTask: (Int) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    private enum Row: Identifiable {
        case view(NavigationItem)
        case task(ProjectTask)

        var id: String {
            switch self {
            case .view(let item): return "view-\(item.rawValue)"
            case .task(let task): return "task-\(task.uniqueID)"
            }
        }
    }

    private var results: [Row] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()

        let viewRows = views
            .filter { trimmed.isEmpty || $0.rawValue.lowercased().contains(trimmed) }
            .map { Row.view($0) }

        // Without a query, show views only so the palette opens instantly on
        // large plans; searching brings in matching tasks.
        guard !trimmed.isEmpty else { return viewRows }

        let taskRows = tasks
            .filter { matchesTask($0, query: trimmed) }
            .prefix(40)
            .map { Row.task($0) }

        return viewRows + Array(taskRows)
    }

    private func matchesTask(_ task: ProjectTask, query: String) -> Bool {
        if let name = task.name?.lowercased(), name.contains(query) { return true }
        if let wbs = task.wbs?.lowercased(), wbs.contains(query) { return true }
        if let id = task.id, String(id).contains(query) { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Jump to a view or task…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($searchFocused)
                        .onSubmit(activateHighlighted)
                    Text("esc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
                .padding(12)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, row in
                                rowView(row, isHighlighted: index == highlighted)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture { activate(row) }
                                    .onHover { if $0 { highlighted = index } }
                            }
                        }
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: highlighted) { _, new in
                        withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(new, anchor: .center) }
                    }
                }
            }
            .frame(width: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            .padding(.top, 90)
            // Handle navigation keys on the container so they don't interfere
            // with the search field's text editing.
            .onKeyPress(.downArrow) { move(1); return .handled }
            .onKeyPress(.upArrow) { move(-1); return .handled }
            .onKeyPress(.escape) { onDismiss(); return .handled }
        }
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onAppear {
            // Focusing in onAppear of a freshly-inserted overlay is unreliable;
            // defer to the next runloop (with a short retry) so the field
            // reliably becomes first responder and keystrokes filter the list.
            DispatchQueue.main.async {
                searchFocused = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !searchFocused { searchFocused = true }
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            switch row {
            case .view(let item):
                Image(systemName: item.icon)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                Text(item.rawValue)
                Spacer()
                Text("View")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .task(let task):
                Image(systemName: task.milestone == true ? "diamond.fill" : (task.summary == true ? "folder.fill" : "circle"))
                    .frame(width: 20)
                    .foregroundStyle(task.milestone == true ? .orange : (task.summary == true ? .blue : .secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.displayName).lineLimit(1)
                    if let wbs = task.wbs {
                        Text(wbs).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("Task")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHighlighted ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    private func move(_ delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        highlighted = (highlighted + delta + count) % count
    }

    private func activateHighlighted() {
        let rows = results
        guard rows.indices.contains(highlighted) else { return }
        activate(rows[highlighted])
    }

    private func activate(_ row: Row) {
        switch row {
        case .view(let item): onSelectView(item)
        case .task(let task): onSelectTask(task.uniqueID)
        }
        onDismiss()
    }
}
