#!/usr/bin/env bash

# Build script for MouseTrail (No Terminal version)

echo "Building MouseTrail..."

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
rm -rf MouseTrail.app
mkdir -p MouseTrail.app/Contents/MacOS
mkdir -p MouseTrail.app/Contents/Resources

# Copy executable with a different name
cp MouseTrail MouseTrail.app/Contents/MacOS/MouseTrail-Binary

# Create an AppleScript launcher that runs without Terminal
cat > MouseTrail.app/Contents/MacOS/MouseTrail << 'EOF'
#!/usr/bin/osascript
on run
    set appPath to (path to me as text)
    set appPOSIX to POSIX path of appPath
    set binaryPath to appPOSIX & "Contents/MacOS/MouseTrail-Binary"
    do shell script quoted form of binaryPath & " > /dev/null 2>&1 &"
end run
EOF

chmod +x MouseTrail.app/Contents/MacOS/MouseTrail
chmod +x MouseTrail.app/Contents/MacOS/MouseTrail-Binary

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
</dict>
</plist>
EOF

echo "✓ App bundle created: MouseTrail.app"
echo ""
echo "This version will run without opening a Terminal window!"
