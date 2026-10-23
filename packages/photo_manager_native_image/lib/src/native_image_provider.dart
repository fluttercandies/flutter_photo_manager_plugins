// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:photo_manager/photo_manager.dart';

import 'native_image_channel.dart';
import 'native_image_request.dart';
import 'native_image_stream_completer.dart';

/// Loads an [AssetEntity] thumbnail decoded natively to RGBA.
///
/// [size] is the pixel length of the shorter side (aspect fill); which sizes an
/// app uses, and how many, is the app's policy. The cache key is
/// `(entity.id, modified date, size, isVideo)`, so an edited asset reloads.
///
/// iOS: an asset that is only in iCloud is tried locally first; if PhotoKit
/// needs the network for this size, one download follows on a low-priority
/// queue.
class NativeImageProvider extends ImageProvider<NativeImageProvider> {
  /// Creates a provider for [entity] at [size] pixels.
  NativeImageProvider(
    this.entity, {
    required this.size,
  }) : assert(size > 0);

  /// The asset to load.
  final AssetEntity entity;

  /// Pixel length of the shorter side of the decoded image.
  final int size;

  int get _modifiedDateSecond =>
      entity.modifiedDateSecond ?? entity.createDateSecond ?? 0;

  bool get _isVideo => entity.type == AssetType.video;

  @override
  Future<NativeImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<NativeImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    NativeImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final NativeImageRequest request = NativeImageRequest(
      channel: NativeImageChannel.instance,
      assetId: entity.id,
      size: size,
      isVideo: _isVideo,
    );
    return NativeImageStreamCompleter(
      load: request.load,
      onCancel: () {
        request.cancel();
        PaintingBinding.instance.imageCache.evict(key);
      },
      // Like NetworkImage: a failed key must not be served from the pending
      // cache, so the next resolve of the same asset starts a new load.
      onFailure: () => PaintingBinding.instance.imageCache.evict(key),
      debugLabel: '${entity.id}@$size',
    );
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is NativeImageProvider &&
        other.entity.id == entity.id &&
        other._modifiedDateSecond == _modifiedDateSecond &&
        other.size == size &&
        other._isVideo == _isVideo;
  }

  @override
  int get hashCode =>
      Object.hash(entity.id, _modifiedDateSecond, size, _isVideo);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'NativeImageProvider')}(${entity.id}, size: $size)';
}
