#!/bin/sh
# Builds the app and zips it for a GitHub release: build/ZiproBar-<version>.zip (+ .sha256).
set -eu
cd "$(dirname "$0")/.."

./scripts/make-app.sh
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
zip="build/ZiproBar-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent build/ZiproBar.app "$zip"
(cd build && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")
echo "Packaged $zip"
