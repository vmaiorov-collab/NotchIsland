#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=NotchIsland.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
swiftc -O -swift-version 5 -F /System/Library/PrivateFrameworks -framework SkyLight Sources/main.swift -o $APP/Contents/MacOS/NotchIsland
clang -dynamiclib -fobjc-arc -framework Foundation Sources/np.m -o $APP/Contents/Resources/libnp.dylib
codesign -f -s - $APP/Contents/Resources/libnp.dylib
cat > $APP/Contents/Info.plist <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>NotchIsland</string>
<key>CFBundleIdentifier</key><string>com.local.notchisland</string>
<key>CFBundleExecutable</key><string>NotchIsland</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
codesign --force --sign - $APP
echo "Built $APP"
