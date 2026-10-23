// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'platform_bridge.dart';
import 'value.dart';

/// Renders a controller's video, filling the space it's given.
///
/// Wrap it in an `AspectRatio(aspectRatio: controller.value.aspectRatio)` to
/// letterbox. With [AssetEntityVideoViewType.textureView] the frames arrive as a
/// Flutter texture, so this composites like any other widget — opacity,
/// transforms and scrolling all behave normally. See
/// [AssetEntityVideoViewType.platformView] for the Android alternative.
class AssetEntityVideoView extends StatelessWidget {
  /// Renders [controller].
  const AssetEntityVideoView(this.controller, {super.key});

  /// The controller whose video is shown.
  final AssetEntityVideoController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AssetEntityVideoValue>(
      valueListenable: controller,
      builder: (BuildContext context, AssetEntityVideoValue value, _) {
        final int? playerId = playerIdOf(controller);
        if (playerId == null || value.hasError) {
          return const SizedBox.expand();
        }
        if (controller.usesPlatformView) {
          // The decoder already rotated the frames, so no RotatedBox here.
          return _PlatformVideoView(playerId: playerId);
        }
        final int textureId = playerId;
        return RotatedBox(
          quarterTurns: value.rotationCorrection ~/ 90,
          child: Texture(textureId: textureId),
        );
      },
    );
  }
}

class _PlatformVideoView extends StatelessWidget {
  const _PlatformVideoView({required this.playerId});

  final int playerId;

  @override
  Widget build(BuildContext context) {
    // IgnorePointer leaves gestures to the Flutter widgets above the video.
    return IgnorePointer(
      child: PlatformViewLink(
        // A new player needs a new SurfaceView bound to it.
        key: ValueKey<int>(playerId),
        viewType: AssetEntityVideoPlatform.viewType,
        surfaceFactory: (
          BuildContext context,
          PlatformViewController controller,
        ) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (PlatformViewCreationParams params) {
          return PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: AssetEntityVideoPlatform.viewType,
            layoutDirection:
                Directionality.maybeOf(context) ?? TextDirection.ltr,
            creationParams: <String, Object?>{'playerId': playerId},
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => params.onFocusChanged(true),
          )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..create();
        },
      ),
    );
  }
}
