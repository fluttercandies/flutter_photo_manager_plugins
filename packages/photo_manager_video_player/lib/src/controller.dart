// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'dart:async';

import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:photo_manager/photo_manager.dart';

import 'platform_bridge.dart';
import 'value.dart';

/// Applies one non-error native event to [current], returning the next value.
///
/// A malformed event is ignored rather than thrown: one bad message must not
/// take down the isolate a whole gallery runs on.
AssetEntityVideoValue applyPlayerEvent(
  AssetEntityVideoValue current,
  Map<Object?, Object?> event,
) {
  switch (_asString(event['event'])) {
    case 'initialized':
      final num? durationMs = event['durationMs'] as num?;
      if (durationMs == null) {
        return current;
      }
      return current.copyWith(
        isInitialized: true,
        duration: Duration(milliseconds: durationMs.toInt()),
        clearDownloadProgress: true,
      );
    case 'videoSize':
      final num? width = event['width'] as num?;
      final num? height = event['height'] as num?;
      if (width == null || height == null || width <= 0 || height <= 0) {
        return current;
      }
      return current.copyWith(
        size: Size(width.toDouble(), height.toDouble()),
        rotationCorrection: (event['rotationDegrees'] as num?)?.toInt() ?? 0,
      );
    case 'firstFrame':
      return current.copyWith(firstFrameRendered: true);
    case 'position':
      final num? positionMs = event['positionMs'] as num?;
      if (positionMs == null) {
        return current;
      }
      return current.copyWith(
        position: Duration(milliseconds: positionMs.toInt()),
      );
    case 'playing':
      final bool isPlaying = event['isPlaying'] as bool? ?? false;
      return current.copyWith(
        isPlaying: isPlaying,
        // Playback stopping is how completion is reported, so only a fresh
        // start clears it.
        isCompleted: isPlaying ? false : current.isCompleted,
      );
    case 'buffering':
      return current.copyWith(
        isBuffering: event['isBuffering'] as bool? ?? false,
      );
    case 'completed':
      return current.copyWith(isCompleted: true, isPlaying: false);
    case 'downloadProgress':
      final num? progress = event['progress'] as num?;
      if (progress == null) {
        return current;
      }
      return current.copyWith(downloadProgress: progress.toDouble());
    default:
      return current;
  }
}

String? _asString(Object? value) => value is String ? value : null;

/// The platform player [controller] shows, once created — a texture id, or
/// the id an Android platform view is created with.
int? playerIdOf(AssetEntityVideoController controller) => controller._playerId;

/// Plays a video that lives in the photo library, without copying the original.
///
/// Android resolves the asset to a MediaStore `content://` URI and hands it to
/// ExoPlayer; iOS asks PhotoKit for an `AVPlayerItem`. Neither path exports or
/// copies a file.
///
/// Playback pauses when the app goes to the background and resumes when it
/// returns, if it was playing. A [play] requested while the app is in the
/// background, or still waiting for initialization when the app leaves,
/// starts on return instead.
class AssetEntityVideoController extends ValueNotifier<AssetEntityVideoValue> {
  /// Builds a controller synchronously, seeding size and duration from the
  /// asset so the layout is correct before the first frame exists.
  ///
  /// Throws an [ArgumentError] when [asset] is not a video.
  AssetEntityVideoController(
    this.asset, {
    this.allowNetworkAccess = true,
    this.viewType = AssetEntityVideoViewType.textureView,
  }) : super(
          AssetEntityVideoValue(
            size: asset.orientatedSize,
            duration: asset.videoDuration,
          ),
        ) {
    if (asset.type != AssetType.video) {
      throw ArgumentError.value(asset.id, 'asset', 'Not a video');
    }
  }

  /// The video this controller plays.
  final AssetEntity asset;

  /// Whether an iCloud-only asset may be downloaded on demand. iOS only.
  ///
  /// Pass `false` where downloading a full original is not wanted, such as
  /// muted previews in a feed; the controller then fails with
  /// [AssetEntityVideoErrorCode.iCloudUnavailable] instead.
  final bool allowNetworkAccess;

  /// How [AssetEntityVideoView] shows the video. Fixed for the controller's
  /// life, since the platform player is built for one or the other.
  final AssetEntityVideoViewType viewType;

