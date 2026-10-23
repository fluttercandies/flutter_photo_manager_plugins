// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/native_image_api.g.dart',
    swiftOut:
        'darwin/photo_manager_native_image/Sources/photo_manager_native_image/NativeImageApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'NativeImageError'),
    kotlinOut:
        'android/src/main/kotlin/com/fluttercandies/photo_manager_native_image/NativeImageApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.fluttercandies.photo_manager_native_image',
      errorClassName: 'NativeImageError',
    ),
    dartPackageName: 'photo_manager_native_image',
  ),
)
@HostApi()
abstract class NativeImageHostApi {
  /// Decodes the asset to a premultiplied RGBA8888 buffer allocated with
  /// `malloc`. The shorter side of the result is [width]/[height] (aspect
  /// fill). Returns `{pointer, width, height, rowBytes}`, or `null` when the
  /// request was cancelled before a buffer was allocated.
  ///
  /// Once a buffer is allocated the host always replies with it, even if a
  /// cancel arrived meanwhile: the Dart side owns the buffer and frees it.
  ///
  /// Errors use the codes `not_found`, `icloud_not_downloaded`, and
  /// `decode_failed`.
  @async
  Map<String, int>? requestImage(
    String assetId,
    int requestId,
    int width,
    int height,
    bool isVideo,
    bool allowNetwork,
  );

  /// Stops [requestId] if it has not allocated a buffer yet. A cancel that
  /// arrives before its request is remembered and applied when it does.
  void cancelRequest(int requestId);
}
