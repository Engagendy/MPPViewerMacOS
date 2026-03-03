#!/usr/bin/env bash
set -euo pipefail

# ─── MPP Viewer — Build & Package Script ───────────────────────────────
# Builds the Java converter JAR, the macOS app, bundles the JRE and JAR,
# and creates a .dmg for distribution.
#
# Usage:
#   ./scripts/package.sh [--skip-jar] [--skip-app] [--arch arm64|x86_64] [--version X.Y]
#
# Requirements:
#   - Xcode command-line tools (xcodebuild)
#   - Maven (mvn)
#   - curl, tar, hdiutil
# ────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Configuration ──────────────────────────────────────────────────────
APP_NAME="MPP Viewer"
APP_BUNDLE="MPPViewer.app"
SCHEME="MPPViewer"
XCODEPROJ="$PROJECT_ROOT/MPPViewer/MPPViewer.xcodeproj"
MAVEN_DIR="$PROJECT_ROOT/MPPConverter"
JAR_NAME="mpxj-converter.jar"

JRE_VERSION="21"
JRE_CACHE_DIR="$PROJECT_ROOT/.cache/jre"

BUILD_DIR="$PROJECT_ROOT/build"
DMG_DIR="$BUILD_DIR/dmg"

SKIP_JAR=false
SKIP_APP=false
ARCH="$(uname -m)"   # arm64 or x86_64
VERSION_OVERRIDE=""

# ─── Parse Arguments ────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-jar)  SKIP_JAR=true; shift ;;
        --skip-app)  SKIP_APP=true; shift ;;
        --arch)      ARCH="$2"; shift 2 ;;
        --version)   VERSION_OVERRIDE="$2"; shift 2 ;;
        *)           echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Map architecture names for Adoptium API
case "$ARCH" in
    arm64|aarch64) ADOPTIUM_ARCH="aarch64"; DMG_ARCH="arm64" ;;
    x86_64|amd64)  ADOPTIUM_ARCH="x64";     DMG_ARCH="x86_64" ;;
    *)             echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

echo "═══════════════════════════════════════════════════════════"
echo "  MPP Viewer — Build & Package"
echo "  Architecture: $ARCH"
if [[ -n "$VERSION_OVERRIDE" ]]; then
    echo "  Version override: $VERSION_OVERRIDE"
fi
echo "═══════════════════════════════════════════════════════════"
echo ""

# ─── Step 1: Build Java Converter JAR ───────────────────────────────────
if [[ "$SKIP_JAR" == false ]]; then
    echo "▸ Building Java converter JAR…"
    (cd "$MAVEN_DIR" && mvn clean package -q -DskipTests)
    echo "  ✓ JAR built: $MAVEN_DIR/target/$JAR_NAME"
else
    echo "▸ Skipping JAR build (--skip-jar)"
fi

JAR_PATH="$MAVEN_DIR/target/$JAR_NAME"
if [[ ! -f "$JAR_PATH" ]]; then
    echo "ERROR: JAR not found at $JAR_PATH"
    echo "       Run without --skip-jar to build it."
    exit 1
fi

# ─── Step 2: Build macOS App ────────────────────────────────────────────
VERSION_BUILD_FLAG=""
if [[ -n "$VERSION_OVERRIDE" ]]; then
    VERSION_BUILD_FLAG="MARKETING_VERSION=$VERSION_OVERRIDE"
fi

if [[ "$SKIP_APP" == false ]]; then
    echo ""
    echo "▸ Building macOS app…"
    xcodebuild -project "$XCODEPROJ" \
        -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        -arch "$ARCH" \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        $VERSION_BUILD_FLAG \
        clean build 2>&1 | tail -5
    echo "  ✓ App built"
else
    echo "▸ Skipping app build (--skip-app)"
fi

# Locate the built .app
APP_PATH="$(find "$BUILD_DIR/DerivedData" -name "$APP_BUNDLE" -type d | head -1)"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "ERROR: $APP_BUNDLE not found in build output."
    exit 1
