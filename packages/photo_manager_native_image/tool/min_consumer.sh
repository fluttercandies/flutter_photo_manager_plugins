#!/bin/sh
# Builds a new app that depends on this package by path, so CI can check the
# minimum Flutter versions an app can use, without the package's own dev tools.
#
# usage: tool/min_consumer.sh apk | ios-cocoapods | ios-swiftpm
set -e
MODE=$1
PKG=$(cd "$(dirname "$0")/.." && pwd)
NAME=$(sed -n 's/^name: *//p' "$PKG/pubspec.yaml")
APP=${RUNNER_TEMP:-${TMPDIR:-/tmp}}/min_consumer

case $MODE in
  ios-cocoapods) flutter config --no-enable-swift-package-manager ;;
  ios-swiftpm) flutter config --enable-swift-package-manager ;;
  apk) ;;
  *) echo "usage: $0 apk | ios-cocoapods | ios-swiftpm" >&2; exit 2 ;;
esac
flutter --version

rm -rf "$APP"
flutter create --platforms android,ios -t app --project-name min_consumer "$APP" >/dev/null
cd "$APP"
python3 - "$NAME" "$PKG" <<'PY'
import sys
name, path = sys.argv[1:]
s = open('pubspec.yaml').read()
s = s.replace('\ndependencies:\n', f'\ndependencies:\n  {name}:\n    path: {path}\n', 1)
open('pubspec.yaml', 'w').write(s)
PY
flutter pub get

if [ "$MODE" = apk ]; then
  MIN_SDK=$(sed -n 's/.*minSdkVersion *\([0-9][0-9]*\).*/\1/p' "$PKG/android/build.gradle" | head -1)
  for gradle in android/app/build.gradle android/app/build.gradle.kts; do
    [ -f "$gradle" ] && sed -i.bak "s/minSdk = flutter.minSdkVersion/minSdk = $MIN_SDK/" "$gradle"
  done
  flutter build apk --debug
  exit 0
fi

sed -i.bak 's/IPHONEOS_DEPLOYMENT_TARGET = 1[0-2]\.0/IPHONEOS_DEPLOYMENT_TARGET = 13.0/' ios/Runner.xcodeproj/project.pbxproj
if [ "$MODE" = ios-cocoapods ]; then
  # The Podfile appears on the first build; give it the plugin's iOS 13 floor.
  flutter build ios --simulator --debug --no-codesign --config-only
  sed -i.bak "s/^# platform :ios.*/platform :ios, '13.0'/" ios/Podfile
fi
flutter build ios --simulator --debug --no-codesign

# Fail unless the plugin went through the integration this job is named after.
GENERATED=ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift
in_swiftpm() { [ -f "$GENERATED" ] && grep -q "$NAME" "$GENERATED"; }
in_cocoapods() { [ -f ios/Podfile.lock ] && grep -q "$NAME" ios/Podfile.lock; }
if [ "$MODE" = ios-cocoapods ]; then
  in_cocoapods && ! in_swiftpm || { echo "$NAME was not integrated through CocoaPods." >&2; exit 1; }
else
  in_swiftpm && ! in_cocoapods || { echo "$NAME was not integrated through Swift Package Manager." >&2; exit 1; }
fi
echo "$NAME was integrated through ${MODE#ios-}."
