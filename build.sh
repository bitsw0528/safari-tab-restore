#!/bin/bash

# Tab Restore App build script.
# Usage: ./build_app.sh
# This script compiles the Release build, finds the generated .app, copies it to the desktop, and launches it.

set -e

# Get the current script directory and project info
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
PROJECT_NAME="tab restore"
BUILD_DIR="$HOME/Library/Developer/Xcode/DerivedData"
DESKTOP_DIR="$HOME/Desktop"

echo "Starting Tab Restore build..."

# Change into the Xcode project directory so xcodebuild picks up the workspace correctly.
cd "$PROJECT_DIR"

# Clean and build the Release configuration so we can ship the correct binary.
echo "Cleaning and building the project..."
xcodebuild -project "$PROJECT_NAME.xcodeproj" \
           -scheme "$PROJECT_NAME" \
           -configuration Release \
           clean build

# Locate the newly built .app bundle inside DerivedData.
APP_PATH=$(find "$BUILD_DIR" -name "$PROJECT_NAME.app" -path "*/Release/*" | head -1)

if [[ -z "$APP_PATH" ]]; then
    echo "Build failed: no app bundle found in DerivedData."
    exit 1
fi

echo "Build succeeded! App found at: $APP_PATH"

# Copy the bundle to the desktop so it is easy to find.
DESKTOP_APP_PATH="$DESKTOP_DIR/$PROJECT_NAME.app"
echo "Copying app bundle to the desktop..."

if [[ -d "$DESKTOP_APP_PATH" ]]; then
    rm -rf "$DESKTOP_APP_PATH"
fi

cp -R "$APP_PATH" "$DESKTOP_DIR/"

echo "All done! The app is now at: $DESKTOP_APP_PATH"

# Launch the copied build so you can test the result immediately.
echo "🚀 Launching the desktop copy..."
open "$DESKTOP_APP_PATH"
