// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

// Runs against the real platform players. The sample clips are added to the
// device library on first run; grant photo access before running.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_video_player/photo_manager_video_player.dart';

/// A sample clip from `integration_test/assets`, added to the library once.
Future<AssetEntity> _clip(String name) async {
  final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
    type: RequestType.video,
    onlyAll: true,
    // API 28 builds an empty ORDER BY without an explicit order.
    filterOption: FilterOptionGroup(orders: <OrderOption>[const OrderOption()]),
  );
  final int count = paths.isEmpty ? 0 : await paths.first.assetCountAsync;
  if (count > 0) {
    final List<AssetEntity> all =
        await paths.first.getAssetListRange(start: 0, end: count);
    for (final AssetEntity asset in all) {
      if ((await asset.titleAsync).startsWith(name)) {
        return asset;
      }
    }
  }
  final ByteData data =
      await rootBundle.load('integration_test/assets/$name.mp4');
  final File file = File('${Directory.systemTemp.path}/$name.mp4')
    ..writeAsBytesSync(data.buffer.asUint8List());
  return PhotoManager.editor.saveVideo(file, title: '$name.mp4');
}

Future<void> _until(
  AssetEntityVideoController controller,
  bool Function(AssetEntityVideoValue value) done, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!done(controller.value)) {
    if (watch.elapsed > timeout) {
      fail('Timed out; last value: ${controller.value}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// 'R' or 'B' for the dominant colour at a relative position of [image].
Future<String> _colourAt(ui.Image image, double fx, double fy) async {
  final ByteData bytes =
      (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final int x = ((image.width - 1) * fx).round();
  final int y = ((image.height - 1) * fy).round();
  final int o = (y * image.width + x) * 4;
  return bytes.getUint8(o) > bytes.getUint8(o + 2) ? 'R' : 'B';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final PermissionState state = await PhotoManager.requestPermissionExtend();
    expect(state.hasAccess, isTrue, reason: 'Grant photo access first.');
  });

  testWidgets('seeking while paused moves the position and keeps it paused',
      (WidgetTester tester) async {
    final AssetEntityVideoController controller =
        AssetEntityVideoController(await _clip('pmvp_short'));
    await controller.initialize();
    expect(controller.value.hasError, isFalse, reason: '${controller.value}');

    await controller.seekTo(const Duration(milliseconds: 1500));
    await _until(
      controller,
      (AssetEntityVideoValue v) => v.position.inMilliseconds == 1500,
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(controller.value.isPlaying, isFalse);
    expect(controller.value.position, const Duration(milliseconds: 1500));

    await controller.seekTo(const Duration(seconds: 60));
    await _until(
        controller, (AssetEntityVideoValue v) => v.position == v.duration);
    await controller.dispose();
  });

  testWidgets('a paused seek shows the frame at the requested time',
      (WidgetTester tester) async {
    // One keyframe at 0; 1.5–2 s is white and 2–2.5 s is black.
    final AssetEntityVideoController controller =
        AssetEntityVideoController(await _clip('pmvp_seek'));
    await controller.initialize();
    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 160,
            height: 120,
            child: AssetEntityVideoView(controller),
          ),
        ),
      ),
    );
    await _until(controller, (AssetEntityVideoValue v) => v.firstFrameRendered);
    Future<int> centreGreen() async {
      await tester.pump(const Duration(milliseconds: 100));
      final ui.Image image = await (key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      final ByteData bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final int o = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
      return bytes.getUint8(o + 1);
    }

    for (final (int ms, int expected) in <(int, int)>[(1700, 255), (2200, 0)]) {
      await controller.seekTo(Duration(milliseconds: ms));
      // Decoding from the only keyframe can be slow on CI emulators; a wrong
      // frame never matches, so wait for the right one with a bound.
      final Stopwatch waited = Stopwatch()..start();
      int green = await centreGreen();
      while ((green - expected).abs() > 30 && waited.elapsed.inSeconds < 5) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        green = await centreGreen();
      }
      expect(green, closeTo(expected, 30), reason: 'green channel at $ms ms');
    }
    await tester.pumpWidget(const SizedBox());
    await controller.dispose();
  });

  testWidgets('a missing asset fails fast with assetNotFound',
      (WidgetTester tester) async {
    final AssetEntityVideoController controller = AssetEntityVideoController(
      AssetEntity(
        id: Platform.isAndroid
            ? '987654321'
            : 'DEADBEEF-0000-0000-0000-000000000000/L0/001',
        typeInt: AssetType.video.index,
        width: 100,
        height: 100,
        duration: 3,
      ),
    );
    final Stopwatch watch = Stopwatch()..start();
    await controller.initialize();
    expect(
        controller.value.error?.code, AssetEntityVideoErrorCode.assetNotFound);
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    await controller.dispose();
  });

  testWidgets('a muted player does not pause an audible one',
      (WidgetTester tester) async {
    final AssetEntityVideoController audible =
        AssetEntityVideoController(await _clip('pmvp_short'));
    final AssetEntityVideoController muted =
        AssetEntityVideoController(await _clip('pmvp_split_rot90'));
    await audible.initialize();
    await muted.initialize();
    await audible.setLooping(true);
    await muted.setLooping(true);
    await muted.setVolume(0);
    await audible.play();
    await _until(audible, (AssetEntityVideoValue v) => v.isPlaying);
    await muted.play();
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(audible.value.isPlaying, isTrue);
    expect(muted.value.isPlaying, isTrue);
    await audible.dispose();
    await muted.dispose();
  });

  testWidgets('initialize and dispose can be repeated without leaks or errors',
      (WidgetTester tester) async {
    final AssetEntity clip = await _clip('pmvp_short');
    for (int i = 0; i < 10; i++) {
      final AssetEntityVideoController controller =
          AssetEntityVideoController(clip);
      // Every other round disposes before the player has reported anything.
      if (i.isEven) {
        await controller.initialize();
        expect(controller.value.isInitialized, isTrue, reason: 'round $i');
        expect(controller.value.hasError, isFalse, reason: 'round $i');
      } else {
        controller.initialize();
      }
      await controller.dispose();
    }
  });

  testWidgets('looping keeps playing across the end of the clip',
      (WidgetTester tester) async {
    final AssetEntityVideoController controller =
        AssetEntityVideoController(await _clip('pmvp_short'));
    await controller.initialize();
    await controller.setLooping(true);
    await controller.play();
    await _until(controller, (AssetEntityVideoValue v) => v.isPlaying);

    final List<bool> playing = <bool>[];
    void record() => playing.add(controller.value.isPlaying);
    controller.addListener(record);
    await Future<void>.delayed(const Duration(milliseconds: 7000));
    controller.removeListener(record);

    expect(playing, isNot(contains(false)));
    expect(controller.value.isCompleted, isFalse);
    await controller.dispose();
  });

  // Both clips are encoded red over blue; their rotation metadata turns them
  // upright as red | blue (90°) and blue over red (180°).
  for (final (String name, String expected) in <(String, String)>[
    ('pmvp_split_rot90', 'RB'),
    ('pmvp_split_rot180', 'BR'),
  ]) {
    testWidgets('$name is drawn upright', (WidgetTester tester) async {
      final AssetEntityVideoController controller =
          AssetEntityVideoController(await _clip(name));
      await controller.initialize();
      // Shows which texture path ran: 0 when the platform already rotated
      // the frames, the clip's rotation when Dart applies it.
      debugPrint(
          '$name rotationCorrection=${controller.value.rotationCorrection}');
      final GlobalKey key = GlobalKey();
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: AssetEntityVideoView(controller),
            ),
          ),
        ),
      );
      await _until(
          controller, (AssetEntityVideoValue v) => v.firstFrameRendered);
      await tester.pump(const Duration(milliseconds: 300));

      final RenderRepaintBoundary boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage();
      final bool portrait = name.endsWith('rot90');
      final String seen = portrait
          ? '${await _colourAt(image, 0.25, 0.5)}${await _colourAt(image, 0.75, 0.5)}'
          : '${await _colourAt(image, 0.5, 0.25)}${await _colourAt(image, 0.5, 0.75)}';
      expect(
        seen,
        expected,
        reason: '${controller.value}; image ${image.width}x${image.height}',
      );
      await controller.dispose();
    });
  }
}
