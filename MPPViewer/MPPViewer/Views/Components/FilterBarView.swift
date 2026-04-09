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
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(criteria.criticalOnly ? .red : nil)

                Toggle("Milestones", isOn: $criteria.milestoneOnly)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(criteria.milestoneOnly ? .orange : nil)

                Toggle("Flagged", isOn: $criteria.flaggedOnly)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(criteria.flaggedOnly ? .orange : nil)

                Toggle("Baseline Slip", isOn: $criteria.baselineSlippedOnly)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(criteria.baselineSlippedOnly ? .red : nil)

                Toggle("Linked", isOn: $criteria.hasDependenciesOnly)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(criteria.hasDependenciesOnly ? .blue : nil)

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
                .buttonStyle(.borderless)

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
                    DatePicker(
                        "From",
                        selection: Binding(
                            get: { criteria.dateRangeStart ?? Date.distantPast },
                            set: { criteria.dateRangeStart = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .frame(width: 200)

                    DatePicker(
                        "To",
                        selection: Binding(
                            get: { criteria.dateRangeEnd ?? Date.distantFuture },
                            set: { criteria.dateRangeEnd = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .frame(width: 200)

                    if criteria.dateRangeStart != nil || criteria.dateRangeEnd != nil {
                        Button("Clear Dates") {
                            criteria.dateRangeStart = nil
                            criteria.dateRangeEnd = nil
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }

                    Divider().frame(height: 16)

                    Toggle("Annotated", isOn: $criteria.annotatedOnly)
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(criteria.annotatedOnly ? .blue : nil)

                    Toggle("Open Issues", isOn: $criteria.unresolvedOnly)
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(criteria.unresolvedOnly ? .orange : nil)

                    Toggle("Follow-Up", isOn: $criteria.followUpOnly)
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(criteria.followUpOnly ? .red : nil)

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
