import SwiftUI
import AppKit

// MARK: - Cursor Modifier

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

enum ColorTheme {
    static let workingDay = Color.green
    static let nonWorkingDay = Color.red
    static let exceptionDay = Color.orange
    static let criticalTask = Color.red
    static let normalTask = Color.accentColor
    static let milestone = Color.orange
    static let summaryTask = Color.primary
    static let completedFill = Color.accentColor
    static let progressBackground = Color.accentColor.opacity(0.3)
    static let baselineBar = Color.gray
    // "Healthy" states use teal rather than green. These are read directly
    // against the red "unhealthy" states, and teal-vs-red stays distinguishable
    // under red–green color blindness where green-vs-red does not.
    static let overAllocated = Color.red
    static let normalAllocation = Color.teal
    static let evmHealthy = Color.teal
    static let evmUnhealthy = Color.red
}
