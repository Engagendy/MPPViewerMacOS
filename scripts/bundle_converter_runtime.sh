#!/usr/bin/env bash
set -euo pipefail

if [[ "${MPPVIEWER_SKIP_RUNTIME_BUNDLE:-}" == "1" ]]; then
    echo "Skipping converter runtime bundle step."
    exit 0
fi

if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
    echo "error: TARGET_BUILD_DIR and UNLOCALIZED_RESOURCES_FOLDER_PATH must be set by Xcode."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAVEN_DIR="$PROJECT_ROOT/MPPConverter"
JAR_NAME="mpxj-converter.jar"
JAR_PATH="$MAVEN_DIR/target/$JAR_NAME"
VENDORED_JAR_PATH="$MAVEN_DIR/vendor/$JAR_NAME"
RESOURCES_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
JRE_VERSION="21"
JRE_CACHE_DIR="$PROJECT_ROOT/.cache/jre"

mkdir -p "$RESOURCES_DIR"

if [[ ! -f "$JAR_PATH" && ! -f "$VENDORED_JAR_PATH" ]]; then
    if ! command -v mvn >/dev/null 2>&1; then
        echo "error: Neither $JAR_PATH nor $VENDORED_JAR_PATH exists, and Maven is not available to build it."
        exit 1
    fi
    echo "Building MPXJ converter JAR..."
    (cd "$MAVEN_DIR" && mvn clean package -q -DskipTests)
fi

if [[ -f "$JAR_PATH" ]]; then
    cp "$JAR_PATH" "$RESOURCES_DIR/$JAR_NAME"
elif [[ -f "$VENDORED_JAR_PATH" ]]; then
    cp "$VENDORED_JAR_PATH" "$RESOURCES_DIR/$JAR_NAME"
else
    echo "error: Converter JAR not found at $JAR_PATH or $VENDORED_JAR_PATH."
    exit 1
fi

echo "Bundled $JAR_NAME."

archs="${ARCHS:-$(uname -m)}"
for arch in $archs; do
    case "$arch" in
        arm64|aarch64)
            adoptium_arch="aarch64"
            runtime_arch="arm64"
            ;;
        x86_64|amd64)
            adoptium_arch="x64"
            runtime_arch="x86_64"
            ;;
        *)
            echo "warning: Skipping unsupported runtime architecture: $arch"
            continue
            ;;
    esac

    tarball="$JRE_CACHE_DIR/temurin-jre-${JRE_VERSION}-${adoptium_arch}.tar.gz"
    extract_dir="$JRE_CACHE_DIR/temurin-jre-${JRE_VERSION}-${adoptium_arch}"

    if [[ ! -d "$extract_dir" ]]; then
        mkdir -p "$JRE_CACHE_DIR" "$extract_dir"
        if [[ ! -f "$tarball" ]]; then
            url="https://api.adoptium.net/v3/binary/latest/${JRE_VERSION}/ga/mac/${adoptium_arch}/jre/hotspot/normal/eclipse"
            echo "Downloading Eclipse Temurin JRE $JRE_VERSION for $runtime_arch..."
            curl -fL -o "$tarball" "$url"
        fi
        tar xzf "$tarball" -C "$extract_dir" --strip-components=1
    fi

    jre_home="$(find "$extract_dir" -type d -name Home | head -1)"
    if [[ -z "$jre_home" ]]; then
        jre_home="$extract_dir"
    fi

    if [[ ! -f "$jre_home/bin/java" ]]; then
        echo "error: java binary not found in JRE at $jre_home/bin/java."
        exit 1
    fi

    runtime_dir="$RESOURCES_DIR/jre/$runtime_arch"
    mkdir -p "$runtime_dir"
    rsync -a --delete "$jre_home/" "$runtime_dir/"
    xattr -cr "$runtime_dir/" 2>/dev/null || true
    chmod -R u+rwX,go+rX "$runtime_dir/"
    echo "Bundled JRE for $runtime_arch."
done