fi
echo "  App location: $APP_PATH"

# ─── Step 3: Download Eclipse Temurin JRE ───────────────────────────────
echo ""
echo "▸ Preparing JRE (Eclipse Temurin $JRE_VERSION, $ADOPTIUM_ARCH)…"

mkdir -p "$JRE_CACHE_DIR"
JRE_TARBALL="$JRE_CACHE_DIR/temurin-jre-${JRE_VERSION}-${ADOPTIUM_ARCH}.tar.gz"
JRE_EXTRACT_DIR="$JRE_CACHE_DIR/temurin-jre-${JRE_VERSION}-${ADOPTIUM_ARCH}"

if [[ -f "$JRE_TARBALL" ]]; then
    echo "  Using cached JRE tarball"
else
    JRE_URL="https://api.adoptium.net/v3/binary/latest/${JRE_VERSION}/ga/mac/${ADOPTIUM_ARCH}/jre/hotspot/normal/eclipse"
    echo "  Downloading from Adoptium…"
    curl -fSL -o "$JRE_TARBALL" "$JRE_URL"
    echo "  ✓ Downloaded"
fi

if [[ ! -d "$JRE_EXTRACT_DIR" ]]; then
    echo "  Extracting JRE…"
    mkdir -p "$JRE_EXTRACT_DIR"
    tar xzf "$JRE_TARBALL" -C "$JRE_EXTRACT_DIR" --strip-components=1
    echo "  ✓ Extracted"
fi

# Find the Home directory inside the extracted JRE (macOS bundles it under Contents/Home)
JRE_HOME="$(find "$JRE_EXTRACT_DIR" -type d -name "Home" | head -1)"
if [[ -z "$JRE_HOME" ]]; then
    # Fallback: the extract dir itself is the JRE root
    JRE_HOME="$JRE_EXTRACT_DIR"
fi

# Verify java binary exists
if [[ ! -f "$JRE_HOME/bin/java" ]]; then
    echo "ERROR: java binary not found in extracted JRE at $JRE_HOME/bin/java"
    exit 1
fi

# ─── Step 4: Bundle JRE into App ────────────────────────────────────────
echo ""
echo "▸ Bundling JRE into app…"

PLUGINS_DIR="$APP_PATH/Contents/PlugIns"
mkdir -p "$PLUGINS_DIR/jre"

# Copy JRE contents (bin, lib, conf, etc.)
rsync -a --delete "$JRE_HOME/" "$PLUGINS_DIR/jre/"

# Strip quarantine attributes so macOS allows execution of bundled JRE
xattr -cr "$PLUGINS_DIR/jre/" 2>/dev/null || true
echo "  ✓ JRE bundled at PlugIns/jre/"

# ─── Step 5: Bundle JAR into App ────────────────────────────────────────
echo "▸ Bundling converter JAR into app…"

RESOURCES_DIR="$APP_PATH/Contents/Resources"
mkdir -p "$RESOURCES_DIR"
cp "$JAR_PATH" "$RESOURCES_DIR/$JAR_NAME"
echo "  ✓ JAR bundled at Resources/$JAR_NAME"

# ─── Step 6: Read Version ──────────────────────────────────────────────
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0.0")"
echo ""
echo "  Version: $VERSION"

# ─── Step 7: Create DMG ────────────────────────────────────────────────
echo ""
echo "▸ Creating DMG…"

DMG_NAME="MPPViewer-${VERSION}-${DMG_ARCH}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

# Clean up any previous DMG staging
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Copy app and create Applications symlink
cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

# Remove any existing DMG
rm -f "$DMG_PATH"

# Create compressed DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" 2>&1 | tail -2

echo "  ✓ DMG created: $DMG_PATH"

# ─── Done ───────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✓ Build complete!"
echo ""
echo "  DMG:  $DMG_PATH"
echo "  Size: $(du -h "$DMG_PATH" | cut -f1)"
echo "═══════════════════════════════════════════════════════════"
