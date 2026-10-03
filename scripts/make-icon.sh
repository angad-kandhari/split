#!/bin/sh
# Renders assets/app-icon.svg into the app icon set. Requires rsvg-convert (brew install librsvg).
set -eu
cd "$(dirname "$0")/.."
out=Split/Brand/Assets.xcassets/AppIcon.appiconset
for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" assets/app-icon.svg -o "$out/icon_${size}.png"
    rsvg-convert -w "$((size * 2))" -h "$((size * 2))" assets/app-icon.svg -o "$out/icon_${size}@2x.png"
done
echo "Wrote icons to $out"
