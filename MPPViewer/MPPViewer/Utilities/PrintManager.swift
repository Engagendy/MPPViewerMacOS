import SwiftUI
import AppKit
import Combine

/// User-facing print options surfaced in the NSPrintPanel accessory view.
/// Orientation and page ranges are handled by the standard panel controls
/// (`.showsOrientation` / `.showsPageRange`); this model covers the
/// Planroom-specific extras: headers/footers and Gantt scaling.
final class PrintPanelOptions: ObservableObject {
    enum ScalingMode: String, CaseIterable, Identifiable {
        case fitToPage = "Fit to Page Width"
        case actualSize = "Actual Size (tile pages)"
        var id: String { rawValue }
    }

    @Published var showHeader: Bool = true
    @Published var showPageNumbers: Bool = true
    @Published var scaling: ScalingMode = .fitToPage

    let projectName: String

    init(projectName: String) {
        self.projectName = projectName
    }

    var wantsHeaderOrFooter: Bool { showHeader || showPageNumbers }
}

enum PrintManager {

    @MainActor
    static func printView<V: View>(_ view: V, size: CGSize, title: String) {
        let hostingView = PrintHostingView(
            rootView: AnyView(view.frame(width: size.width, height: size.height))
        )
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

        let options = PrintPanelOptions(projectName: title)
        hostingView.printOptions = options
        printInfo.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = NSNumber(value: true)

        let printOp = NSPrintOperation(view: hostingView, printInfo: printInfo)
        printOp.jobTitle = title
        printOp.showsPrintPanel = true
        printOp.showsProgressPanel = true

        let panel = printOp.printPanel
        panel.options.formUnion([
            .showsCopies,
            .showsPageRange,
            .showsOrientation,
            .showsPaperSize,
            .showsScaling,
            .showsPreview
        ])
        panel.addAccessoryController(PrintOptionsAccessoryController(options: options, printInfo: printInfo))

        printOp.run()

        window.contentView = nil
    }
}

// MARK: - Hosting view with header/footer support

/// NSHostingView subclass that draws the Planroom page header (project name +
/// print date) and footer ("Page X of Y") when enabled in the print options.
private final class PrintHostingView: NSHostingView<AnyView> {
    var printOptions: PrintPanelOptions?

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    @MainActor @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported for PrintHostingView")
    }

    override var pageHeader: NSAttributedString {
        guard let options = printOptions, options.showHeader else {
            return NSAttributedString(string: "")
        }
        let dateText = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        let text = options.projectName.isEmpty ? dateText : "\(options.projectName)  —  \(dateText)"
        return NSAttributedString(string: text, attributes: Self.headerFooterAttributes)
    }

    override var pageFooter: NSAttributedString {
        guard let options = printOptions, options.showPageNumbers,
              let operation = NSPrintOperation.current else {
            return NSAttributedString(string: "")
        }
        let current = operation.currentPage
        let range = operation.pageRange
        let text: String
        if range.length > 0, range.location != NSNotFound {
            let last = range.location + range.length - 1
            text = "Page \(current) of \(last)"
        } else {
            text = "Page \(current)"
        }
        return NSAttributedString(string: text, attributes: Self.headerFooterAttributes)
    }

    private static let headerFooterAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 9, weight: .regular),
        .foregroundColor: NSColor.darkGray
    ]
}

// MARK: - Print panel accessory

/// Standard NSPrintPanel accessory controller hosting the SwiftUI options form.
private final class PrintOptionsAccessoryController: NSViewController, NSPrintPanelAccessorizing {
    private let options: PrintPanelOptions
    private let printInfo: NSPrintInfo
    private var cancellable: AnyCancellable?

    /// KVO-visible token bumped whenever an option changes so the print
    /// panel preview refreshes (see `keyPathsForValuesAffectingPreview`).
    @objc dynamic var optionsRevision: Int = 0

    init(options: PrintPanelOptions, printInfo: NSPrintInfo) {
        self.options = options
        self.printInfo = printInfo
        super.init(nibName: nil, bundle: nil)
        title = "Planroom"

        cancellable = options.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyOptions()
            }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let hosting = NSHostingView(rootView: PrintOptionsForm(options: options))
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 150)
        view = hosting
    }

    private func applyOptions() {
        printInfo.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] =
            NSNumber(value: options.wantsHeaderOrFooter)
        switch options.scaling {
        case .fitToPage:
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .automatic
        case .actualSize:
            printInfo.horizontalPagination = .automatic
            printInfo.verticalPagination = .automatic
            printInfo.scalingFactor = 1.0
        }
        optionsRevision += 1
    }

    // MARK: NSPrintPanelAccessorizing

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        [
            [.itemName: "Header", .itemDescription: options.showHeader ? "Project name and date" : "Off"],
            [.itemName: "Page Numbers", .itemDescription: options.showPageNumbers ? "On" : "Off"],
            [.itemName: "Scaling", .itemDescription: options.scaling.rawValue]
        ]
    }

    func keyPathsForValuesAffectingPreview() -> Set<String> {
        ["optionsRevision"]
    }
}

private struct PrintOptionsForm: View {
    @ObservedObject var options: PrintPanelOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Header with project name and date", isOn: $options.showHeader)
            Toggle("Footer with page numbers", isOn: $options.showPageNumbers)
            Picker("Scaling:", selection: $options.scaling) {
                ForEach(PrintPanelOptions.ScalingMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            Text("Use the standard controls above for paper size, orientation, and page ranges.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }
}
