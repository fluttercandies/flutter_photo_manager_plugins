// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_video_player/photo_manager_video_player.dart';

const String _name = 'com.fluttercandies/photo_manager_video_player';
const MethodChannel _channel = MethodChannel(_name);

AssetEntity _video() => AssetEntity(
      id: '1',
      typeInt: AssetType.video.index,
      width: 1920,
      height: 1080,
      duration: 6,
    );

/// Answers `create` with player [id] and replays [events] once Dart listens.
/// Returns the `create` calls.
List<MethodCall> _mockPlatform(
  List<Map<String, Object?>> events, {
  int id = 1,
}) {
  final List<MethodCall> creates = <MethodCall>[];
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final String eventChannel = '$_name/events/$id';

  messenger.setMockMethodCallHandler(_channel, (MethodCall call) async {
    if (call.method != 'create') {
      return null;
    }
    creates.add(call);
    return id;
  });
  messenger.setMockMethodCallHandler(MethodChannel(eventChannel), (
    MethodCall call,
  ) async {
    if (call.method != 'listen') {
      return null;
    }
    for (final Map<String, Object?> event in events) {
      await messenger.handlePlatformMessage(
        eventChannel,
        const StandardMethodCodec().encodeSuccessEnvelope(event),
        null,
      );
    }
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    messenger.setMockMethodCallHandler(MethodChannel(eventChannel), null);
  });
  return creates;
}

Future<AssetEntityVideoController> _ready(
  List<Map<String, Object?>> events,
) async {
  _mockPlatform(<Map<String, Object?>>[
    <String, Object?>{'event': 'initialized', 'durationMs': 6000},
    ...events,
  ]);
  final AssetEntityVideoController controller = AssetEntityVideoController(
    _video(),
  );
  await controller.initialize();
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('nothing is drawn before the platform player exists', (
    WidgetTester tester,
  ) async {
    _mockPlatform(const <Map<String, Object?>>[]);
    final AssetEntityVideoController controller = AssetEntityVideoController(
      _video(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(AssetEntityVideoView(controller));

    expect(find.byType(Texture), findsNothing);
  });

  testWidgets('an upright track is drawn without a quarter turn', (
    WidgetTester tester,
  ) async {
    final AssetEntityVideoController controller = await _ready(
      <Map<String, Object?>>[
        <String, Object?>{
          'event': 'videoSize',
          'width': 1920,
          'height': 1080,
          'rotationDegrees': 0,
        },
      ],
    );

    await tester.pumpWidget(AssetEntityVideoView(controller));

    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 0);
  });

  testWidgets('a quarter-turned track is rotated back upright', (
    WidgetTester tester,
  ) async {
    final AssetEntityVideoController controller = await _ready(
      <Map<String, Object?>>[
        <String, Object?>{
          'event': 'videoSize',
          'width': 1080,
          'height': 1920,
          'rotationDegrees': 90,
        },
      ],
    );

    await tester.pumpWidget(AssetEntityVideoView(controller));

    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 1);
    expect(controller.value.size, const Size(1080, 1920));
  });

  group('platformView', () {
    const Map<String, Object?> quarterTurned = <String, Object?>{
      'event': 'videoSize',
      'width': 1080,
      'height': 1920,
      'rotationDegrees': 90,
    };

    Future<(AssetEntityVideoController, List<MethodCall>)> ready() async {
      final List<MethodCall> creates = _mockPlatform(
        <Map<String, Object?>>[
          <String, Object?>{'event': 'initialized', 'durationMs': 6000},
          quarterTurned,
        ],
        id: -1,
      );
      final AssetEntityVideoController controller = AssetEntityVideoController(
        _video(),
        viewType: AssetEntityVideoViewType.platformView,
      );
      await controller.initialize();
      addTearDown(controller.dispose);
      return (controller, creates);
    }

    testWidgets('Android shows a SurfaceView without a Dart rotation', (
      WidgetTester tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final (AssetEntityVideoController controller, List<MethodCall> creates) =
          await ready();

      await tester.pumpWidget(AssetEntityVideoView(controller));

      expect(
        (creates.single.arguments as Map<Object?, Object?>)['viewType'],
        'platformView',
      );
      expect(controller.usesPlatformView, isTrue);
      expect(controller.textureId, isNull);
      final PlatformViewLink link =
          tester.widget<PlatformViewLink>(find.byType(PlatformViewLink));
      expect(link.viewType, '$_name/view');
      expect(find.byType(Texture), findsNothing);
      expect(find.byType(RotatedBox), findsNothing);
      expect(controller.value.size, const Size(1080, 1920));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('other platforms keep the texture', (
      WidgetTester tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final (AssetEntityVideoController controller, List<MethodCall> creates) =
          await ready();

      await tester.pumpWidget(AssetEntityVideoView(controller));

      expect(
        (creates.single.arguments as Map<Object?, Object?>)
            .containsKey('viewType'),
        isFalse,
      );
      expect(controller.usesPlatformView, isFalse);
      expect(controller.textureId, -1);
      expect(find.byType(PlatformViewLink), findsNothing);
      expect(find.byType(Texture), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  test('the texture stays the default', () {
    final AssetEntityVideoController controller = AssetEntityVideoController(
      _video(),
    );
    addTearDown(controller.dispose);
    expect(controller.viewType, AssetEntityVideoViewType.textureView);
  });
}
