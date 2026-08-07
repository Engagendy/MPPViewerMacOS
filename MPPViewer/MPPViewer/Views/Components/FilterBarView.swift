import SwiftUI

struct FilterBarView: View {
    @Binding var criteria: TaskFilterCriteria
    @Binding var grouping: TaskGrouping
    let resources: [ProjectResource]
    var onClear: (() -> Void)? = nil
    @State private var showMore = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                TextField("Search task, WBS, ID, resource, review notes, custom fields", text: $criteria.textSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 240, maxWidth: 320)

                // Status picker
                Picker("Status", selection: $criteria.status) {
                    ForEach(TaskStatus.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .frame(width: 150)

                // Resource picker
                Picker("Resource", selection: Binding(
                    get: { criteria.resourceID ?? -1 },
                    set: { criteria.resourceID = $0 == -1 ? nil : $0 }
                )) {
                    Text("All Resources").tag(-1)
                    ForEach(resources.filter { $0.type?.lowercased() == "work" || $0.type == nil }, id: \.uniqueID) { resource in
                        Text(resource.name ?? "Resource \(resource.uniqueID ?? 0)")
                            .tag(resource.uniqueID ?? 0)
                    }
                }
                .frame(width: 160)

                // Toggles
                Toggle("Critical", isOn: $criteria.criticalOnly)
                    .toggleStyle(.button)
                    .hoverHighlight()
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(criteria.criticalOnly ? .red : nil)
                    .help("Show only tasks on the critical path")
                    .accessibilityHint("Filters the list to critical-path tasks only")

                Toggle("Milestones", isOn: $criteria.milestoneOnly)
                    .toggleStyle(.button)
                    .hoverHighlight()
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(criteria.milestoneOnly ? .orange : nil)
                    .help("Show only milestones")
                    .accessibilityHint("Filters the list to milestones only")

                Toggle("Flagged", isOn: $criteria.flaggedOnly)
                    .toggleStyle(.button)
                    .hoverHighlight()
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(criteria.flaggedOnly ? .orange : nil)
                    .help("Show only tasks you've flagged for follow-up")
                    .accessibilityHint("Filters the list to flagged tasks only")

                Toggle("Baseline Slip", isOn: $criteria.baselineSlippedOnly)
                    .toggleStyle(.button)
                    .hoverHighlight()
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(criteria.baselineSlippedOnly ? .red : nil)
                    .help("Show only tasks that finish later than their baseline")
                    .accessibilityHint("Filters the list to tasks that slipped past baseline")

                Toggle("Linked", isOn: $criteria.hasDependenciesOnly)
                    .toggleStyle(.button)
                    .hoverHighlight()
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(criteria.hasDependenciesOnly ? .blue : nil)
                    .help("Show only tasks that have predecessors or successors")
                    .accessibilityHint("Filters the list to tasks with dependencies")

                Divider().frame(height: 16)

                // Group by
                Picker("Group", selection: $grouping) {
                    ForEach(TaskGrouping.allCases) { g in
                        Text(g.rawValue).tag(g)
                    }
                }
                .frame(width: 150)

                Spacer()

                // More / Date Range toggle
                Button {
                    showMore.toggle()
                } label: {
                    Label("More", systemImage: showMore ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.accessoryBar)

                if criteria.isActive {
                    Button("Clear") {
                        criteria.clear()
                        grouping = .none
                        onClear?()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }
            .font(.caption)

            if showMore {
                HStack(spacing: 12) {
                    // A nil bound means the date filter is inactive; seed the
                    // pickers with today so they never render the sentinel
                    // years of Date.distantPast/.distantFuture (1 and 4001).
                    let today = Calendar.current.startOfDay(for: Date())
                    CalendarDatePicker(
                        title: "From",
                        date: Binding(
                            get: { criteria.dateRangeStart ?? today },
                            set: { criteria.dateRangeStart = $0 }
                        ),
                        isCompact: true
                    )
                    .opacity(criteria.dateRangeStart == nil ? 0.55 : 1)

                    CalendarDatePicker(
                        title: "To",
                        date: Binding(
                            get: { criteria.dateRangeEnd ?? criteria.dateRangeStart ?? today },
                            set: { criteria.dateRangeEnd = $0 }
                        ),
                        isCompact: true
                    )
                    .opacity(criteria.dateRangeEnd == nil ? 0.55 : 1)

                    if criteria.dateRangeStart != nil || criteria.dateRangeEnd != nil {
                        Button("Clear Dates") {
                            criteria.dateRangeStart = nil
                            criteria.dateRangeEnd = nil
                        }
                        .buttonStyle(.accessoryBar)
                        .font(.caption)
                    }

                    Divider().frame(height: 16)

                    Toggle("Annotated", isOn: $criteria.annotatedOnly)
                        .toggleStyle(.button)
                        .hoverHighlight()
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(criteria.annotatedOnly ? .blue : nil)
                        .help("Show only tasks that have review notes")
                        .accessibilityHint("Filters the list to tasks with review annotations")

                    Toggle("Open Issues", isOn: $criteria.unresolvedOnly)
                        .toggleStyle(.button)
                        .hoverHighlight()
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(criteria.unresolvedOnly ? .orange : nil)
                        .help("Show only tasks with unresolved review issues")
                        .accessibilityHint("Filters the list to tasks with open issues")

                    Toggle("Follow-Up", isOn: $criteria.followUpOnly)
                        .toggleStyle(.button)
                        .hoverHighlight()
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(criteria.followUpOnly ? .red : nil)
                        .help("Show only tasks marked for follow-up")
                        .accessibilityHint("Filters the list to follow-up tasks")

                    Spacer()
                }
                .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
