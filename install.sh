#!/bin/bash
set -e

APP_NAME="Teletalk"
BUILD_DIR="build"
INSTALL_DIR="/Applications"

echo "╔══════════════════════════════════════╗"
echo "║         TeleTalk Installer           ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Check requirements
if ! command -v xcodebuild &> /dev/null; then
    echo "Error: Xcode command line tools not found."
    echo "Install with: xcode-select --install"
    exit 1
fi

if [[ $(uname -m) != "arm64" ]]; then
    echo "Error: TeleTalk requires Apple Silicon (M1 or later)."
    exit 1
fi

# Code signing setup
echo "Code signing options:"
echo "  1) Ad-hoc signing (no Apple account needed, works on your Mac only)"
echo "  2) Sign with your Apple Developer account"
echo ""
read -p "Choose [1/2] (default: 1): " SIGN_CHOICE
SIGN_CHOICE=${SIGN_CHOICE:-1}

SIGN_FLAGS=""
if [[ "$SIGN_CHOICE" == "2" ]]; then
    # List available signing identities
    echo ""
    echo "Available signing identities:"
    security find-identity -v -p codesigning | grep "Apple Development\|Developer ID"
    echo ""
    read -p "Enter your Team ID (e.g. D8D266XP48): " TEAM_ID
    if [[ -z "$TEAM_ID" ]]; then
        echo "Error: Team ID is required for developer signing."
        exit 1
    fi
    SIGN_FLAGS="DEVELOPMENT_TEAM=$TEAM_ID"
else
    SIGN_FLAGS='CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO'
fi

# Build
echo ""
echo "Building $APP_NAME (Release)..."
eval xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    $SIGN_FLAGS \
    clean build 2>&1 | tail -3

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: Build failed. Run with Xcode for detailed logs."
    exit 1
fi

# Install
echo ""
read -p "Install to $INSTALL_DIR? [Y/n]: " INSTALL_CHOICE
INSTALL_CHOICE=${INSTALL_CHOICE:-Y}

if [[ "$INSTALL_CHOICE" =~ ^[Yy]$ ]]; then
    cp -R "$APP_PATH" "$INSTALL_DIR/"
    echo ""
    echo "Installed to $INSTALL_DIR/$APP_NAME.app"

    # Refresh icon cache
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null

    echo ""
    echo "Done! Launch TeleTalk from Spotlight or /Applications."
    echo "On first launch, grant Microphone, Accessibility, and Input Monitoring permissions."
else
    echo ""
    echo "Build complete at: $APP_PATH"
    echo "Move it to /Applications manually when ready."
fi
