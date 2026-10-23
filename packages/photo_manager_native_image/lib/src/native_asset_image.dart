// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';

import 'native_image_provider.dart';

/// An [Image] backed by a [NativeImageProvider], shaped like
/// `AssetEntityImage` from photo_manager_image_provider.
class NativeAssetImage extends Image {
  /// Shows [entity] decoded at [size] pixels on its shorter side.
  NativeAssetImage(
    AssetEntity entity, {
    required int size,
    super.key,
    super.frameBuilder,
    super.loadingBuilder,
    super.errorBuilder,
    super.semanticLabel,
    super.excludeFromSemantics,
    super.width,
    super.height,
    super.color,
    super.opacity,
    super.colorBlendMode,
    super.fit,
    super.alignment,
    super.repeat,
    super.centerSlice,
    super.matchTextDirection,
    super.gaplessPlayback,
    super.isAntiAlias,
    super.filterQuality = FilterQuality.low,
  }) : super(image: NativeImageProvider(entity, size: size));
}
