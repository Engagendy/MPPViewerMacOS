import Foundation

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
}
