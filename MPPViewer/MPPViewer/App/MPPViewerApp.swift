import SwiftUI
import UniformTypeIdentifiers
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
    }
}

@main
struct MPPViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: PlanningDocument()) { file in
            ContentView(document: file.$document)
        }
        .commands {
            CommandGroup(after: .sidebar) {
                ForEach(Array(NavigationItem.allCases.enumerated()), id: \.element.id) { index, item in
                    if index < 9 {
                        Button(item.rawValue) {
                            NotificationCenter.default.post(
                                name: .navigateToItem,
                                object: item
                            )
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    }
                }
            }
            CommandGroup(after: .help) {
                Button("Open In-App Guide") {
                    NotificationCenter.default.post(
                        name: .navigateToItem,
                        object: NavigationItem.helpCenter
                    )
                }

                Button("Financial Terms Glossary") {
                    NotificationCenter.default.post(
                        name: .navigateToItem,
                        object: NavigationItem.helpCenter
                    )
                }
            }
        }
    }
}
