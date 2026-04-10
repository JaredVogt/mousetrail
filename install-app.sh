#!/usr/bin/env bash

# Build the app
echo "Building MouseTrail..."
./build-working.sh

# Check if build succeeded
if [ ! -d "MouseTrail.app" ]; then
    echo "Build failed - MouseTrail.app not found"
    exit 1
fi

# Sign with entitlements
echo "Signing app with entitlements..."
codesign --force --deep --sign - --entitlements entitlements.plist MouseTrail.app

# Copy to Applications
echo "Installing to /Applications..."
cp -R MouseTrail.app /Applications/

# Verify installation
if [ -d "/Applications/MouseTrail.app" ]; then
    echo "✓ App installed successfully to /Applications/MouseTrail.app"
    echo ""
    echo "To run the app:"
    echo "  - Double-click MouseTrail in Applications folder"
    echo "  - Or run: open /Applications/MouseTrail.app"
    echo ""
    echo "To see debug output, open the Info Panel from the menu bar"
else
    echo "✗ Installation failed"
    exit 1
fi