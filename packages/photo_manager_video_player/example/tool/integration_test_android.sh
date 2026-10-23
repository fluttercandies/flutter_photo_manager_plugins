#!/bin/sh
# Runs the playback integration tests on a connected Android emulator.
# `flutter test` reinstalls the app, so photo access is granted as soon as it appears.
set -e
cd "$(dirname "$0")/.."
(
  for _ in $(seq 1 300); do
    for permission in READ_MEDIA_VIDEO READ_MEDIA_IMAGES READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE; do
      adb shell pm grant com.fluttercandies.example "android.permission.$permission" >/dev/null 2>&1 || true
    done
    sleep 2
  done
) &
GRANTS=$!
# The grant loop would otherwise keep the CI step open after the tests end.
trap 'kill $GRANTS 2>/dev/null' EXIT
flutter test integration_test/playback_test.dart -d "${1:-emulator-5554}" --timeout 120s
