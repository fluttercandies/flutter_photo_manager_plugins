import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_native_image/photo_manager_native_image.dart';

import 'fake_channel.dart';

void main() {
  test('same id, date, size and type are equal', () {
    final NativeImageProvider a =
        NativeImageProvider(entity(modifiedDate: 10), size: 320);
    final NativeImageProvider b =
        NativeImageProvider(entity(modifiedDate: 10), size: 320);
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });

  test('size is part of the key', () {
    expect(
      NativeImageProvider(entity(), size: 128),
      isNot(equals(NativeImageProvider(entity(), size: 320))),
    );
  });

  test('modified date is part of the key', () {
    expect(
      NativeImageProvider(entity(modifiedDate: 1), size: 320),
      isNot(equals(NativeImageProvider(entity(modifiedDate: 2), size: 320))),
    );
  });

  test('create date is used when modified date is missing', () {
    final NativeImageProvider a =
        NativeImageProvider(entity(createDate: 5), size: 320);
    expect(a, equals(NativeImageProvider(entity(createDate: 5), size: 320)));
    expect(
      a,
      isNot(equals(NativeImageProvider(entity(createDate: 6), size: 320))),
    );
  });

  test('video and image with the same id differ', () {
    expect(
      NativeImageProvider(entity(type: AssetType.video), size: 320),
      isNot(equals(NativeImageProvider(entity(), size: 320))),
    );
  });
}
