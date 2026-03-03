import SwiftUI
import UniformTypeIdentifiers

@main
struct MPPViewerApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MPPDocument.self) { file in
            ContentView(document: file.document)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
