import Foundation

enum DurationFormatting {
    /// Formats a duration in seconds (as MPXJ outputs) into a human-readable string.
    /// Assumes 8-hour work days.
    static func formatSeconds(_ totalSeconds: Int) -> String {
        if totalSeconds == 0 { return "0d" }

        let hours = Double(totalSeconds) / 3600.0
        let days = hours / 8.0

        if days >= 1 && days == days.rounded() {
            return "\(Int(days))d"
        } else if days >= 1 {
            return String(format: "%.1fd", days)
        } else if hours >= 1 {
            return String(format: "%.1fh", hours)
        } else {
            let minutes = totalSeconds / 60
            return "\(minutes)m"
        }
    }

    /// Formats an optional duration string (legacy support)
    static func format(_ duration: String?) -> String {
        guard let duration = duration, !duration.isEmpty else { return "" }
        return duration
    }
}
