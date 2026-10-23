// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_video_player/photo_manager_video_player.dart';

const MethodChannel _channel = MethodChannel(
  'com.fluttercandies/photo_manager_video_player',
);

AssetEntity _video(String id) => AssetEntity(
      id: id,
      typeInt: AssetType.video.index,
      width: 1920,
      height: 1080,
      duration: 12,
    );

/// The cleanup latch is per-isolate, and `flutter test` gives every file its
/// own isolate — so these assertions need this file to themselves.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<String> methods = <String>[];

  setUp(() {
    methods.clear();
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (MethodCall call) async {
      methods.add(call.method);
      return call.method == 'create' ? 1 : null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel(
        'com.fluttercandies/photo_manager_video_player/events/1',
      ),
      (MethodCall call) async => null,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      messenger.setMockMethodCallHandler(
        const MethodChannel(
          'com.fluttercandies/photo_manager_video_player/events/1',
        ),
        null,
      );
    });
  });

  test('the first create clears players left by the previous isolate',
      () async {
    final AssetEntityVideoController controller = AssetEntityVideoController(
      _video('1'),
    );
    unawaited(controller.initialize());
    await Future<void>.delayed(Duration.zero);

    expect(methods.take(2), <String>['disposeAll', 'create']);
    controller.dispose();
  });

  test('later players do not clear the ones already playing', () async {
    final AssetEntityVideoController first = AssetEntityVideoController(
      _video('1'),
    );
    unawaited(first.initialize());
    await Future<void>.delayed(Duration.zero);
    methods.clear();

    final AssetEntityVideoController second = AssetEntityVideoController(
      _video('2'),
    );
    unawaited(second.initialize());
    await Future<void>.delayed(Duration.zero);

    expect(methods, isNot(contains('disposeAll')));
    first.dispose();
    second.dispose();
  });
}
