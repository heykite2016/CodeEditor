#!/bin/bash
#
#  构建脚本：编译 → 组装 .app → 生成图标 → 注册到 LaunchServices
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="代码编辑器"
APP="$ROOT/build/$APP_NAME.app"
BUNDLE_ID="com.notepad.replica"

# 本机 xcode-select 指向 CommandLineTools（其 modulemap 有重复定义问题），
# 因此优先使用 Xcode 内置工具链。
if [ -x /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc ]; then
  SWIFTC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
  SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
else
  SWIFTC="$(xcrun --find swiftc)"
  SDK="$(xcrun --sdk macosx --show-sdk-path)"
fi

ARCH="$(uname -m)"
echo "==> 编译（$ARCH / $(basename "$SWIFTC")）"
rm -rf "$APP"
rm -rf "$ROOT/build/记事本.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

"$SWIFTC" -O -wmo -swift-version 5 \
  -sdk "$SDK" -target "${ARCH}-apple-macosx12.0" \
  "$ROOT"/Sources/*.swift \
  -o "$APP/Contents/MacOS/Notepad" \
  -framework AppKit

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
[ -f "$ROOT/Resources/使用说明.html" ] && cp "$ROOT/Resources/使用说明.html" "$APP/Contents/Resources/"

echo "==> 生成图标"
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
"$SWIFTC" -O -sdk "$SDK" -target "${ARCH}-apple-macosx12.0" \
  "$ROOT/Tools/makeicon.swift" -o "$ROOT/build/makeicon" >/dev/null
"$ROOT/build/makeicon" "$ROOT/build/icon_1024.png" >/dev/null
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
  set -- $spec
  sips -z "$1" "$1" "$ROOT/build/icon_1024.png" --out "$ICONSET/icon_$2.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" "$ROOT/build/icon_1024.png" "$ROOT/build/makeicon"

echo "==> 签名（ad-hoc）并注册"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" || true

echo "==> 完成：$APP"
echo "    运行：open \"$APP\""
