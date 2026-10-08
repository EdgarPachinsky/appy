#!/bin/bash
# One-time setup: generates the macOS runner, applies Appy's macOS tweaks
# (icon, sandbox off so it can run npm/flutter, stays alive in menu bar).
set -e
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found in PATH. Install it from https://docs.flutter.dev/get-started/install/macos" >&2
  exit 1
fi

if [ ! -d macos/Runner.xcodeproj ]; then
  echo "→ Generating macOS project"
  flutter create --platforms=macos --project-name appy --org dev.appy .
  rm -f test/widget_test.dart
fi

echo "→ Applying Appy macOS overrides"
cp -R tool/macos_overrides/Runner/ macos/Runner/

# Current Xcode only supports macOS 12.0+ deployment targets.
sed -i '' -E 's/MACOSX_DEPLOYMENT_TARGET = [0-9.]+;/MACOSX_DEPLOYMENT_TARGET = 12.0;/g' macos/Runner.xcodeproj/project.pbxproj
if [ -f macos/Podfile ]; then
  sed -i '' -E "s/^#? *platform :osx, '[0-9.]+'/platform :osx, '12.0'/" macos/Podfile
fi

echo "→ Fetching packages"
flutter pub get

echo "→ Analyzing"
flutter analyze || true

echo ""
echo "Done. Run:    flutter run -d macos"
echo "      Build:  flutter build macos   (→ build/macos/Build/Products/Release/appy.app)"
