import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager_native_image/photo_manager_native_image.dart';
import 'package:photo_manager_native_image/src/native_image_metrics.dart';
import 'package:photo_manager_native_image/src/native_image_request.dart';

import 'fake_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeChannel channel;
  late int frees;
  late NativeImageMetrics metrics;

  NativeImageRequest request({int size = 64}) {
    return NativeImageRequest(
      channel: channel,
      assetId: 'a',
      size: size,
      isVideo: false,
      free: (Pointer<Uint8> p) {
        frees++;
        malloc.free(p);
      },
      metrics: metrics,
    );
  }

  setUp(() {
    channel = FakeChannel();
    frees = 0;
    metrics = NativeImageMetrics.instance..reset();
  });

  test('normal reply: buffer freed once, frame produced', () async {
    final NativeImageRequest r = request();
    final Future<ui.FrameInfo?> future = r.load();
    channel.reply(r.requestId, allocateBuffer(40, 30));
    final ui.FrameInfo? frame = await future;
    expect(frame, isNotNull);
    expect(frame!.image.width, 40);
    expect(frame.image.height, 30);
    expect(frees, 1);
    expect(metrics.liveBuffers, 0);
    expect(metrics.completed, 1);
    frame.image.dispose();
  });

  test('padded rows are honoured', () async {
    final NativeImageRequest r = request();
    final Future<ui.FrameInfo?> future = r.load();
    channel.reply(r.requestId, allocateBuffer(10, 10, padding: 24));
    final ui.FrameInfo? frame = await future;
    expect(frame!.image.width, 10);
    expect(frees, 1);
    frame.image.dispose();
  });

  test('cancel before send never reaches the platform', () async {
    final NativeImageRequest r = request();
    r.cancel();
    expect(await r.load(), isNull);
    expect(channel.requested, isEmpty);
    expect(channel.cancelled, isEmpty);
  });

  test('cancel after send is forwarded once', () async {
    final NativeImageRequest r = request();
    final Future<ui.FrameInfo?> future = r.load();
    r.cancel();
    r.cancel();
    expect(channel.cancelled, <int>[r.requestId]);
    channel.reply(r.requestId, null);
    expect(await future, isNull);
    expect(frees, 0);
    expect(metrics.cancelled, 1);
  });

  test('a buffer that arrives after cancel is still freed exactly once',
      () async {
    final NativeImageRequest r = request();
    final Future<ui.FrameInfo?> future = r.load();
    r.cancel();
    channel.reply(r.requestId, allocateBuffer(8, 8));
    expect(await future, isNull);
    expect(frees, 1);
    expect(metrics.liveBuffers, 0);
  });

  test('cancel after settle is ignored', () async {
    final NativeImageRequest r = request();
    final Future<ui.FrameInfo?> future = r.load();
    channel.reply(r.requestId, allocateBuffer(8, 8));
    (await future)!.image.dispose();
    r.cancel();
    expect(channel.cancelled, isEmpty);
    expect(r.isSettled, isTrue);
  });

  test('oversized reply is scaled so the shorter side matches size', () async {
    final NativeImageRequest r = request(size: 16);
    final Future<ui.FrameInfo?> future = r.load();
    channel.reply(r.requestId, allocateBuffer(64, 32));
    final ui.FrameInfo? frame = await future;
    expect(frame!.image.width, 32);
    expect(frame.image.height, 16);
    frame.image.dispose();
  });

  test('platform errors map to typed codes', () async {
    for (final (String wire, NativeImageErrorCode code)
        in <(String, NativeImageErrorCode)>[
      ('not_found', NativeImageErrorCode.notFound),
      ('icloud_not_downloaded', NativeImageErrorCode.icloudNotDownloaded),
      ('decode_failed', NativeImageErrorCode.decodeFailed),
      ('something_else', NativeImageErrorCode.decodeFailed),
    ]) {
      final NativeImageRequest r = request();
      final Future<ui.FrameInfo?> future = r.load();
      channel.fail(r.requestId, wire);
      if (wire == 'icloud_not_downloaded') {
        // The local miss is followed by one network attempt; fail that too.
        await Future<void>.delayed(Duration.zero);
        channel.fail(r.requestId, wire);
      }
      await expectLater(
        future,
        throwsA(
          isA<NativeImageException>().having((e) => e.code, 'code', code),
        ),
      );
    }
    expect(metrics.failed, 4);
    expect(metrics.inFlight, 0);
  });

  test('load twice is rejected', () async {
    final NativeImageRequest r = request();
    final Future<ui.FrameInfo?> first = r.load();
    expect(r.load, throwsStateError);
    channel.reply(r.requestId, null);
    await first;
  });

  group('iCloud fallback', () {
    test('icloud miss triggers one network attempt with a new id', () async {
      final NativeImageRequest r = request();
      final Future<ui.FrameInfo?> future = r.load();
      final int first = r.requestId;
      channel.fail(first, 'icloud_not_downloaded');
      await Future<void>.delayed(Duration.zero);
      expect(channel.requested, hasLength(2));
      final int second = channel.requested.last;
      expect(second, isNot(first));
      expect(r.requestId, second);
      expect(channel.networkOf[first], isFalse);
      expect(channel.networkOf[second], isTrue);
      channel.reply(second, allocateBuffer(4, 4));
      final ui.FrameInfo? frame = await future;
      expect(frame, isNotNull);
      frame!.image.dispose();
      expect(metrics.fallbacks, 1);
      expect(metrics.failed, 0);
      expect(metrics.completed, 1);
      expect(metrics.liveBuffers, 0);
    });

    test('the second failure is reported with its own code', () async {
      final NativeImageRequest r = request();
      final Future<ui.FrameInfo?> future = r.load();
      channel.fail(r.requestId, 'icloud_not_downloaded');
      await Future<void>.delayed(Duration.zero);
      channel.fail(channel.requested.last, 'decode_failed');
      await expectLater(
        future,
        throwsA(
          isA<NativeImageException>().having(
            (e) => e.code,
            'code',
            NativeImageErrorCode.decodeFailed,
          ),
        ),
      );
      expect(channel.requested, hasLength(2));
      expect(metrics.failed, 1);
    });

    test('a non-icloud first failure is not retried', () async {
      final NativeImageRequest r = request();
      final Future<ui.FrameInfo?> future = r.load();
      channel.fail(r.requestId, 'not_found');
      await expectLater(future, throwsA(isA<NativeImageException>()));
      expect(channel.requested, hasLength(1));
    });

    test('cancel between attempts stops the second one', () async {
      final NativeImageRequest r = request();
      final Future<ui.FrameInfo?> future = r.load();
      final int first = r.requestId;
      // Cancel arrives after the platform replied but before Dart handles it.
      r.cancel();
      channel.fail(first, 'icloud_not_downloaded');
      expect(await future, isNull);
      expect(channel.requested, <int>[first]);
      expect(channel.cancelled, <int>[first]);
      expect(metrics.fallbacks, 0);
    });

    test('cancel during the second attempt targets its id', () async {
      final NativeImageRequest r = request();
      final Future<ui.FrameInfo?> future = r.load();
      channel.fail(r.requestId, 'icloud_not_downloaded');
      await Future<void>.delayed(Duration.zero);
      final int second = channel.requested.last;
      r.cancel();
      expect(channel.cancelled, <int>[second]);
      channel.reply(second, null);
      expect(await future, isNull);
    });
  });

  group('resizeTargetFor', () {
    test('returns null when already within size', () {
      expect(resizeTargetFor(300, 200, 320), isNull);
      expect(resizeTargetFor(320, 320, 320), isNull);
    });

    test('scales the shorter side to size', () {
      expect(resizeTargetFor(640, 480, 320), (width: 427, height: 320));
      expect(resizeTargetFor(480, 640, 320), (width: 320, height: 427));
    });

    test('caps panoramas at four size squares', () {
      expect(resizeTargetFor(8000, 1000, 1024), (width: 5793, height: 724));
      expect(resizeTargetFor(4000, 1000, 160), (width: 640, height: 160));
      expect(resizeTargetFor(1280, 320, 320), isNull);
    });
  });
}
