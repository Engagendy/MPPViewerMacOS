import SwiftUI
import SwiftData
import AppKit
import UserNotifications
import ServiceManagement

extension Notification.Name {
    /// Posted by the menu bar panel; handled inside the SwiftUI scene, where
    /// the openSettings environment action actually works.
    static let openPlanroomSettings = Notification.Name("openPlanroomSettings")
}

/// AppStorage keys for the menu bar + reminder features.
enum ReminderSettings {
    static let menuBarEnabled = "reminders.menuBarEnabled"
    static let digestEnabled = "reminders.digestEnabled"
    static let digestHour = "reminders.digestHour"
    static let milestoneAlertsEnabled = "reminders.milestoneAlertsEnabled"
    static let milestoneLeadDays = "reminders.milestoneLeadDays"
    static let digestIncludeCostHighlights = "reminders.digestIncludeCostHighlights"
}

// MARK: - Reminder model rows

struct ReminderTaskRow: Identifiable {
    let id: Int
    let name: String
    let finishDate: Date
    let isMilestone: Bool
}

/// Snapshot of the most recently updated, non-archived plan's attention items.
struct ReminderDigest {
    var planTitle: String = ""
    var overdue: [ReminderTaskRow] = []
    var dueSoon: [ReminderTaskRow] = []
    var milestones: [ReminderTaskRow] = []

    var isEmpty: Bool { overdue.isEmpty && dueSoon.isEmpty && milestones.isEmpty }

    /// The most recently updated, non-archived plan (the digest source).
    @MainActor
    static func mostRecentActivePlan(in context: ModelContext) -> PortfolioProjectPlan? {
        var descriptor = FetchDescriptor<PortfolioProjectPlan>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 8
        guard let plans = try? context.fetch(descriptor) else { return nil }
        return plans.first(where: { !$0.isArchivedValue })
    }

    /// Builds the digest from the most recently updated active plan.
    @MainActor
    static func fromMostRecentPlan(in context: ModelContext) -> ReminderDigest? {
        guard let plan = mostRecentActivePlan(in: context) else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let soonCutoff = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let milestoneCutoff = calendar.date(byAdding: .day, value: 60, to: today) ?? today

        let tasks = plan.nativeTasksForUI
        // Positional hierarchy: a task followed by a deeper row is a summary.
        var summaryIDs: Set<Int> = []
        for (index, task) in tasks.enumerated()
        where index + 1 < tasks.count && tasks[index + 1].outlineLevel > task.outlineLevel {
            summaryIDs.insert(task.id)
        }

        var digest = ReminderDigest(planTitle: plan.title.isEmpty ? "Plan" : plan.title)
        for task in tasks where !summaryIDs.contains(task.id) && task.percentComplete < 100 {
            let finish = calendar.startOfDay(for: task.normalizedFinishDate)
            let row = ReminderTaskRow(id: task.id, name: task.name, finishDate: finish, isMilestone: task.isMilestone)
            if finish < today {
                digest.overdue.append(row)
            } else if task.isMilestone, finish <= milestoneCutoff {
                digest.milestones.append(row)
            } else if finish <= soonCutoff {
                digest.dueSoon.append(row)
            }
        }
        digest.overdue.sort { $0.finishDate < $1.finishDate }
        digest.dueSoon.sort { $0.finishDate < $1.finishDate }
        digest.milestones.sort { $0.finishDate < $1.finishDate }
        return digest
    }
}

// MARK: - Digest sharing

extension ReminderDigest {
    /// Cost/EVM highlights for the digest body, computed on demand from the
    /// digest's source plan (scheduling runs synchronously, so only call this
    /// from an explicit user action such as Share/Copy).
    @MainActor
    static func costHighlights(in context: ModelContext) -> EVMMetrics? {
        guard let plan = mostRecentActivePlan(in: context) else { return nil }
        let project = plan.asNativePlan().asProjectModel()
        let workTasks = project.tasks.filter { $0.summary != true }
        let metrics = EVMCalculator.projectMetrics(tasks: workTasks, statusDate: plan.statusDate)
        guard metrics.bac > 0 || metrics.ac > 0 else { return nil }
        return metrics
    }

