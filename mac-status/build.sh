#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname "$HERE")
OUT="$ROOT/out/mac-status"
APP="$OUT/AI Network.app"
COMPILER=/Library/Developer/CommandLineTools/usr/bin/swiftc
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
mkdir -p "$OUT/module-cache" "$APP/Contents/MacOS" "$APP/Contents/Resources"
ARCH=$(uname -m)
"$COMPILER" -swift-version 5 -parse-as-library -O \
  -target "$ARCH-apple-macosx26.0" -sdk "$SDK" -module-cache-path "$OUT/module-cache" \
  "$HERE/Sources/StatusModel.swift" "$HERE/Sources/StatusViews.swift" "$HERE/Sources/GlassPresentation.swift" "$HERE/Sources/App.swift" \
  "$HERE/Tests/StatusModelTests.swift" \
  -framework AppKit -framework SwiftUI -framework Combine \
  -o "$APP/Contents/MacOS/AI Network"
cat > "$APP/Contents/Info.plist" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>AI Network</string>
<key>CFBundleDisplayName</key><string>AI Network</string>
<key>CFBundleExecutable</key><string>AI Network</string>
<key>CFBundleIdentifier</key><string>dev.artme.AINetwork</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Личный монитор сети · Только просмотр</string>
</dict></plist>
XML
"$COMPILER" -swift-version 5 -target "$ARCH-apple-macosx26.0" -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" "$HERE/Tools/MakeIcon.swift" -framework AppKit -o "$OUT/make-icon"
"$OUT/make-icon" "$OUT/AppIcon.iconset"
/usr/bin/iconutil -c icns "$OUT/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - --identifier dev.artme.AINetwork "$APP"
"$APP/Contents/MacOS/AI Network" --self-test
printf '%s\n' "$APP"
