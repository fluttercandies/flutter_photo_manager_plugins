// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/services.dart';

/// Why a native thumbnail request failed.
enum NativeImageErrorCode {
  /// The asset no longer exists in the photo library.
  notFound,

  /// iOS only: the asset is in iCloud and could not be downloaded, for
  /// example because the device is offline.
  icloudNotDownloaded,

  /// The platform could not produce pixels for the asset.
  decodeFailed,
}

const Map<NativeImageErrorCode, String> _wireCodes =
    <NativeImageErrorCode, String>{
  NativeImageErrorCode.notFound: 'not_found',
  NativeImageErrorCode.icloudNotDownloaded: 'icloud_not_downloaded',
  NativeImageErrorCode.decodeFailed: 'decode_failed',
};

/// Thrown into the [ImageStream] (and so into `Image.errorBuilder`) when a
/// thumbnail cannot be loaded.
class NativeImageException implements Exception {
  const NativeImageException._(this.code, this.message);

  /// The typed failure reason.
  final NativeImageErrorCode code;

  /// Optional detail from the platform.
  final String? message;

  @override
  String toString() =>
      'NativeImageException(${_wireCodes[code]}${message == null ? '' : ': $message'})';
}

/// Maps a channel error to a [NativeImageException]; unknown codes become
/// [NativeImageErrorCode.decodeFailed]. Not exported.
NativeImageException nativeImageExceptionFromPlatform(
  PlatformException exception,
) {
  final NativeImageErrorCode code = _wireCodes.entries
      .firstWhere(
        (MapEntry<NativeImageErrorCode, String> e) => e.value == exception.code,
        orElse: () => const MapEntry<NativeImageErrorCode, String>(
          NativeImageErrorCode.decodeFailed,
          '',
        ),
      )
      .key;
  return NativeImageException._(code, exception.message);
}
