import SwiftUI

/// Adds the hover affordance macOS bordered controls lack: a soft rounded
/// highlight while the pointer is over the control, so toggles and bordered
/// buttons read as interactive before they are clicked.
private struct HoverHighlightModifier: ViewModifier {
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovering && isEnabled ? 0.07 : 0))
                    .allowsHitTesting(false)
            )
            .onHover { hovering in
                isHovering = hovering
            }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

extension View {
    /// Hover feedback for bordered toolbar controls (buttons and button-style
    /// toggles), matching the highlight `.accessoryBar` buttons get for free.
    func hoverHighlight() -> some View {
        modifier(HoverHighlightModifier())
    }
}
