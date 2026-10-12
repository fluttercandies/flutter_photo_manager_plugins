// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Size;

/// How [AssetEntityVideoView] puts the video on screen.
enum AssetEntityVideoViewType {
  /// A Flutter texture, composited like any other widget.
  textureView,

  /// An Android `SurfaceView` embedded as a platform view. Android only;
  /// other platforms fall back to [textureView].
  ///
  /// The video stays on its own display layer, so HDR video is shown with the
  /// system's HDR handling instead of being flattened into the 8-bit sRGB
  /// Flutter layer. In return it composites like a platform view: transforms
  /// and clipping cost more, and opacity may not apply. Keep the view painted
  /// until `firstFrameRendered` — under a zero opacity it is not composited,
  /// so its surface, and the first frame, never arrive. Cover it instead.
  platformView,
}

/// Why playback could not start or continue.
///
/// Only cases a gallery UI has to branch on are exposed as codes; everything
/// else collapses into [AssetEntityVideoErrorCode.playbackFailed].
enum AssetEntityVideoErrorCode {
  /// The asset is no longer in the library, or is outside the app's access.
  assetNotFound,

  /// The photo library denied access.
  permissionDenied,

  /// The asset lives only in iCloud and could not be downloaded.
  iCloudUnavailable,

  /// The platform player failed to decode or render.
  playbackFailed,
}

/// A playback failure, carrying a code the UI can branch on.
@immutable
class AssetEntityVideoError implements Exception {
  /// Creates an error with a machine-readable [code].
  const AssetEntityVideoError(this.code, this.message);

  /// What went wrong.
  final AssetEntityVideoErrorCode code;

  /// Platform-supplied detail, for logs rather than for users.
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssetEntityVideoError &&
          code == other.code &&
          message == other.message);

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'AssetEntityVideoError(${code.name}: $message)';
}

/// Immutable snapshot of a player's state.
@immutable
class AssetEntityVideoValue {
  /// Creates a snapshot; every field defaults to a not-yet-playing state.
  const AssetEntityVideoValue({
    required this.size,
    required this.duration,
    this.position = Duration.zero,
    this.isInitialized = false,
    this.isPlaying = false,
    this.isLooping = false,
    this.isBuffering = false,
    this.isCompleted = false,
    this.firstFrameRendered = false,
    this.rotationCorrection = 0,
    this.volume = 1.0,
    this.downloadProgress,
    this.error,
  });

  /// Display size with rotation applied. Seeded from the `AssetEntity` so the
  /// aspect ratio is right before the player exists, then corrected by it.
  final Size size;

  /// Seeded from the asset's whole-second duration, replaced by the exact
  /// value on initialization.
  final Duration duration;

  /// Where playback currently is.
  final Duration position;

  /// Whether the platform player exists and reported its metadata.
  final bool isInitialized;

  /// Whether playback is currently advancing.
  final bool isPlaying;

  /// Whether playback restarts on completion.
  final bool isLooping;

  /// Whether the player is stalled waiting for data.
  final bool isBuffering;

  /// Whether playback reached the end without looping.
  final bool isCompleted;

  /// Clockwise quarter turn the raw texture needs to be upright (0, 90, 180,
  /// 270). [AssetEntityVideoView] applies it; [size] is already the upright
  /// size. Only needed when drawing `AssetEntityVideoController.textureId`
  /// yourself. Always 0 for [AssetEntityVideoViewType.platformView], whose
  /// frames the decoder already rotates.
  final int rotationCorrection;

  /// True once a frame has actually reached the platform surface — the signal
  /// to cross-fade away from the poster thumbnail.
  final bool firstFrameRendered;

  /// Output volume, 0.0 to 1.0.
  final double volume;

  /// 0.0–1.0 while an iCloud asset is downloading, null otherwise. iOS only.
  final double? downloadProgress;

  /// The failure that stopped playback, if any.
  final AssetEntityVideoError? error;

  /// Whether [error] is set.
  bool get hasError => error != null;

  /// Width over height of [size]; 1.0 when the size is unknown.
  double get aspectRatio => size.height == 0 ? 1.0 : size.width / size.height;

  /// Returns a copy with the given fields replaced.
  ///
  /// Pass `clearDownloadProgress` to drop an in-flight iCloud progress value,
  /// which `null` cannot express — it also means "leave this field alone".
  AssetEntityVideoValue copyWith({
    Size? size,
    Duration? duration,
    Duration? position,
    bool? isInitialized,
    bool? isPlaying,
    bool? isLooping,
    bool? isBuffering,
    bool? isCompleted,
    bool? firstFrameRendered,
    int? rotationCorrection,
    double? volume,
    double? downloadProgress,
    bool clearDownloadProgress = false,
    AssetEntityVideoError? error,
  }) {
    return AssetEntityVideoValue(
      size: size ?? this.size,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isLooping: isLooping ?? this.isLooping,
      isBuffering: isBuffering ?? this.isBuffering,
      isCompleted: isCompleted ?? this.isCompleted,
      firstFrameRendered: firstFrameRendered ?? this.firstFrameRendered,
      rotationCorrection: rotationCorrection ?? this.rotationCorrection,
      volume: volume ?? this.volume,
      downloadProgress: clearDownloadProgress
          ? null
          : downloadProgress ?? this.downloadProgress,
      error: error ?? this.error,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssetEntityVideoValue &&
          size == other.size &&
          duration == other.duration &&
          position == other.position &&
          isInitialized == other.isInitialized &&
          isPlaying == other.isPlaying &&
          isLooping == other.isLooping &&
          isBuffering == other.isBuffering &&
          isCompleted == other.isCompleted &&
          firstFrameRendered == other.firstFrameRendered &&
          rotationCorrection == other.rotationCorrection &&
          volume == other.volume &&
          downloadProgress == other.downloadProgress &&
          error == other.error);

  @override
  int get hashCode => Object.hash(
        size,
        duration,
        position,
        isInitialized,
        isPlaying,
        isLooping,
        isBuffering,
        isCompleted,
        firstFrameRendered,
        rotationCorrection,
        volume,
        downloadProgress,
        error,
      );

  @override
  String toString() => 'AssetEntityVideoValue('
      'size: $size, duration: $duration, position: $position, '
      'isInitialized: $isInitialized, isPlaying: $isPlaying, '
      'isLooping: $isLooping, isBuffering: $isBuffering, '
      'isCompleted: $isCompleted, firstFrameRendered: $firstFrameRendered, '
      'rotationCorrection: $rotationCorrection, '
      'volume: $volume, downloadProgress: $downloadProgress, error: $error)';
}
