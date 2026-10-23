import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager_native_image/src/native_image_metrics.dart';

void main() {
  test('counter changes notify after the current synchronous work', () async {
    final NativeImageMetrics metrics = NativeImageMetrics.instance..reset();
    await Future<void>.delayed(Duration.zero);
    int notifications = 0;
    metrics.addListener(() => notifications++);

    // loadImage() runs during build; a synchronous notification there would
    // let a listener call setState() mid-build.
    metrics.markRequested();
    metrics.markRequested();
    expect(notifications, 0);
    expect(metrics.requested, 2);

    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);
  });
}
