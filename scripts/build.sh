#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$PROJECT_DIR/dist/Xbox Controller Helper.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources" "$PROJECT_DIR/.build"
xcrun swift "$PROJECT_DIR/scripts/make-icon.swift" "$PROJECT_DIR/.build/AppIcon.iconset"
/usr/bin/iconutil -c icns "$PROJECT_DIR/.build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
xcrun clang -dynamiclib -arch arm64 -arch x86_64 -Wall -Wextra \
  "$PROJECT_DIR/Sources/xbox-identity.c" -o "$APP/Contents/Frameworks/xbox-identity.dylib"
xcrun swiftc -O -target arm64-apple-macosx13.0 \
  "$PROJECT_DIR/Sources/Environment.swift" "$PROJECT_DIR/Sources/PromptPolicy.swift" "$PROJECT_DIR/Sources/main.swift" \
  -framework AppKit -framework SwiftUI -framework IOKit -o "$APP/Contents/MacOS/XboxControllerHelper"
cp "$PROJECT_DIR/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP/Contents/Frameworks/xbox-identity.dylib"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"
