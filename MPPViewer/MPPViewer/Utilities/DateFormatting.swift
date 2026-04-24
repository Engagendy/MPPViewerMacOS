import Foundation
import os

enum DateFormatting {
    // MPXJ dates look like: "2026-02-04T08:00:00.0"
    private static let mpxjFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.S"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    private static let mpxjFormatterNoFrac: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    private static let simpleDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    private static let shortWeekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E"
        return f
    }()

    private static let mediumDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func parseMPXJDate(_ string: String) -> Date? {
        if let d = mpxjFormatter.date(from: string) { return d }
        if let d = mpxjFormatterNoFrac.date(from: string) { return d }
        if let d = simpleDateFormatter.date(from: string) { return d }
        return nil
    }

    static func parseSimpleDate(_ string: String) -> Date? {
        simpleDateFormatter.date(from: string)
    }

    static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    static func shortDate(_ string: String?) -> String {
        guard let s = string, let d = parseMPXJDate(s) else { return "" }
        return shortDate(d)
    }

    static func mediumDateTime(_ date: Date) -> String {
        mediumDateTimeFormatter.string(from: date)
    }

    static func mediumDateTime(_ string: String?) -> String {
        guard let s = string, let d = parseMPXJDate(s) else { return "" }
        return mediumDateTime(d)
    }

    static func shortWeekday(_ date: Date) -> String {
        shortWeekdayFormatter.string(from: date)
    }

    static func mpxjDateTime(_ date: Date) -> String {
        mpxjFormatter.string(from: date)
    }

    static func simpleDate(_ date: Date) -> String {
        simpleDateFormatter.string(from: date)
    }
}

enum CurrencyFormatting {
    private static let lock = NSLock()
    private static var formatterCache: [String: NumberFormatter] = [:]

    static func string(
        from value: Double,
        currencyCode: String? = nil,
        currencySymbol: String? = nil,
        maximumFractionDigits: Int = 0,
        minimumFractionDigits: Int = 0
    ) -> String {
        let formatter = formatter(
            currencyCode: currencyCode,
            currencySymbol: currencySymbol,
            maximumFractionDigits: maximumFractionDigits,
            minimumFractionDigits: minimumFractionDigits
        )
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maximumFractionDigits)f", value)
    }

    private static func formatter(
        currencyCode: String?,
        currencySymbol: String?,
        maximumFractionDigits: Int,
        minimumFractionDigits: Int
    ) -> NumberFormatter {
        let cacheKey = [
            currencyCode ?? "",
            currencySymbol ?? "",
            String(maximumFractionDigits),
            String(minimumFractionDigits)
        ].joined(separator: "|")

        lock.lock()
        defer { lock.unlock() }

        if let cached = formatterCache[cacheKey] {
            return cached
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        if let currencyCode {
            formatter.currencyCode = currencyCode
        }
        if let currencySymbol {
            formatter.currencySymbol = currencySymbol
        }
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = minimumFractionDigits
        formatterCache[cacheKey] = formatter
        return formatter
    }
}

enum PerformanceMonitor {
    static let subsystem = "com.mppviewer.MPPViewer"
    static let interactionLogger = Logger(subsystem: subsystem, category: "Interaction")
    static let signposter = OSSignposter(subsystem: subsystem, category: "Interaction")

    @discardableResult
    static func measure<T>(_ name: StaticString, _ body: () -> T) -> T {
        let state = signposter.beginInterval(name)
        let result = body()
        signposter.endInterval(name, state)
        return result
    }

    static func mark(_ name: StaticString, message: String) {
        interactionLogger.debug("\(name, privacy: .public): \(message, privacy: .public)")
        signposter.emitEvent(name, "\(message, privacy: .public)")
    }
}
