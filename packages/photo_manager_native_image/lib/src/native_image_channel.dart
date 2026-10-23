// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'native_image_api.g.dart';

/// The platform surface used by [NativeImageProvider]. Tests substitute a
/// fake; production uses the Pigeon-generated [NativeImageHostApi].
abstract class NativeImageChannel {
  /// Creates a channel.
  const NativeImageChannel();

  /// The channel used when a provider is not given one.
  static NativeImageChannel instance = const PigeonNativeImageChannel();

  static int _nextRequestId = 0;

  /// Hands out request ids unique within this isolate.
  static int allocateRequestId() => ++_nextRequestId;

  /// See [NativeImageHostApi.requestImage].
  Future<Map<String, int>?> requestImage({
    required String assetId,
    required int requestId,
    required int width,
    required int height,
    required bool isVideo,
    required bool allowNetwork,
  });

  /// See [NativeImageHostApi.cancelRequest].
  Future<void> cancelRequest(int requestId);
}

/// [NativeImageChannel] backed by the Pigeon host API.
class PigeonNativeImageChannel extends NativeImageChannel {
  /// Creates the production channel.
  const PigeonNativeImageChannel();

  static final NativeImageHostApi _api = NativeImageHostApi();

  @override
  Future<Map<String, int>?> requestImage({
    required String assetId,
    required int requestId,
    required int width,
    required int height,
    required bool isVideo,
    required bool allowNetwork,
  }) {
    return _api.requestImage(
      assetId,
      requestId,
      width,
      height,
      isVideo,
      allowNetwork,
    );
  }

  @override
  Future<void> cancelRequest(int requestId) => _api.cancelRequest(requestId);
}
