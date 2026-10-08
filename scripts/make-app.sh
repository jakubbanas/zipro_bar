#!/bin/sh
# Builds ZiproBar as a universal (arm64 + x86_64), ad-hoc signed .app bundle.
#   --install  also copy to ~/Applications (stable path for "Open at Login") and launch
#   --zip      also create build/ZiproBar-<version>.zip (+ .sha256) for a GitHub release
set -eu
cd "$(dirname "$0")/.."

arch="--arch arm64 --arch x86_64"
swift build -c release --product ZiproBar $arch
app=build/ZiproBar.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release $arch --show-bin-path)/ZiproBar" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
codesign --force --sign - "$app"
echo "Built $app"

case "${1:-}" in
--install)
    pkill -x ZiproBar || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/ZiproBar.app
    cp -R "$app" ~/Applications/
    open ~/Applications/ZiproBar.app
    echo "Installed and launched ~/Applications/ZiproBar.app"
    ;;
--zip)
    version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
    zip="build/ZiproBar-$version.zip"
    rm -f "$zip"
    ditto -c -k --keepParent "$app" "$zip"
    (cd build && shasum -a 256 "$(basename "$zip")" | tee "$(basename "$zip").sha256")
    ;;
esac
