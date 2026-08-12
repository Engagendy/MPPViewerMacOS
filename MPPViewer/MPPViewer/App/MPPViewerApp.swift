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

    /// Debounce stamp so rapid activations don't thrash the notification center.
    private var lastReminderScheduling = Date.distantPast
    /// Classic status item (SwiftUI's MenuBarExtra scene loops when combined
    /// with DocumentGroup on current macOS, so the menu bar presence is
    /// AppKit-managed instead).
    private var statusItem: NSStatusItem?
    private var reminderPopover: NSPopover?
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        installMenuActions()
        scheduleRemindersSoon()
        syncStatusItem()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncStatusItem()
        }
    }

    /// Creates or removes the menu bar item to match the Settings toggle.
    private func syncStatusItem() {
        let enabled = UserDefaults.standard.object(forKey: ReminderSettings.menuBarEnabled) as? Bool ?? true
        if enabled, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(
                systemSymbolName: "calendar.badge.clock",
                accessibilityDescription: "Planroom reminders"
            )
            item.button?.target = self
            item.button?.action = #selector(toggleReminderPopover(_:))
            statusItem = item
        } else if !enabled, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            reminderPopover?.close()
            reminderPopover = nil
        }
    }

    /// Control-Center-style panel anchored to the status item — native popover
    /// chrome instead of a menu with an embedded view.
    @objc private func toggleReminderPopover(_ sender: Any?) {
        if let popover = reminderPopover, popover.isShown {
            popover.close()
            return
        }
        guard let button = statusItem?.button, let container = ReminderScheduler.container else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(onAction: { [weak popover] in popover?.close() })
                .modelContainer(container)
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        reminderPopover = popover
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        installMenuActions()
        scheduleRemindersSoon()
    }

    /// Rebuilds pending reminder notifications from current plan data.
    private func scheduleRemindersSoon() {
        guard Date().timeIntervalSince(lastReminderScheduling) > 60 else { return }
        lastReminderScheduling = Date()
        Task { @MainActor in
            ReminderScheduler.requestAuthorizationIfNeeded()
            ReminderScheduler.reschedule()
        }
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
    private let modelContainer: ModelContainer

    init() {
        let container = PortfolioModelContainer.make()
        modelContainer = container
        ReminderScheduler.container = container
    }

    var body: some Scene {
        DocumentGroup(newDocument: PlanningDocument()) { file in
            ContentView(document: file.$document)
                .saveFailureAlerts()
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Planroom") {
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

        Settings {
            PlanroomSettingsView()
        }
    }
}
