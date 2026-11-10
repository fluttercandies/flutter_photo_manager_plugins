// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager_video_player/photo_manager_video_player.dart';
import 'package:photo_manager_video_player/src/controller.dart'
    show applyPlayerEvent;

const AssetEntityVideoValue _base = AssetEntityVideoValue(
  size: Size(1920, 1080),
  duration: Duration(seconds: 12),
);

void main() {
  test('a malformed event is ignored instead of throwing', () {
    expect(
      applyPlayerEvent(_base, const <Object?, Object?>{'event': 'initialized'}),
      same(_base),
    );
  });

  test('initialized replaces the seeded duration with the exact one', () {
    final AssetEntityVideoValue result = applyPlayerEvent(
      _base,
      const <Object?, Object?>{'event': 'initialized', 'durationMs': 12345},
    );
    expect(result.isInitialized, isTrue);
    expect(result.duration, const Duration(milliseconds: 12345));
    expect(result.size, _base.size, reason: 'size comes from the AssetEntity');
  });

  test('completion survives the playback-stopped event that follows it', () {
    final AssetEntityVideoValue completed = applyPlayerEvent(
      _base,
      const <Object?, Object?>{'event': 'completed'},
    );
    final AssetEntityVideoValue afterStop = applyPlayerEvent(
      completed,
      const <Object?, Object?>{'event': 'playing', 'isPlaying': false},
    );
    expect(afterStop.isCompleted, isTrue);
  });

  test('starting playback clears completion', () {
    final AssetEntityVideoValue completed = applyPlayerEvent(
      _base,
      const <Object?, Object?>{'event': 'completed'},
    );
    final AssetEntityVideoValue restarted = applyPlayerEvent(
      completed,
      const <Object?, Object?>{'event': 'playing', 'isPlaying': true},
    );
    expect(restarted.isCompleted, isFalse);
  });

  test('AssetEntityVideoValue has value equality', () {
    expect(_base, equals(_base.copyWith()));
    expect(_base.hashCode, _base.copyWith().hashCode);
  });

  test('videoSize corrects the size seeded from the asset', () {
    const AssetEntityVideoValue seeded = AssetEntityVideoValue(
      size: Size.zero,
      duration: Duration.zero,
    );

    final AssetEntityVideoValue next = applyPlayerEvent(
      seeded,
      <Object?, Object?>{'event': 'videoSize', 'width': 1920, 'height': 1080},
    );

    expect(next.size, const Size(1920, 1080));
    expect(next.aspectRatio, closeTo(16 / 9, 0.001));
  });

  test('videoSize carries the upright size and the texture rotation', () {
    const AssetEntityVideoValue seeded = AssetEntityVideoValue(
      size: Size.zero,
      duration: Duration.zero,
    );

    final AssetEntityVideoValue next =
        applyPlayerEvent(seeded, <Object?, Object?>{
      'event': 'videoSize',
      'width': 720,
      'height': 1280,
      'rotationDegrees': 90,
    });

    expect(next.size, const Size(720, 1280));
    expect(next.rotationCorrection, 90);
  });
}
