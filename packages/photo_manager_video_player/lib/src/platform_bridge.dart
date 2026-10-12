// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

// Internal transport layer; not exported from the package.
// ignore_for_file: public_member_api_docs

import 'package:flutter/services.dart';

import 'value.dart';

/// Channel names and payload keys, kept in one place so the native side has a
/// single contract to match.
class AssetEntityVideoPlatform {
  static const String _name = 'com.fluttercandies/photo_manager_video_player';
  static const MethodChannel _channel = MethodChannel(_name);

  static bool _restartCleanupDone = false;

  static Future<int> create({
    required String assetId,
    required bool allowNetworkAccess,
    required bool looping,
    required double volume,
    required bool platformView,
  }) async {
    if (!_restartCleanupDone) {
      _restartCleanupDone = true;
      // A hot restart leaves the engine, and its players, alive while this
      // isolate starts over with no way to dispose them.
      await _channel.invokeMethod<void>('disposeAll');
    }
    final int? id =
        await _channel.invokeMethod<int>('create', <String, dynamic>{
      'assetId': assetId,
      'allowNetworkAccess': allowNetworkAccess,
      'looping': looping,
      'volume': volume,
      if (platformView) 'viewType': 'platformView',
    });
    if (id == null) {
      throw PlatformException(
        code: 'playbackFailed',
        message: 'Platform returned no texture id.',
      );
    }
    return id;
  }

  static Future<void> play(int textureId) => _invoke('play', textureId);

  static Future<void> pause(int textureId) => _invoke('pause', textureId);

  static Future<void> dispose(int textureId) => _invoke('dispose', textureId);

  static Future<void> seekTo(int textureId, Duration position) =>
      _invoke('seekTo', textureId, <String, dynamic>{
        'positionMs': position.inMilliseconds,
      });

  static Future<void> setVolume(int textureId, double volume) =>
      _invoke('setVolume', textureId, <String, dynamic>{'volume': volume});

  static Future<void> setLooping(int textureId, bool looping) =>
      _invoke('setLooping', textureId, <String, dynamic>{'looping': looping});

  static Future<void> _invoke(
    String method,
    int textureId, [
    Map<String, dynamic> args = const <String, dynamic>{},
  ]) {
    return _channel.invokeMethod<void>(method, <String, dynamic>{
      'textureId': textureId,
      ...args,
    });
  }

  /// The Android platform view type that shows a player created with
  /// `platformView`.
  static const String viewType = '$_name/view';

  static Stream<dynamic> events(int textureId) =>
      EventChannel('$_name/events/$textureId').receiveBroadcastStream();
}

/// Maps a native `error` payload onto the public error type.
AssetEntityVideoError decodeError(String? code, String? message) {
  final AssetEntityVideoErrorCode parsed = switch (code) {
    'assetNotFound' => AssetEntityVideoErrorCode.assetNotFound,
    'permissionDenied' => AssetEntityVideoErrorCode.permissionDenied,
    'iCloudUnavailable' => AssetEntityVideoErrorCode.iCloudUnavailable,
    _ => AssetEntityVideoErrorCode.playbackFailed,
  };
  return AssetEntityVideoError(parsed, message ?? 'Unknown playback failure.');
}
