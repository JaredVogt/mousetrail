#!/usr/bin/env bash

# Build script for MouseTrail (Working version)

echo "Building MouseTrail..."

# Get current timestamp
BUILD_TIME=$(date "+%Y-%m-%d %H:%M:%S")
echo "Build time: $BUILD_TIME"

# Update the BUILD_TIMESTAMP in AppCore.swift
sed -i '' "s/let BUILD_TIMESTAMP = \"[^\"]*\"/let BUILD_TIMESTAMP = \"$BUILD_TIME\"/" AppCore.swift

SWIFT_FLAGS=(-O -whole-module-optimization)

# Compile Metal CIKernel for ripple effect
METAL_SRC="RippleKernel.ci.metal"
if [ -f "$METAL_SRC" ]; then
    echo "Compiling Metal kernel..."
    if xcrun metal -c -fcikernel "$METAL_SRC" -o /tmp/RippleKernel.air && \
       xcrun metallib -cikernel /tmp/RippleKernel.air -o /tmp/RippleKernel.metallib; then
        echo "✓ Metal kernel compiled"
    else
        echo "✗ Metal kernel compilation failed"
        exit 1
    fi
fi

# Compile the Swift file
if swiftc "${SWIFT_FLAGS[@]}" *.swift -o MouseTrail; then
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

# Copy Metal library to Resources
if [ -f "/tmp/RippleKernel.metallib" ]; then
    cp /tmp/RippleKernel.metallib MouseTrail.app/Contents/Resources/RippleKernel.metallib
    echo "✓ Metal library bundled"
fi

echo "✓ App bundle created: MouseTrail.app"

# Codesign the app bundle with a stable identity (so TCC permissions persist across rebuilds)
SIGN_IDENTITY="Apple Development: jared@dca.io (6HZ3G86AKD)"
codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements entitlements.plist MouseTrail.app
echo "✓ App signed with: $SIGN_IDENTITY"

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