    /// Plain-text rendering of the digest, suitable for Messages/Mail bodies
    /// and the pasteboard.
    func sharePlainText(costHighlights: EVMMetrics? = nil) -> String {
        var lines: [String] = []
        lines.append("\(planTitle) — Digest for \(DateFormatting.shortDate(Date()))")
        if isEmpty {
            lines.append("")
            lines.append("All clear — nothing needs attention.")
        }
        for (title, rows) in [("Overdue", overdue), ("Due this week", dueSoon), ("Upcoming milestones", milestones)] where !rows.isEmpty {
            lines.append("")
            lines.append("\(title) (\(rows.count)):")
            for row in rows {
                lines.append("  • \(row.name) — \(DateFormatting.shortDate(row.finishDate))")
            }
        }
        if let evm = costHighlights {
            lines.append("")
            lines.append("Cost highlights:")
            lines.append("  Budget (BAC): \(CurrencyFormatting.string(from: evm.bac))")
            lines.append("  Earned value: \(CurrencyFormatting.string(from: evm.ev))")
            lines.append("  Actual cost: \(CurrencyFormatting.string(from: evm.ac))")
            lines.append("  CPI \(String(format: "%.2f", evm.cpi)) · SPI \(String(format: "%.2f", evm.spi)) · EAC \(CurrencyFormatting.string(from: evm.eac))")
        }
        lines.append("")
        lines.append("Sent from Planroom")
        return lines.joined(separator: "\n")
    }

    /// HTML rendering of the digest, used for the pasteboard's rich flavor.
    func shareHTML(costHighlights: EVMMetrics? = nil) -> String {
        func escape(_ string: String) -> String {
            string
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }

        var html = "<html><body style=\"font-family: -apple-system, Helvetica, sans-serif;\">"
        html += "<h2>\(escape(planTitle)) — Digest for \(escape(DateFormatting.shortDate(Date())))</h2>"
        if isEmpty {
            html += "<p>All clear — nothing needs attention.</p>"
        }
        for (title, rows, color) in [
            ("Overdue", overdue, "#c0392b"),
            ("Due this week", dueSoon, "#d35400"),
            ("Upcoming milestones", milestones, "#8e44ad")
        ] where !rows.isEmpty {
            html += "<h3 style=\"color: \(color);\">\(title) (\(rows.count))</h3><ul>"
            for row in rows {
                html += "<li>\(escape(row.name)) — <b>\(escape(DateFormatting.shortDate(row.finishDate)))</b></li>"
            }
            html += "</ul>"
        }
        if let evm = costHighlights {
            html += "<h3>Cost highlights</h3><ul>"
            html += "<li>Budget (BAC): \(escape(CurrencyFormatting.string(from: evm.bac)))</li>"
            html += "<li>Earned value: \(escape(CurrencyFormatting.string(from: evm.ev)))</li>"
            html += "<li>Actual cost: \(escape(CurrencyFormatting.string(from: evm.ac)))</li>"
            html += "<li>CPI \(String(format: "%.2f", evm.cpi)) · SPI \(String(format: "%.2f", evm.spi)) · EAC \(escape(CurrencyFormatting.string(from: evm.eac)))</li>"
            html += "</ul>"
        }
        html += "<p style=\"color: #888;\">Sent from Planroom</p></body></html>"
        return html
    }
}

// MARK: - Notification scheduling

enum ReminderScheduler {
    /// Shared container handle, set once at app start so scheduling can run
    /// from app lifecycle callbacks.
    static var container: ModelContainer?

    private static let digestIdentifier = "planroom.daily.digest"
    private static let prefix = "planroom.reminder."

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    /// Rebuilds all pending Planroom notifications from current plan data.
    @MainActor
    static func reschedule() {
        guard let container else { return }
        let defaults = UserDefaults.standard
        let digestEnabled = defaults.object(forKey: ReminderSettings.digestEnabled) as? Bool ?? true
        let milestonesEnabled = defaults.object(forKey: ReminderSettings.milestoneAlertsEnabled) as? Bool ?? true
        let digestHour = defaults.object(forKey: ReminderSettings.digestHour) as? Int ?? 9
        let leadDays = defaults.object(forKey: ReminderSettings.milestoneLeadDays) as? Int ?? 3

        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [digestIdentifier])
        center.getPendingNotificationRequests { pending in
            let planroomIDs = pending.map(\.identifier).filter { $0.hasPrefix(prefix) || $0 == digestIdentifier }
            center.removePendingNotificationRequests(withIdentifiers: planroomIDs)
        }

        guard digestEnabled || milestonesEnabled else { return }
        guard let digest = ReminderDigest.fromMostRecentPlan(in: container.mainContext) else { return }

        var requests: [UNNotificationRequest] = []

