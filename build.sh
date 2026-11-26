#!/bin/bash
# 构建 MouseHighlighter.app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/MouseHighlighter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 \
    -framework AppKit -framework Carbon -framework QuartzCore \
    Sources/main.swift -o "$APP/Contents/MacOS/MouseHighlighter"

# 图标：没有就用 Tools/make_icon.swift 生成
if [[ ! -f Resources/AppIcon.icns ]]; then
    swift Tools/make_icon.swift Resources
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MouseHighlighter</string>
    <key>CFBundleDisplayName</key><string>Mouse Highlighter</string>
    <key>CFBundleIdentifier</key><string>local.mousehighlighter</string>
    <key>CFBundleExecutable</key><string>MouseHighlighter</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built: $(pwd)/$APP"

# ./build.sh install  → 安装到 /Applications 并启动（开机自启指向这个位置）
if [[ "${1:-}" == "install" ]]; then
    pkill -x MouseHighlighter || true
    sleep 0.5
    rm -rf /Applications/MouseHighlighter.app
    cp -R "$APP" /Applications/
    touch /Applications/MouseHighlighter.app   # 让 Finder 刷新图标
    open /Applications/MouseHighlighter.app
    echo "Installed: /Applications/MouseHighlighter.app"
fi
