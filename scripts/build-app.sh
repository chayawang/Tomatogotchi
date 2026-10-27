#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
project_root="$PWD"
python3 scripts/make-app-icon.py
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$project_root/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$project_root/.build/module-cache"
swift build --configuration release --product Tomatogotchi --disable-sandbox
binary_dir="$(swift build --configuration release --show-bin-path --disable-sandbox 2>/dev/null)"
app="$project_root/build/Tomatogotchi.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Tomatogotchi" "$app/Contents/MacOS/Tomatogotchi"
cp -R "$binary_dir/Tomatogotchi_Tomatogotchi.bundle" "$app/Contents/Resources/"
cp Sources/Tomatogotchi/Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>work.shiroi.tomatogotchi</string>
<key>CFBundleName</key><string>Tomatogotchi</string>
<key>CFBundleDisplayName</key><string>Tomatogotchi</string>
<key>CFBundleExecutable</key><string>Tomatogotchi</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.3</string>
<key>CFBundleVersion</key><string>38</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
printf '\nBuilt: %s\nLocal development build; not notarized for public distribution.\n' "$app"
