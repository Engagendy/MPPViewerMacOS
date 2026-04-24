#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <template-name> <app-path> [output-trace]"
  echo "Example: $0 \"Time Profiler\" /tmp/mpp-performance-derived/Build/Products/Debug/MPPViewer.app /tmp/mppviewer.trace"
  exit 1
fi

TEMPLATE="$1"
APP_PATH="$2"
OUTPUT_PATH="${3:-/tmp/mppviewer-$(date +%Y%m%d-%H%M%S).trace}"

echo "Recording template: $TEMPLATE"
echo "App: $APP_PATH"
echo "Trace: $OUTPUT_PATH"

xcrun xctrace record \
  --template "$TEMPLATE" \
  --launch "$APP_PATH" \
  --output "$OUTPUT_PATH"

echo "Trace saved to $OUTPUT_PATH"
