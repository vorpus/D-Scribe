#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="D Scribe"
SCHEME="D Scribe"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"

echo "==> Building $APP_NAME (Release, self-signed)..."
xcodebuild \
  -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  -quiet

echo "==> Build succeeded: $APP_PATH"

if [[ "${1:-}" == "--install" ]]; then
  echo "==> Installing to $INSTALL_PATH..."
  rm -rf "$INSTALL_PATH"
  cp -R "$APP_PATH" "$INSTALL_PATH"
  xattr -cr "$INSTALL_PATH"
  echo "==> Installed. You can launch $APP_NAME from Applications."
else
  echo "==> Run with --install to copy to /Applications"
  echo "    Or drag into Applications: $APP_PATH"
fi
