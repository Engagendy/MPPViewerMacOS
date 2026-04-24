import SwiftUI
import AppKit

enum PrintManager {

    @MainActor
    static func printView<V: View>(_ view: V, size: CGSize, title: String) {
        let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.appearance = NSAppearance(named: .aqua)
        hostingView.needsLayout = true
        hostingView.displayIfNeeded()

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.orientation = .landscape
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        printInfo.jobDisposition = .spool

        let printOp = NSPrintOperation(view: hostingView, printInfo: printInfo)
        printOp.jobTitle = title
        printOp.showsPrintPanel = true
        printOp.showsProgressPanel = true
        printOp.run()
    }
}
