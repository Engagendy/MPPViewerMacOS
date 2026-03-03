import SwiftUI

struct CalendarView: View {
    let calendars: [ProjectCalendar]
    @State private var selectedCalendar: ProjectCalendar?
    @State private var displayMonth = Date()

    var body: some View {
        if calendars.isEmpty {
            ContentUnavailableView("No Calendars", systemImage: "calendar", description: Text("This project has no calendars defined."))
        } else {
            HSplitView {
                // Calendar list
                List(calendars, selection: Binding(
                    get: { selectedCalendar?.id },
                    set: { id in selectedCalendar = calendars.first { $0.id == id } }
                )) { cal in
                    VStack(alignment: .leading) {
                        Text(cal.name ?? "Unnamed")
                            .font(.body)
                        if let calType = cal.type {
                            Text(calType)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(cal.id)
                }
                .listStyle(.sidebar)
                .frame(minWidth: 180, maxWidth: 250)

                // Calendar grid
                if let cal = selectedCalendar ?? calendars.first {
                    CalendarMonthGrid(calendar: cal, displayMonth: $displayMonth)
                } else {
                    Text("Select a calendar")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

struct CalendarMonthGrid: View {
    let calendar: ProjectCalendar
    @Binding var displayMonth: Date

    private let sysCalendar = Calendar.current
    private let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayMonth)
    }

    private var daysInMonth: [Date?] {
        let components = sysCalendar.dateComponents([.year, .month], from: displayMonth)
        guard let firstDay = sysCalendar.date(from: components),
              let range = sysCalendar.range(of: .day, in: .month, for: firstDay) else {
            return []
        }

        let firstWeekday = sysCalendar.component(.weekday, from: firstDay) - 1
        var days: [Date?] = Array(repeating: nil, count: firstWeekday)

        for day in range {
            if let date = sysCalendar.date(bySetting: .day, value: day, of: firstDay) {
                days.append(date)
            }
        }

        // Pad to complete weeks
        while days.count % 7 != 0 {
            days.append(nil)
        }

        return days
    }

    var body: some View {
        VStack(spacing: 16) {
            // Month navigation
            HStack {
                Button(action: { changeMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                Text(monthTitle)
                    .font(.title2)
                    .frame(minWidth: 200)

                Button(action: { changeMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
            }

            // Calendar info
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle().fill(ColorTheme.workingDay).frame(width: 10, height: 10)
                    Text("Working").font(.caption)
                }
                HStack(spacing: 4) {
                    Circle().fill(ColorTheme.nonWorkingDay).frame(width: 10, height: 10)
                    Text("Non-working").font(.caption)
                }
                HStack(spacing: 4) {
                    Circle().fill(ColorTheme.exceptionDay).frame(width: 10, height: 10)
                    Text("Exception").font(.caption)
                }
            }
            .foregroundStyle(.secondary)

            // Day headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(daysOfWeek, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        let dayInfo = dayStatus(for: date)
                        VStack(spacing: 2) {
                            Text("\(sysCalendar.component(.day, from: date))")
                                .font(.body)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(dayInfo.color.opacity(0.3))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(dayInfo.isException ? ColorTheme.exceptionDay : .clear, lineWidth: 1.5)
                        )
                        .help(dayInfo.tooltip)
                    } else {
                        Color.clear.frame(minHeight: 44)
                    }
                }
            }

            // Exceptions list
            if let exceptions = calendar.exceptions, !exceptions.isEmpty {
                GroupBox("Exceptions") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(exceptions) { exception in
                            HStack {
                                Circle()
                                    .fill(exception.isWorking ? ColorTheme.workingDay : ColorTheme.nonWorkingDay)
                                    .frame(width: 8, height: 8)
                                Text(exception.name ?? "Unnamed")
                                Spacer()
                                if let from = exception.from, let to = exception.to {
                                    Text("\(from) - \(to)")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .padding(4)
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func changeMonth(by value: Int) {
        if let newDate = sysCalendar.date(byAdding: .month, value: value, to: displayMonth) {
            displayMonth = newDate
        }
    }

    private struct DayInfo {
        let isWorking: Bool
        let isException: Bool
        let tooltip: String
        var color: Color {
            if isException { return ColorTheme.exceptionDay }
            return isWorking ? ColorTheme.workingDay : ColorTheme.nonWorkingDay
        }
    }

    private func dayStatus(for date: Date) -> DayInfo {
        let weekday = sysCalendar.component(.weekday, from: date)

        // Check exceptions
        if let exceptions = calendar.exceptions {
            for exception in exceptions {
                if isDate(date, inException: exception) {
                    return DayInfo(
                        isWorking: exception.isWorking,
                        isException: true,
                        tooltip: exception.name ?? "Exception"
                    )
                }
            }
        }

        // Check regular days from calendar
        let isWorking = calendar.isWorkingDay(weekday: weekday)
        return DayInfo(
            isWorking: isWorking,
            isException: false,
            tooltip: isWorking ? "Working day" : "Non-working day"
        )
    }

    private func isDate(_ date: Date, inException exception: CalendarException) -> Bool {
        guard let from = exception.fromDate, let to = exception.toDate else {
            return false
        }
        let startOfDay = sysCalendar.startOfDay(for: date)
        return startOfDay >= sysCalendar.startOfDay(for: from) && startOfDay <= sysCalendar.startOfDay(for: to)
    }
}
