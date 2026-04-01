import SwiftUI

struct SidebarView: View {
    @Binding var selection: NavigationItem?

    var body: some View {
        List(selection: $selection) {
            Section("Overview") {
                sidebarRow(.dashboard)
                sidebarRow(.executive)
                sidebarRow(.summary)
            }

            Section("Planning") {
                sidebarRow(.tasks)
                sidebarRow(.milestones)
                sidebarRow(.gantt)
                sidebarRow(.schedule)
                sidebarRow(.timeline)
                sidebarRow(.resources)
                sidebarRow(.calendar)
            }

            Section("Analysis") {
                sidebarRow(.validation)
                sidebarRow(.diagnostics)
                sidebarRow(.resourceRisks)
                sidebarRow(.criticalPath)
                sidebarRow(.earnedValue)
                sidebarRow(.workload)
                sidebarRow(.diff)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
    }

    private func sidebarRow(_ item: NavigationItem) -> some View {
        Label(item.rawValue, systemImage: item.icon)
            .tag(item)
    }
}
