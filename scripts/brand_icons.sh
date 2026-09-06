#!/usr/bin/env bash
# Render every platform icon from the brand masters in assets/brand/.
#
# The mark is drawn in code inside the app (rift_mark_path.dart); these are
# the places that need a file: launcher icons, the tray, favicons and the
# installer. All of them are the ink tile, pinned to Indigo, so the product
# has one identity outside the app however it is themed inside.
#
# Needs rsvg-convert and ImageMagick.
set -euo pipefail
cd "$(dirname "$0")/.."

tile=assets/brand/rift-tile.svg
square=assets/brand/rift-tile-square.svg

render() { # svg size out
  rsvg-convert -w "$2" -h "$2" "$1" -o "$3"
}

# Android launcher: plain mipmaps, one per density.
for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  render "$tile" "${pair#*:}" "android/app/src/main/res/mipmap-${pair%%:*}/ic_launcher.png"
done

# iOS masks its own corners, so it gets the square; macOS wants the shape.
for set in ios/Runner/Assets.xcassets/AppIcon.appiconset:$square macos/Runner/AppIcon.appiconset:$tile; do
  dir=${set%%:*}; src=${set#*:}
  for png in "$dir"/*.png; do
    size=$(basename "$png" .png)
    render "$src" "$size" "$png"
  done
done

# Windows: one .ico carrying every size Explorer asks for.
tmp=$(mktemp -d)
for s in 16 24 32 48 64 128 256; do render "$tile" "$s" "$tmp/$s.png"; done
magick "$tmp"/{16,24,32,48,64,128,256}.png windows/runner/resources/app_icon.ico
rm -rf "$tmp"

# Tray and notifications (Linux, Windows), the installer, the web app.
render "$tile" 72 assets/images/tray_icon.png
tmp=$(mktemp -d)
render "$tile" 256 "$tmp/256.png"
magick "$tmp/256.png" assets/images/tray_icon.ico
rm -rf "$tmp"
render "$tile" 72 web/favicon.png
render "$tile" 192 web/icons/icon.png

echo "rendered"
