#!/bin/bash
#
#  Release 构建：universal binary（x86_64 + arm64）→ strip → 签名 → zip / dmg
#  用法：./build_release.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="代码编辑器"
VERSION="2.0.0"
APP="$ROOT/build/$APP_NAME.app"
DIST="$ROOT/dist"
BUNDLE_ID="com.notepad.replica"

if [ -x /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc ]; then
  SWIFTC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
  SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
else
  SWIFTC="$(xcrun --find swiftc)"
  SDK="$(xcrun --sdk macosx --show-sdk-path)"
fi

echo "==> [1/6] 清理"
rm -rf "$APP" "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"

echo "==> [2/6] 编译 x86_64 / arm64（-O -wmo）"
for ARCH in x86_64 arm64; do
  echo "    - $ARCH"
  "$SWIFTC" -O -wmo -swift-version 5 \
    -sdk "$SDK" -target "${ARCH}-apple-macosx12.0" \
    "$ROOT"/Sources/*.swift \
    -o "$DIST/Notepad_$ARCH" \
    -framework AppKit
done

echo "==> [3/6] 合并为 universal binary"
lipo -create "$DIST/Notepad_x86_64" "$DIST/Notepad_arm64" \
     -output "$APP/Contents/MacOS/Notepad"
strip -x -S "$APP/Contents/MacOS/Notepad" 2>/dev/null || true
lipo -archs "$APP/Contents/MacOS/Notepad"
rm -f "$DIST/Notepad_x86_64" "$DIST/Notepad_arm64"

echo "==> [4/6] 资源与图标"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
[ -f "$ROOT/Resources/使用说明.html" ] && cp "$ROOT/Resources/使用说明.html" "$APP/Contents/Resources/"

ICONSET="$DIST/AppIcon.iconset"
mkdir -p "$ICONSET"
"$SWIFTC" -O -sdk "$SDK" -target "x86_64-apple-macosx12.0" \
  "$ROOT/Tools/makeicon.swift" -o "$DIST/makeicon" >/dev/null
"$DIST/makeicon" "$DIST/icon_1024.png" >/dev/null
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
  set -- $spec
  sips -z "$1" "$1" "$DIST/icon_1024.png" --out "$ICONSET/icon_$2.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" "$DIST/icon_1024.png" "$DIST/makeicon"

echo "==> [5/6] ad-hoc 签名并注册"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true
codesign -dv "$APP" 2>&1 | head -4 || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" || true

echo "==> [6/6] 打包 zip / dmg"
(cd "$ROOT/build" && zip -r -q -y "$DIST/${APP_NAME}-${VERSION}-macOS-universal.zip" "$APP_NAME.app")
hdiutil create -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO \
  "$DIST/${APP_NAME}-${VERSION}-macOS-universal.dmg" >/dev/null 2>&1 || \
  echo "    (dmg 生成失败，zip 已就绪)"

echo ""
echo "==> Release 构建完成：$DIST"
ls -lh "$DIST"
shasum -a 256 "$DIST"/*.zip "$DIST"/*.dmg 2>/dev/null || true
