import SwiftUI

/// Read-only audit trail of saved plan changes, newest first. Entries are
/// recorded by `PlanHistoryBuilder` each time the .mppplan file is saved with
/// content changes, and are bounded to the most recent
/// `PlanHistoryBuilder.maxEntries` saves.
struct PlanHistoryView: View {
    let history: [PlanHistoryEntry]

    @State private var expandedEntryIDs: Set<UUID> = []

    private var sortedHistory: [PlanHistoryEntry] {
        history.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Version History")
                    .font(.headline)
                if !history.isEmpty {
                    Text("\(history.count) saved \(history.count == 1 ? "change" : "changes")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if history.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("A change log entry is recorded each time this plan is saved with changes. Save the plan, then reopen it to review its history here.")
                )
            } else {
                List {
                    ForEach(sortedHistory) { entry in
                        entryRow(entry)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: PlanHistoryEntry) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedEntryIDs.contains(entry.id) },
                set: { isExpanded in
                    if isExpanded {
                        expandedEntryIDs.insert(entry.id)
                    } else {
                        expandedEntryIDs.remove(entry.id)
                    }
                }
            )
        ) {
            ForEach(entry.changes) { change in
                changeRow(change)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.body.weight(.medium))
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func changeRow(_ change: PlanHistoryItemChange) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(change.changeKind.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor(for: change.changeKind).opacity(0.15))
                    .foregroundStyle(badgeColor(for: change.changeKind))
                    .clipShape(Capsule())
                Text(change.entity.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(change.name)
                    .font(.callout)
                    .lineLimit(1)
            }
            if !change.fieldChanges.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(change.fieldChanges) { fieldChange in
                        HStack(spacing: 4) {
                            Text(fieldChange.field)
                                .font(.caption.weight(.medium))
                                .frame(minWidth: 80, alignment: .leading)
                            Text(fieldChange.oldValue.isEmpty ? "—" : fieldChange.oldValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .strikethrough(!fieldChange.oldValue.isEmpty)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(fieldChange.newValue.isEmpty ? "—" : fieldChange.newValue)
                                .font(.caption)
                        }
                    }
                }
                .padding(.leading, 12)
            }
        }
        .padding(.vertical, 2)
    }

    private func badgeColor(for kind: PlanHistoryChangeKind) -> Color {
        switch kind {
        case .added: return .green
        case .removed: return .red
        case .modified: return .orange
        }
    }
}