        if digestEnabled, !digest.isEmpty {
            let content = UNMutableNotificationContent()
            content.title = "\(digest.planTitle) — daily check-in"
            var parts: [String] = []
            if !digest.overdue.isEmpty { parts.append("\(digest.overdue.count) overdue") }
            if !digest.dueSoon.isEmpty { parts.append("\(digest.dueSoon.count) due this week") }
            if let next = digest.milestones.first {
                parts.append("next milestone “\(next.name)” \(RelativeDateTimeFormatter().localizedString(for: next.finishDate, relativeTo: Date()))")
            }
            content.body = parts.joined(separator: ", ").capitalizedFirst
            content.sound = .default
            var components = DateComponents()
            components.hour = digestHour
            components.minute = 0
            requests.append(UNNotificationRequest(
                identifier: digestIdentifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            ))
        }

        if milestonesEnabled {
            let calendar = Calendar.current
            for milestone in digest.milestones.prefix(20) {
                guard let alertDay = calendar.date(byAdding: .day, value: -max(0, leadDays), to: milestone.finishDate),
                      alertDay > Date() else { continue }
                var components = calendar.dateComponents([.year, .month, .day], from: alertDay)
                components.hour = digestHour
                components.minute = 0
                let content = UNMutableNotificationContent()
                content.title = "Milestone approaching"
                content.body = "“\(milestone.name)” is due \(DateFormatting.shortDate(milestone.finishDate)) (\(digest.planTitle))."
                content.sound = .default
                requests.append(UNNotificationRequest(
                    identifier: prefix + "milestone.\(milestone.id)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                ))
            }

            // One-shot "became overdue" alerts for tasks finishing within 30 days.
            let horizon = calendar.date(byAdding: .day, value: 30, to: Date()) ?? Date()
            for task in digest.dueSoon.prefix(15) where task.finishDate <= horizon {
                guard let alertDay = calendar.date(byAdding: .day, value: 1, to: task.finishDate),
                      alertDay > Date() else { continue }
                var components = calendar.dateComponents([.year, .month, .day], from: alertDay)
                components.hour = digestHour
                components.minute = 5
                let content = UNMutableNotificationContent()
                content.title = "Task past due"
                content.body = "“\(task.name)” was due \(DateFormatting.shortDate(task.finishDate)) and isn’t complete (\(digest.planTitle))."
                content.sound = .default
                requests.append(UNNotificationRequest(
                    identifier: prefix + "overdue.\(task.id)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                ))
            }
        }

        for request in requests {
            center.add(request)
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

// MARK: - Menu bar dropdown

/// Content of the status-item popover: a compact, native-feeling panel with
/// the most recently updated plan's attention items.
struct MenuBarContentView: View {
    @Environment(\.modelContext) private var modelContext
    var onAction: (() -> Void)? = nil
    @State private var digest: ReminderDigest?
    @State private var shareAnchorView: NSView?
    @State private var justCopied = false
    @AppStorage(ReminderSettings.digestIncludeCostHighlights) private var includeCostHighlights = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let digest, !digest.isEmpty {
                        reminderSection("Overdue", rows: digest.overdue, tint: .red, icon: "exclamationmark.circle.fill")
                        reminderSection("Due this week", rows: digest.dueSoon, tint: .orange, icon: "clock.fill")
                        reminderSection("Milestones", rows: digest.milestones, tint: .purple, icon: "diamond.fill")
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text(digest == nil ? "No active plan yet." : "All clear — nothing needs attention.")
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 320)

            Divider()

            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 320)
        .focusEffectDisabled()
        .onAppear(perform: refresh)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(digest?.planTitle ?? "Planroom")
                    .font(.headline)
                    .lineLimit(1)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var headerSubtitle: String {
        guard let digest else { return "Open a plan to see reminders" }
        let count = digest.overdue.count + digest.dueSoon.count + digest.milestones.count
        if count == 0 { return "Everything is on track" }
        return "\(count) item\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") attention"
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button {
                onAction?()
                openApp()
            } label: {
                Label("Open Planroom", systemImage: "arrow.up.forward.app")
                    .font(.callout)
            }
            .buttonStyle(PanelHoverButtonStyle())

            Spacer()

            Button {
                presentSharePicker()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(PanelHoverButtonStyle())
            .background(ShareAnchorView(anchor: $shareAnchorView))
            .disabled(digest == nil)
            .help("Share Digest…")

            Button {
                copyDigest()
            } label: {
                Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(PanelHoverButtonStyle())
            .disabled(digest == nil)
            .help("Copy Digest")

            Button {
                onAction?()
                // Ensure a scene window exists, then let ContentView invoke the
                // openSettings environment action — the only reliable route.
                openApp(navigate: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    NotificationCenter.default.post(name: .openPlanroomSettings, object: nil)
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(PanelHoverButtonStyle())
            .help("Planroom Settings")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(PanelHoverButtonStyle())
            .help("Quit Planroom")
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func reminderSection(_ title: String, rows: [ReminderTaskRow], tint: Color, icon: String) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(tint)
                    Text(title.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .kerning(0.4)
                    Spacer()
                    Text("\(rows.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(rows.prefix(5).enumerated()), id: \.element.id) { index, row in
                        Button {
                            onAction?()
                            openApp()
                        } label: {
                            HStack(spacing: 8) {
                                Text(row.name)
                                    .lineLimit(1)
                                Spacer(minLength: 12)
                                Text(DateFormatting.shortDate(row.finishDate))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .font(.callout)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PanelHoverButtonStyle(padded: false))

                        if index < min(rows.count, 5) - 1 {
                            Divider().padding(.leading, 8)
                        }
                    }
                }
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                if rows.count > 5 {
                    Text("and \(rows.count - 5) more…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 8)
                }
            }
        }
    }

    private func refresh() {
        digest = ReminderDigest.fromMostRecentPlan(in: modelContext)
        ReminderScheduler.reschedule()
    }

    private func digestCostHighlights() -> EVMMetrics? {
        guard includeCostHighlights else { return nil }
        return ReminderDigest.costHighlights(in: modelContext)
    }

    private func presentSharePicker() {
        guard let digest, let anchor = shareAnchorView else { return }
        let picker = NSSharingServicePicker(items: [digest.sharePlainText(costHighlights: digestCostHighlights())])
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    private func copyDigest() {
        guard let digest else { return }
        let highlights = digestCostHighlights()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(digest.sharePlainText(costHighlights: highlights), forType: .string)
        pasteboard.setString(digest.shareHTML(costHighlights: highlights), forType: .html)
        justCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            justCopied = false
        }
    }

    private func openApp(navigate: Bool = true) {
        NSApp.activate(ignoringOtherApps: true)
        let hasDocumentWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeKey }
        if !hasDocumentWindow {
            NSDocumentController.shared.newDocument(nil)
        }
        if navigate {
            NotificationCenter.default.post(name: .navigateToItem, object: NavigationItem.tasks)
        }
    }
}

/// Invisible AppKit view that captures itself so NSSharingServicePicker has a
/// concrete anchor inside the SwiftUI popover.
private struct ShareAnchorView: NSViewRepresentable {
    @Binding var anchor: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { anchor = view }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Hover-highlighted borderless button used throughout the menu bar panel.
struct PanelHoverButtonStyle: ButtonStyle {
    var padded: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, padded: padded)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let padded: Bool
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, padded ? 7 : 0)
                .padding(.vertical, padded ? 4 : 0)
                .background(
                    isHovering ? Color.primary.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .opacity(configuration.isPressed ? 0.55 : 1)
                .onHover { hovering in
                    isHovering = hovering
                }
        }
    }
}

// MARK: - Settings

struct PlanroomSettingsView: View {
    @AppStorage(ReminderSettings.menuBarEnabled) private var menuBarEnabled = true
    @AppStorage(ReminderSettings.digestEnabled) private var digestEnabled = true
    @AppStorage(ReminderSettings.digestHour) private var digestHour = 9
    @AppStorage(ReminderSettings.milestoneAlertsEnabled) private var milestoneAlertsEnabled = true
    @AppStorage(ReminderSettings.milestoneLeadDays) private var milestoneLeadDays = 3
    @AppStorage(ReminderSettings.digestIncludeCostHighlights) private var includeCostHighlights = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show Planroom in the menu bar", isOn: $menuBarEnabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Reminders") {
                Toggle("Daily check-in notification", isOn: $digestEnabled)
                Picker("Remind me at", selection: $digestHour) {
                    ForEach(6..<21, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
                .disabled(!digestEnabled && !milestoneAlertsEnabled)

                Toggle("Milestone alerts", isOn: $milestoneAlertsEnabled)
                Stepper("Alert \(milestoneLeadDays) day(s) before a milestone", value: $milestoneLeadDays, in: 0...14)
                    .disabled(!milestoneAlertsEnabled)

                Toggle("Include cost highlights in shared digests", isOn: $includeCostHighlights)

                Text("Reminders come from your most recently updated plan and update whenever Planroom runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding(.vertical, 8)
        .onChange(of: digestEnabled) { _, _ in refreshScheduling() }
        .onChange(of: digestHour) { _, _ in refreshScheduling() }
        .onChange(of: milestoneAlertsEnabled) { _, _ in refreshScheduling() }
        .onChange(of: milestoneLeadDays) { _, _ in refreshScheduling() }
    }

    private func refreshScheduling() {
        if digestEnabled || milestoneAlertsEnabled {
            ReminderScheduler.requestAuthorizationIfNeeded()
        }
        ReminderScheduler.reschedule()
    }
}