  /// Whether the video is shown through an Android platform view; [viewType]
  /// falls back to a texture elsewhere.
  bool get usesPlatformView =>
      viewType == AssetEntityVideoViewType.platformView &&
      defaultTargetPlatform == TargetPlatform.android;

  int? _playerId;
  StreamSubscription<dynamic>? _events;
  Future<void>? _initializing;
  Future<int>? _creating;
  Future<void>? _disposing;
  final Completer<void> _ready = Completer<void>();
  bool _disposed = false;

  /// Whether the app asked for playback; survives the wait for initialization.
  bool _wantsPlaying = false;

  /// Whether playback starts when the app returns to the foreground.
  bool _resumeOnReturn = false;
  _LifecycleObserver? _lifecycle;

  static bool get _inBackground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused;

  /// The Flutter texture the video is drawn into, once [initialize] has
  /// created the platform player. [AssetEntityVideoView] uses it; draw it
  /// yourself with a `Texture` widget and [AssetEntityVideoValue.rotationCorrection].
  /// Always null when [usesPlatformView].
  int? get textureId => usesPlatformView ? null : _playerId;

  /// Creates the platform player and completes once it reports its metadata,
  /// so `value.duration` and `value.size` are exact when this returns.
  ///
  /// Never throws: a failure lands in `value.error`, so a gallery can warm up
  /// neighbouring pages without awaiting. Check `value.hasError` afterwards.
  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    _observeLifecycle();
    try {
      final bool looping = value.isLooping;
      final double volume = value.volume;
      final Future<int> creating = _creating = AssetEntityVideoPlatform.create(
        assetId: asset.id,
        allowNetworkAccess: allowNetworkAccess,
        looping: looping,
        volume: volume,
        platformView: usesPlatformView,
      );
      final int id = await creating;
      if (_disposed) {
        // dispose() releases this player once the create it awaits returns.
        return;
      }
      _playerId = id;
      // The player id isn't part of `value`, so assigning it alone wouldn't
      // reach a ValueListenableBuilder — the view would never mount.
      notifyListeners();
      _events = AssetEntityVideoPlatform.events(id).listen(
        _onEvent,
        onError: (Object e) => _fail(
          e is PlatformException
              ? decodeError(e.code, e.message)
              : AssetEntityVideoError(
                  AssetEntityVideoErrorCode.playbackFailed,
                  '$e',
                ),
        ),
      );
      // Setters called while `create` was in flight only updated `value`.
      if (value.isLooping != looping) {
        await _call(
          (int id) => AssetEntityVideoPlatform.setLooping(id, value.isLooping),
        );
      }
      if (value.volume != volume) {
        await _call(
          (int id) => AssetEntityVideoPlatform.setVolume(id, value.volume),
        );
      }
      await _ready.future;
    } on PlatformException catch (e) {
      _fail(decodeError(e.code, e.message));
    } catch (e) {
      _fail(
        AssetEntityVideoError(
          AssetEntityVideoErrorCode.playbackFailed,
          '$e',
        ),
      );
    }
  }

  /// Starts or resumes playback, initializing the player if needed. In the
  /// background it only initializes; playback starts when the app returns.
  Future<void> play() async {
    if (_disposed) {
      return;
    }
    _observeLifecycle();
    if (_inBackground) {
      _resumeOnReturn = true;
      await initialize();
      return;
    }
    _wantsPlaying = true;
    await initialize();
    if (_wantsPlaying) {
      await _call(AssetEntityVideoPlatform.play);
    }
  }

  /// Pauses playback, keeping the surface on the current frame. Before
  /// initialization it only cancels a pending [play].
  Future<void> pause() {
    _resumeOnReturn = false;
    return _pause();
  }

  Future<void> _pause() async {
    _wantsPlaying = false;
    await _call(AssetEntityVideoPlatform.pause);
  }

  void _observeLifecycle() {
    _lifecycle ??= _LifecycleObserver(this)..attach();
  }

  void _onBackground() {
    // Playback the platform already paused (lost audio focus, an
    // interruption) stays paused on return.
    final bool active =
        !value.isInitialized || value.isPlaying || value.isBuffering;
    _resumeOnReturn = _wantsPlaying && active;
    if (_wantsPlaying) {
      _pause();
    }
  }

  void _onForeground() {
    if (_resumeOnReturn) {
      _resumeOnReturn = false;
      play();
    }
  }

  /// Moves playback to [position], clamped to the video's duration. Does
  /// nothing before initialization.
  Future<void> seekTo(Duration position) {
    if (!value.isInitialized) {
      return Future<void>.value();
    }
    final Duration clamped = position < Duration.zero
        ? Duration.zero
        : (position > value.duration ? value.duration : position);
    // Seeking away from the end means the clip is no longer finished; iOS
    // reports no event for that.
    if (value.isCompleted && clamped < value.duration) {
      value = value.copyWith(isCompleted: false);
    }
    return _call((int id) => AssetEntityVideoPlatform.seekTo(id, clamped));
  }

  /// Sets output volume; values outside 0.0–1.0 are clamped. Before
  /// initialization the value is kept and applied when the player exists.
  Future<void> setVolume(double volume) {
    if (_disposed) {
      return Future<void>.value();
    }
    final double clamped = volume.clamp(0.0, 1.0);
    value = value.copyWith(volume: clamped);
    return _call((int id) => AssetEntityVideoPlatform.setVolume(id, clamped));
  }

  /// Sets whether playback restarts on completion. Before initialization the
  /// value is kept and applied when the player exists.
  Future<void> setLooping(bool looping) {
    if (_disposed) {
      return Future<void>.value();
    }
    value = value.copyWith(isLooping: looping);
    return _call((int id) => AssetEntityVideoPlatform.setLooping(id, looping));
  }

  /// Sends [action] to an existing player; a no-op before initialization.
  Future<void> _call(Future<void> Function(int textureId) action) async {
    final int? id = _playerId;
    if (id == null || _disposed) {
      return;
    }
    try {
      await action(id);
    } on PlatformException catch (e) {
      _fail(decodeError(e.code, e.message));
    }
  }

  void _onEvent(dynamic event) {
    if (_disposed || event is! Map) {
      return;
    }
    final Map<Object?, Object?> map = event;
    if (_asString(map['event']) == 'error') {
      _fail(decodeError(_asString(map['code']), _asString(map['message'])));
      return;
    }
    value = applyPlayerEvent(value, map);
    if (value.isCompleted) {
      _wantsPlaying = false;
    }
    if (value.isInitialized) {
      _markReady();
    }
  }

  void _fail(AssetEntityVideoError error) {
    _markReady();
    _wantsPlaying = false;
    _resumeOnReturn = false;
    if (_disposed) {
      return;
    }
    value = value.copyWith(
      error: error,
      isPlaying: false,
      isBuffering: false,
      clearDownloadProgress: true,
    );
  }

  /// Lets a pending [initialize] return; nothing more will change its outcome.
  void _markReady() {
    if (!_ready.isCompleted) {
      _ready.complete();
    }
  }

  /// Releases the platform player. The returned future completes once it is
  /// gone, including a player whose creation was still in flight.
  @override
  Future<void> dispose() {
    final Future<void>? disposing = _disposing;
    if (disposing != null) {
      return disposing;
    }
    _disposed = true;
    _wantsPlaying = false;
    _resumeOnReturn = false;
    _markReady();
    _lifecycle?.detach();
    super.dispose();
    return _disposing = _release(_events, _creating);
  }

  Future<void> _release(
    StreamSubscription<dynamic>? events,
    Future<int>? creating,
  ) async {
    await events?.cancel();
    int? id = _playerId;
    if (id == null && creating != null) {
      try {
        id = await creating;
      } catch (_) {
        // A failed create left nothing to release.
      }
    }
    if (id != null) {
      // The native side may already have dropped the player on an engine
      // detach, and that rejection must not escape into the disposing zone.
      await AssetEntityVideoPlatform.dispose(id).catchError((Object _) {});
    }
  }
}

/// Pauses on the way to the background and resumes on return, like
/// `video_player` does by default.
class _LifecycleObserver with WidgetsBindingObserver {
  _LifecycleObserver(this._controller);

  final AssetEntityVideoController _controller;

  void attach() => WidgetsBinding.instance.addObserver(this);

  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _controller._onBackground();
    } else if (state == AppLifecycleState.resumed) {
      _controller._onForeground();
    }
  }
}
