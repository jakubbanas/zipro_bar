#!/bin/sh
# Builds ZiproBar and wraps it in an ad-hoc signed .app bundle (needed for the Bluetooth permission).
# --install also copies it to ~/Applications, a stable path for "Start with macOS".
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product ZiproBar
app=build/ZiproBar.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/ZiproBar" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
codesign --force --sign - "$app"
echo "Built $app"

if [ "${1:-}" = "--install" ]; then
    pkill -x ZiproBar || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/ZiproBar.app
    cp -R "$app" ~/Applications/
    open ~/Applications/ZiproBar.app
    echo "Installed and launched ~/Applications/ZiproBar.app"
fi
