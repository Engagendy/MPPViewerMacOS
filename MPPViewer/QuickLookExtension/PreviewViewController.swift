import Cocoa
import Quartz
import SwiftUI

/// Quick Look preview controller for `.mppplan` files. Reads the plan and hosts
/// the SwiftUI preview card so Finder's Space-bar preview shows the project
/// header, key metrics, and milestone timeline without opening the app.
class PreviewViewController: NSViewController, QLPreviewingController {

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 460))
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let plan = PlanPreview.load(from: url) ?? PlanPreview(
            title: url.deletingPathExtension().lastPathComponent,
            manager: nil,
            company: nil,
            taskCount: 0,
            milestoneCount: 0,
            percentComplete: 0,
            startDate: nil,
            finishDate: nil,
            milestones: []
        )

        await MainActor.run {
            let hosting = NSHostingView(rootView: PlanPreviewView(plan: plan))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: view.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
    }
}
