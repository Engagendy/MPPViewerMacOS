#!/bin/sh
# Xcode Cloud: derive the marketing version from the newest v* git tag so
# cutting a release is just pushing a tag — no manual project edits.
# The build number (CFBundleVersion) is already managed by Xcode Cloud itself.
set -e

if [ -z "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
    echo "Not running in Xcode Cloud; skipping version stamping."
    exit 0
fi

cd "$CI_PRIMARY_REPOSITORY_PATH"

latest_tag=$(git tag --list 'v*' --sort=-v:refname | head -1)
if [ -z "$latest_tag" ]; then
    echo "No v* tags found; keeping the project's MARKETING_VERSION."
    exit 0
fi

version="${latest_tag#v}"
echo "Stamping MARKETING_VERSION = $version (from tag $latest_tag)"
sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $version;/g" \
    "MPPViewer/MPPViewer.xcodeproj/project.pbxproj"
