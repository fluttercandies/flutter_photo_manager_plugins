// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';

/// Draws [entity] through a native view so a gain map (Apple HDR HEIC,
/// Ultra HDR JPEG) is applied on HDR-capable displays.
///
/// The view stays transparent unless the decoded image carries HDR data —
/// on unsupported OS versions, for SDR photos, and on any failure. Put it
/// above a regular image (e.g. [NativeAssetImage]) so that one shows
/// otherwise. Fills its box like [BoxFit.cover]. Never takes pointer events.
///
/// iOS 17+: `UIImageView(preferredImageDynamicRange: .high)`.
/// Android 14+: `ImageView` in a Hybrid Composition platform view; the
/// activity window must be in `ActivityInfo.COLOR_MODE_HDR` for HDR output.
/// The plugin never changes the window color mode; that is the app's call.
class NativeAssetHdrView extends StatelessWidget {
  /// Creates a view that draws [entity] with its gain map, decoded to [size].
  const NativeAssetHdrView(this.entity, {super.key, required this.size})
      : assert(size > 0);

  /// The image to draw. Must be an [AssetType.image].
  final AssetEntity entity;

  /// Target pixel length of the shorter side to decode (aspect fill). Android
  /// samples by powers of two, so its shorter side lands between `size` and
  /// twice `size`.
  final int size;

  /// Platform view type registered by the native plugin code.
  static const String viewType = 'photo_manager_native_image/hdr_view';

  @override
  Widget build(BuildContext context) {
    assert(entity.type == AssetType.image,
        'NativeAssetHdrView draws images only.');
    final Map<String, Object?> params = <String, Object?>{
      'assetId': entity.id,
      'size': size,
    };
    final Widget platformView;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        platformView = UiKitView(
          viewType: viewType,
          creationParams: params,
          creationParamsCodec: const StandardMessageCodec(),
        );
      case TargetPlatform.android:
        platformView = PlatformViewLink(
          viewType: viewType,
          surfaceFactory: (
            BuildContext context,
            PlatformViewController controller,
          ) {
            return AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers: const <Factory<
                  OneSequenceGestureRecognizer>>{},
              hitTestBehavior: PlatformViewHitTestBehavior.transparent,
            );
          },
          onCreatePlatformView: (PlatformViewCreationParams createParams) {
            return PlatformViewsService.initExpensiveAndroidView(
              id: createParams.id,
              viewType: viewType,
              layoutDirection:
                  Directionality.maybeOf(context) ?? TextDirection.ltr,
              creationParams: params,
              creationParamsCodec: const StandardMessageCodec(),
              onFocus: () => createParams.onFocusChanged(true),
            )
              ..addOnPlatformViewCreatedListener(
                createParams.onPlatformViewCreated,
              )
              ..create();
          },
        );
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        platformView = const SizedBox.expand();
    }
    return IgnorePointer(
      child: KeyedSubtree(
        key: ValueKey<(String, int, int)>(
          (entity.id, entity.modifiedDateSecond ?? 0, size),
        ),
        child: platformView,
      ),
    );
  }
}
