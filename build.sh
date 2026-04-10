#!/usr/bin/env bash

# Build script for MouseTrail

echo "Building MouseTrail..."

SWIFT_FLAGS=(-O -whole-module-optimization)

# Compile the Swift file
if swiftc "${SWIFT_FLAGS[@]}" main.swift -o MouseTrail; then
    echo "✓ Compilation successful"
else
    echo "✗ Compilation failed"
    exit 1
fi

# Create app bundle structure
echo "Creating app bundle..."
mkdir -p MouseTrail.app/Contents/MacOS
mkdir -p MouseTrail.app/Contents/Resources

# Copy executable
cp MouseTrail MouseTrail.app/Contents/MacOS/

# Create Info.plist
cat > MouseTrail.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MouseTrail</string>
    <key>CFBundleIdentifier</key>
    <string>com.jaredvogt.MouseTrail</string>
    <key>CFBundleName</key>
    <string>MouseTrail</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSBackgroundOnly</key>
    <true/>
</dict>
</plist>
EOF

echo "✓ App bundle created: MouseTrail.app"
echo ""
echo "You can now:"
echo "  • Double-click MouseTrail.app in Finder"
echo "  • Run from terminal: ./MouseTrail"
echo "  • Or open the app: open MouseTrail.app"
