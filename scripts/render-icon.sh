#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p resource
ICON_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/wageflow-icon.XXXXXX")
trap 'rm -rf "$ICON_TEMP"' EXIT HUP INT TERM
ICONSET="$ICON_TEMP/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/render-icon.swift resource/AppIcon.png
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" resource/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" resource/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
python3 - "$ICONSET" <<'PY'
from pathlib import Path
import struct
import sys

# Modern macOS ICNS stores PNG representations in size-specific chunks.
iconset = Path(sys.argv[1])
representations = {
    b'icp4': 'icon_16x16.png',
    b'icp5': 'icon_32x32.png',
    b'ic07': 'icon_128x128.png',
    b'ic08': 'icon_256x256.png',
    b'ic09': 'icon_512x512.png',
    b'ic10': 'icon_512x512@2x.png',
    b'ic11': 'icon_16x16@2x.png',
    b'ic12': 'icon_32x32@2x.png',
    b'ic13': 'icon_128x128@2x.png',
    b'ic14': 'icon_256x256@2x.png',
}
chunks = []
for kind, filename in representations.items():
    data = (iconset / filename).read_bytes()
    chunks.append(kind + struct.pack('>I', len(data) + 8) + data)
body = b''.join(chunks)
Path('resource/AppIcon.icns').write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
PY
echo "Generated resource/AppIcon.icns"
