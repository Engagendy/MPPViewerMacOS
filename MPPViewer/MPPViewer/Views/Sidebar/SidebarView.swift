import SwiftUI

struct SidebarView: View {
    @Binding var selection: NavigationItem?

    var body: some View {
        List(NavigationItem.allCases, selection: $selection) { item in
            Label(item.rawValue, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
    }
}
