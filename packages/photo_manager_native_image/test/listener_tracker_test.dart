import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager_native_image/src/cache_aware_listener_tracker.dart';

class TrackedCompleter extends ImageStreamCompleter
    with CacheAwareListenerTracker {
  int cancels = 0;

  @override
  void onCancelRequested() => cancels++;
}

ImageStreamListener listener() => ImageStreamListener((_, __) {});

Future<ui.Image> makeImage() async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint());
  return recorder.endRecording().toImage(2, 2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cancels once when only the cache listener remains', () {
    final TrackedCompleter completer = TrackedCompleter();
    final ImageStreamListener cache = listener();
    final ImageStreamListener widget = listener();
    completer.addListener(cache);
    completer.addListener(widget);
    completer.removeListener(widget);
    expect(completer.cancels, 1);
    completer.removeListener(cache);
    expect(completer.cancels, 1);
  });

  test('imageCache.clear() detaching the cache listener does not cancel', () {
    final TrackedCompleter completer = TrackedCompleter();
    final ImageStreamListener cache = listener();
    final ImageStreamListener widget = listener();
    completer.addListener(cache);
    completer.addListener(widget);
    completer.removeListener(cache);
    expect(completer.cancels, 0);
    completer.removeListener(widget);
    expect(completer.cancels, 1);
  });

  test('a cache listener detached synchronously is not a false cancel',
      () async {
    final TrackedCompleter fresh = TrackedCompleter();
    final ImageStreamCompleterHandle handle = fresh.keepAlive();
    fresh.setImage(ImageInfo(image: await makeImage()));
    late ImageStreamListener cache;
    cache = ImageStreamListener((_, bool sync) {
      if (sync) {
        fresh.removeListener(cache);
      }
    });
    fresh.addListener(cache);
    expect(fresh.cancels, 0);
    expect(fresh.widgetListenerCount, 0);
    final ImageStreamListener widget = listener();
    fresh.addListener(widget);
    fresh.removeListener(widget);
    expect(fresh.cancels, 0);
    handle.dispose();
  });

  test(
      'a widget listener added after the cache left is not mistaken '
      'for the cache listener', () {
    final TrackedCompleter completer = TrackedCompleter();
    final ImageStreamListener cache = listener();
    final ImageStreamListener a = listener();
    completer.addListener(cache);
    completer.addListener(a);
    completer.removeListener(cache);
    final ImageStreamListener b = listener();
    completer.addListener(b);
    expect(completer.widgetListenerCount, 2);
    completer.removeListener(a);
    expect(completer.cancels, 0);
    completer.removeListener(b);
    expect(completer.cancels, 1);
  });

  test('no cancel once an image has arrived', () async {
    final TrackedCompleter completer = TrackedCompleter();
    final ImageStreamListener cache = listener();
    final ImageStreamListener widget = listener();
    completer.addListener(cache);
    completer.addListener(widget);
    completer.setImage(ImageInfo(image: await makeImage()));
    completer.removeListener(widget);
    completer.removeListener(cache);
    expect(completer.cancels, 0);
  });
}
