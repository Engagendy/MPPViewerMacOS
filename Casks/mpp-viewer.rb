cask "mpp-viewer" do
  version "2.2.2"
  sha256 :no_check # Update with actual SHA256 after first release

  url "https://github.com/Engagendy/MPPViewerMacOS/releases/download/v#{version}/MPPViewer-#{version}-arm64.dmg",
      verified: "github.com/Engagendy/MPPViewerMacOS/"

  name "MPP Viewer"
  desc "Native macOS viewer for Microsoft Project (.mpp) files"
  homepage "https://github.com/Engagendy/MPPViewerMacOS"

  depends_on macos: ">= :sonoma"

  app "MPP Viewer.app"

  postflight do
    # Remove quarantine attribute so the unsigned app can launch
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/MPP Viewer.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Caches/com.mppviewer.MPPViewer",
    "~/Library/Preferences/com.mppviewer.MPPViewer.plist",
    "~/Library/Saved Application State/com.mppviewer.MPPViewer.savedState",
  ]
end
