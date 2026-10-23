import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('asynchronous decode errors run provider error cleanup', () async {
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.presentError;
    FlutterError.presentError = reports.add;
    addTearDown(() => FlutterError.presentError = previous);
    final provider = AssetEntityImageProvider(_ImageAsset(), isOriginal: false);
    final expected = StateError('asynchronous decode failure');
    final received = Completer<Object>();
    final stream = provider.loadImage(
      provider,
      (
        ui.ImmutableBuffer buffer, {
        ui.TargetImageSizeCallback? getTargetSize,
      }) async {
        buffer.dispose();
        await Future<void>.delayed(Duration.zero);
        throw expected;
      },
    );
    final listener = ImageStreamListener(
      (ImageInfo image, bool synchronousCall) => fail('Unexpected image'),
      onError: (Object error, StackTrace? stack) => received.complete(error),
    );
    stream.addListener(listener);
    addTearDown(() => stream.removeListener(listener));
    expect(
      await received.future.timeout(const Duration(seconds: 5)),
      same(expected),
    );
    expect(
      reports.where((details) => details.library == 'photo_manager'),
      hasLength(1),
    );
    expect(reports.single.exception, same(expected));
  });
}

class _ImageAsset extends AssetEntity {
  _ImageAsset()
      : super(
          id: 'decode-error-test',
          typeInt: 1,
          width: 1,
          height: 1,
          title: 'test.jpg',
        );

  @override
  Future<Uint8List?> thumbnailDataWithOption(
    ThumbnailOption option, {
    PMProgressHandler? progressHandler,
    dynamic cancelToken,
  }) async =>
      Uint8List.fromList(<int>[0]);
}
