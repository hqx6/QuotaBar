#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
if [[ "${QUOTABAR_UNIVERSAL:-0}" == "1" ]]; then
  swift build -c release --arch arm64 --disable-sandbox
  swift build -c release --arch x86_64 --disable-sandbox
  mkdir -p .build/universal
  lipo -create .build/arm64-apple-macosx/release/QuotaBar .build/x86_64-apple-macosx/release/QuotaBar -output .build/universal/QuotaBar
  BINARY="$PWD/.build/universal/QuotaBar"
else
  swift build -c release --disable-sandbox
  BINARY="$PWD/.build/release/QuotaBar"
fi
APP="$PWD/dist/QuotaBar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/QuotaBar"
swift scripts/make-icon.swift "$PWD/.build/artwork"
iconutil --convert icns --output "$APP/Contents/Resources/AppIcon.icns" "$PWD/.build/artwork/AppIcon.iconset"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>QuotaBar</string>
<key>CFBundleIdentifier</key><string>local.huqixin.QuotaBar</string>
<key>CFBundleName</key><string>QuotaBar</string>
<key>CFBundleDisplayName</key><string>QuotaBar</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.2</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
print "已生成：$APP"
