# Quick Look Preview Extension for `.mppplan`

This folder contains a **complete, compile-verified** Quick Look preview
extension so Finder can preview a native `.mppplan` file (project header, key
metrics, and milestone timeline) when you press the Space bar — without opening
the app.

The **code is done**. The only remaining step is adding the target in Xcode,
which must be done via the GUI so Xcode generates the correct signing/embedding
configuration that Xcode Cloud needs (hand-editing `project.pbxproj` for a new
app-extension target risks breaking the release pipeline).

## Files

| File | Purpose |
|------|---------|
| `PreviewViewController.swift` | `QLPreviewingController` — loads the plan and hosts the SwiftUI card |
| `PlanPreview.swift` | Self-contained `.mppplan` reader + the SwiftUI preview view |
| `Info.plist` | Declares the extension handles `com.mppviewer.plan` |
| `QuickLookExtension.entitlements` | Sandbox + read-only file access |

## Add the target (≈ 2 minutes in Xcode)

1. **File → New → Target… → Quick Look Preview Extension.** Name it
   `QuickLookExtension`, embed in `MPPViewer`. Let Xcode create it.
2. Delete the placeholder files Xcode generated in the new target's folder.
3. **Add these four files** to the new target (drag them in, or point the
   target's build phase at this folder). Set membership to the extension
   target only.
4. In the target's **Build Settings**:
   - `INFOPLIST_FILE` → `MPPViewer/QuickLookExtension/Info.plist`
   - `CODE_SIGN_ENTITLEMENTS` → `MPPViewer/QuickLookExtension/QuickLookExtension.entitlements`
   - `GENERATE_INFOPLIST_FILE` → `NO`
   - Bundle identifier → `com.mppviewer.MPPViewer.QuickLook`
   - Deployment target → macOS 14.4 (match the app)
5. Confirm the extension appears under **MPPViewer → Build Phases → Embed
   Foundation Extensions** (Xcode adds this automatically).

## App Store Connect / signing

- Register the bundle ID `com.mppviewer.MPPViewer.QuickLook` in the Apple
  Developer portal so Xcode Cloud can sign the embedded extension.
- No new capabilities are required beyond the sandbox already used by the app.

## How it renders

`PlanPreview.load(from:)` decodes only the fields the preview needs (title,
manager/company, task & milestone counts, average % complete, schedule span,
and up to 12 milestones) using an ISO-8601 date strategy that matches the
app's `.mppplan` encoder. `PlanPreviewView` lays these out as a header, metric
chips, and a milestone list. It has **no dependency on the app's models**, so
the extension stays small and fast.
