#!/bin/bash
# 构建 macOS 发布版并打包 dmg
set -e
cd "$(dirname "$0")/.."

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
echo "==> flutter build macos --release (v$VERSION)"
flutter build macos --release

APP="build/macos/Build/Products/Release/Hiko.app"
DMG="dist/Hiko-$VERSION.dmg"
mkdir -p dist
rm -f "$DMG"

echo "==> 打包 $DMG"
hdiutil create -volname "Hiko" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null
echo "==> 完成：$DMG"
ls -lh "$DMG"
