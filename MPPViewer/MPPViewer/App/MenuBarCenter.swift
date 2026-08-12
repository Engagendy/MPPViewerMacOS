import SwiftUI
import SwiftData
import AppKit
import UserNotifications
import ServiceManagement

/// AppStorage keys for the menu bar + reminder features.
enum ReminderSettings {
    static let menuBarEnabled = "reminders.menuBarEnabled"
    static let digestEnabled = "reminders.digestEnabled"
    static let digestHour = "reminders.digestHour"
    static let milestoneAlertsEnabled = "reminders.milestoneAlertsEnabled"
    static let milestoneLeadDays = "reminders.milestoneLeadDays"
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

    /// Builds the digest from the most recently updated active plan.
    @MainActor
    static func fromMostRecentPlan(in context: ModelContext) -> ReminderDigest? {
        var descriptor = FetchDescriptor<PortfolioProjectPlan>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 8
        guard let plans = try? context.fetch(descriptor),
              let plan = plans.first(where: { !$0.isArchivedValue }) else { return nil }

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
            .buttonStyle(.borderless)

            Spacer()

            Button {
                onAction?()
                NSApp.activate(ignoringOtherApps: true)
                // The Settings scene selector must run after the transient
                // popover has closed and the app is active, and its name
                // differs across macOS releases.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                        _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Planroom Settings")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
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
                        .buttonStyle(.plain)

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

    private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        let hasDocumentWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeKey }
        if !hasDocumentWindow {
            NSDocumentController.shared.newDocument(nil)
        }
        NotificationCenter.default.post(name: .navigateToItem, object: NavigationItem.tasks)
    }
}

// MARK: - Settings

struct PlanroomSettingsView: View {
    @AppStorage(ReminderSettings.menuBarEnabled) private var menuBarEnabled = true
    @AppStorage(ReminderSettings.digestEnabled) private var digestEnabled = true
    @AppStorage(ReminderSettings.digestHour) private var digestHour = 9
    @AppStorage(ReminderSettings.milestoneAlertsEnabled) private var milestoneAlertsEnabled = true
    @AppStorage(ReminderSettings.milestoneLeadDays) private var milestoneLeadDays = 3
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
