import SwiftUI
import AppKit

extension Color {
    /// Builds a Color from a `#RRGGBB` (or `RRGGBB`) hex string. Returns nil
    /// for anything that isn't a valid 6-digit hex color.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6, let intValue = UInt64(value, radix: 16) else {
            return nil
        }
        let red = Double((intValue >> 16) & 0xFF) / 255.0
        let green = Double((intValue >> 8) & 0xFF) / 255.0
        let blue = Double(intValue & 0xFF) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }

    /// Serializes the color to a `#RRGGBB` hex string via its sRGB components.
    var hexString: String? {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let red = Int((components.redComponent * 255).rounded())
        let green = Int((components.greenComponent * 255).rounded())
        let blue = Int((components.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
