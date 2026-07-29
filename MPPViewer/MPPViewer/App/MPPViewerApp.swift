import SwiftUI
import UniformTypeIdentifiers
import AppKit
import SwiftData
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        installMenuActions()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        installMenuActions()
    }

    @objc func closeFrontWindow(_ sender: Any?) {
        let targetWindow = NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.orderedWindows.first(where: { $0.isVisible && $0.canBecomeKey })
        targetWindow?.close()
    }

    @objc func quitApplication(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    private func installMenuActions() {
        if let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu,
           let closeItem = fileMenu.item(withTitle: "Close") {
            closeItem.target = self
            closeItem.action = #selector(closeFrontWindow(_:))
            closeItem.isEnabled = true
        }

        if let appMenu = NSApp.mainMenu?.items.first?.submenu,
           let quitItem = appMenu.items.first(where: { $0.title.hasPrefix("Quit") }) {
            quitItem.target = self
            quitItem.action = #selector(quitApplication(_:))
            quitItem.isEnabled = true
        }
    }
}

@main
struct MPPViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let modelContainer: ModelContainer = PortfolioModelContainer.make()

    var body: some Scene {
        DocumentGroup(newDocument: PlanningDocument()) { file in
            ContentView(document: file.$document)
                .saveFailureAlerts()
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit MPP Viewer") {
                    AppDelegate.shared?.quitApplication(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
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
