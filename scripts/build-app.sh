#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product WageFlow "$@"
BIN_DIR=$(swift build -c release --show-bin-path "$@")
APP="dist/WageFlow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/WageFlow" "$APP/Contents/MacOS/WageFlow"
cp resource/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>WageFlow</string>
<key>CFBundleDisplayName</key><string>WageFlow</string>
<key>CFBundleIdentifier</key><string>local.wageflow.app</string>
<key>CFBundleExecutable</key><string>WageFlow</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
python3 - "$APP/Contents/Info.plist" <<'PY'
import os
from pathlib import Path
import plistlib
import re
import sys

version = os.environ.get("WAGEFLOW_VERSION", "1.0.0")
build = os.environ.get("WAGEFLOW_BUILD_NUMBER", "1")
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
    raise SystemExit("WAGEFLOW_VERSION must use MAJOR.MINOR.PATCH, e.g. 1.2.0")
if not re.fullmatch(r"[0-9]+", build):
    raise SystemExit("WAGEFLOW_BUILD_NUMBER must be numeric")
path = Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
info["CFBundleShortVersionString"] = version
info["CFBundleVersion"] = build
path.write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "已生成 $APP"
