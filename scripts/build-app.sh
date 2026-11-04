#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release "$@"
BIN_DIR=$(swift build -c release --show-bin-path "$@")
APP="dist/WageFlow.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/SalaryPanel" "$APP/Contents/MacOS/SalaryPanel"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>WageFlow</string>
<key>CFBundleDisplayName</key><string>WageFlow</string>
<key>CFBundleIdentifier</key><string>local.salary-panel.app</string>
<key>CFBundleExecutable</key><string>SalaryPanel</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "已生成 $APP"
