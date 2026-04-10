#!/usr/bin/env bash

# Build script for MouseTrail (Working version)

echo "Building MouseTrail..."

# Get current timestamp
BUILD_TIME=$(date "+%Y-%m-%d %H:%M:%S")
echo "Build time: $BUILD_TIME"

# Update the BUILD_TIMESTAMP in main.swift
sed -i '' "s/let BUILD_TIMESTAMP = \"[^\"]*\"/let BUILD_TIMESTAMP = \"$BUILD_TIME\"/" main.swift

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

# Copy executable directly
cp MouseTrail MouseTrail.app/Contents/MacOS/MouseTrail

# Copy Info.plist
if [ -f "Info.plist" ]; then
    cp Info.plist MouseTrail.app/Contents/Info.plist
    echo "✓ Info.plist copied"
else
    echo "✗ Info.plist not found, creating basic one..."
    # Create basic Info.plist as fallback
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
    <key>CFBundleDisplayName</key>
    <string>Mouse Trail</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.13</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF
fi

echo "✓ App bundle created: MouseTrail.app"

# Copy to Applications folder
echo ""
echo "Copying to /Applications..."
if cp -R MouseTrail.app /Applications/; then
    echo "✓ App installed to /Applications/MouseTrail.app"
else
    echo "✗ Failed to copy to /Applications (may need sudo)"
fi

echo ""
echo "The app can now be double-clicked to launch without Terminal!"
echo "It will appear only as a menu bar icon."
