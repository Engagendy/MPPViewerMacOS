import SwiftUI

/// A compact date control combining a type-in text field with a button that
/// opens a graphical month calendar in a popover. Replaces the field-style
/// DatePicker whose tiny steppers make date entry cumbersome.
struct CalendarDatePicker: View {
    var title: String = ""
    @Binding var date: Date
    var isCompact: Bool = false

    @State private var isPresented = false
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private static let parseFormatters: [DateFormatter] = {
        var formatters: [DateFormatter] = []

        let short = DateFormatter()
        short.dateStyle = .short
        short.timeStyle = .none
        short.isLenient = true
        formatters.append(short)

        let explicitFormats = [
            "d/M/yyyy",
            "M/d/yyyy",
            "yyyy-MM-dd",
            "d-M-yyyy",
            "d.M.yyyy",
            "d MMM yyyy",
            "MMM d yyyy",
            "MMM d, yyyy"
        ]
        for format in explicitFormats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.isLenient = true
            formatters.append(formatter)
        }
        return formatters
    }()

    var body: some View {
        HStack(spacing: 6) {
            if !title.isEmpty {
                Text(title)
            }

            HStack(spacing: 4) {
                TextField("Date", text: $text)
                    .textFieldStyle(.plain)
                    .monospacedDigit()
                    .focused($isFocused)
                    .onSubmit(commitTypedDate)
                    .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
                        if press.key == .downArrow, press.modifiers.contains(.command) {
                            commitTypedDate()
                            isPresented = true
                        } else {
                            adjustDay(by: press.key == .upArrow ? 1 : -1)
                        }
                        return .handled
                    }
                    .frame(minWidth: isCompact ? 66 : 84)

                Button {
                    isPresented.toggle()
                } label: {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                        .font(isCompact ? .caption : .body)
                }
                .buttonStyle(.borderless)
                // Keep the icon out of the tab order so Tab moves from the
                // text field straight to the next input; the calendar stays
                // reachable by mouse or Command-Down Arrow from the field.
                .focusable(false)
                .help("Pick from calendar (⌘↓)")
                .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                    CalendarPopoverContent(date: $date, isPresented: $isPresented)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, isCompact ? 2 : 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(isFocused ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1)
            )
        }
        .onAppear {
            text = DateFormatting.shortDate(date)
        }
        .onChange(of: date) { _, newValue in
            text = DateFormatting.shortDate(newValue)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                commitTypedDate()
            }
        }
    }

    private func adjustDay(by days: Int) {
        commitTypedDate()
        if let adjusted = Calendar.current.date(byAdding: .day, value: days, to: date) {
            date = Calendar.current.startOfDay(for: adjusted)
        }
    }

    private func commitTypedDate() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            for formatter in Self.parseFormatters {
                if let parsed = formatter.date(from: trimmed) {
                    let normalized = Calendar.current.startOfDay(for: parsed)
                    if normalized != Calendar.current.startOfDay(for: date) {
                        date = normalized
                    }
                    break
                }
            }
        }
        // Re-render from the bound value so invalid or oddly formatted
        // input always settles back to a real date.
        text = DateFormatting.shortDate(date)
    }
}

private struct CalendarPopoverContent: View {
    @Binding var date: Date
    @Binding var isPresented: Bool

    // The calendar shows this draft selection; month/year menus move it
    // without committing, and only clicking a day (or Today) writes the
    // draft back to the bound date and closes the popover.
    @State private var draftDate: Date

    init(date: Binding<Date>, isPresented: Binding<Bool>) {
        self._date = date
        self._isPresented = isPresented
        self._draftDate = State(initialValue: date.wrappedValue)
    }

    private var draftYear: Int {
        Calendar.current.component(.year, from: draftDate)
    }

    private var draftMonth: Int {
        Calendar.current.component(.month, from: draftDate)
    }

    private var yearRange: [Int] {
        let center = draftYear
        return Array((center - 30)...(center + 30))
    }

    private var monthSymbols: [String] {
        Calendar.current.monthSymbols
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Picker("Month", selection: Binding(
                    get: { draftMonth },
                    set: { setDraft(month: $0) }
                )) {
                    ForEach(1...12, id: \.self) { month in
                        Text(monthSymbols[month - 1]).tag(month)
                    }
                }
                .labelsHidden()

                Picker("Year", selection: Binding(
                    get: { draftYear },
                    set: { setDraft(year: $0) }
                )) {
                    ForEach(yearRange, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .labelsHidden()
                .frame(width: 76)
            }

            DatePicker(
                "",
                selection: Binding(
                    get: { draftDate },
                    set: { picked in
                        draftDate = picked
                        commit(picked)
                    }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .id(draftDate)

            HStack {
                Button("Today") {
                    commit(Date())
                }
                .controlSize(.small)

                Spacer()

                Text(DateFormatting.shortWeekday(draftDate) + ", " + DateFormatting.shortDate(draftDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(10)
        .frame(width: 252)
    }

    private func setDraft(month: Int? = nil, year: Int? = nil) {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: draftDate)
        if let month {
            components.month = month
        }
        if let year {
            components.year = year
        }

        // Clamp the day so e.g. Jan 31 -> Feb lands on a valid date.
        if let day = components.day,
           let firstOfMonth = calendar.date(from: DateComponents(year: components.year, month: components.month, day: 1)),
           let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count {
            components.day = min(day, daysInMonth)
        }

        if let updated = calendar.date(from: components) {
            draftDate = calendar.startOfDay(for: updated)
        }
    }

    private func commit(_ picked: Date) {
        date = Calendar.current.startOfDay(for: picked)
        isPresented = false
    }
}
