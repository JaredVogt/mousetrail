#!/usr/bin/env bash

# Build script for MouseTrail

echo "Building MouseTrail..."

# Update the in-app build timestamp so the info panel reflects the current build.
BUILD_TIME=$(date "+%Y-%m-%d %H:%M:%S")
sed -i '' "s/let BUILD_TIMESTAMP = \"[^\"]*\"/let BUILD_TIMESTAMP = \"$BUILD_TIME\"/" AppCore.swift

SWIFT_FLAGS=(-O -whole-module-optimization)

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

# Copy executable
cp MouseTrail MouseTrail.app/Contents/MacOS/

# Copy the project Info.plist so the app behaves like a menu bar app instead
# of a background-only process with no visible UI.
cp Info.plist MouseTrail.app/Contents/Info.plist

# Refresh bundle directory timestamps so Finder shows the latest build time
touch MouseTrail.app
touch MouseTrail.app/Contents
touch MouseTrail.app/Contents/MacOS

echo "✓ App bundle created: MouseTrail.app"
echo ""
echo "You can now:"
echo "  • Double-click MouseTrail.app in Finder"
echo "  • Run from terminal: ./MouseTrail"
echo "  • Or open the app: open MouseTrail.app"
