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
}
