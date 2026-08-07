import SwiftUI
import AppKit

enum PrintManager {

    @MainActor
    static func printView<V: View>(_ view: V, size: CGSize, title: String) {
        let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.appearance = NSAppearance(named: .aqua)

        // A detached NSHostingView prints blank pages — SwiftUI only renders
        // once the view is part of a window. Host it in an offscreen window
        // and force layout/display before printing. The window is retained for
        // the duration of the synchronous print operation.
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        hostingView.needsDisplay = true
        hostingView.displayIfNeeded()

        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        printInfo.orientation = .landscape
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        printInfo.jobDisposition = .spool

        let printOp = NSPrintOperation(view: hostingView, printInfo: printInfo)
        printOp.jobTitle = title
        printOp.showsPrintPanel = true
        printOp.showsProgressPanel = true
        printOp.run()

        window.contentView = nil
    }
}
