import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_native_image/src/native_image_channel.dart';

/// Records calls and lets a test decide each reply.
class FakeChannel extends NativeImageChannel {
  final List<int> requested = <int>[];
  final List<int> cancelled = <int>[];
  final Map<int, bool> networkOf = <int, bool>{};
  final Map<int, Completer<Map<String, int>?>> pending =
      <int, Completer<Map<String, int>?>>{};

  @override
  Future<Map<String, int>?> requestImage({
    required String assetId,
    required int requestId,
    required int width,
    required int height,
    required bool isVideo,
    required bool allowNetwork,
  }) {
    requested.add(requestId);
    networkOf[requestId] = allowNetwork;
    final Completer<Map<String, int>?> completer =
        Completer<Map<String, int>?>();
    pending[requestId] = completer;
    return completer.future;
  }

  @override
  Future<void> cancelRequest(int requestId) async {
    cancelled.add(requestId);
  }

  void reply(int requestId, Map<String, int>? value) =>
      pending.remove(requestId)!.complete(value);

  void fail(int requestId, String code) => pending
      .remove(requestId)!
      .completeError(PlatformException(code: code, message: 'x'));
}

/// Allocates an opaque RGBA buffer of `width x height` and returns the reply
/// the platform would send.
Map<String, int> allocateBuffer(int width, int height, {int padding = 0}) {
  final int rowBytes = width * 4 + padding;
  final Pointer<Uint8> pointer = malloc.allocate<Uint8>(rowBytes * height);
  final List<int> bytes = pointer.asTypedList(rowBytes * height);
  for (int i = 0; i < bytes.length; i += 4) {
    bytes[i] = 200;
    bytes[i + 1] = 100;
    bytes[i + 2] = 50;
    bytes[i + 3] = 255;
  }
  return <String, int>{
    'pointer': pointer.address,
    'width': width,
    'height': height,
    'rowBytes': rowBytes,
  };
}

AssetEntity entity({
  String id = 'a',
  int? createDate,
  int? modifiedDate,
  AssetType type = AssetType.image,
}) {
  return AssetEntity(
    id: id,
    typeInt: type.index,
    width: 100,
    height: 100,
    createDateSecond: createDate,
    modifiedDateSecond: modifiedDate,
  );
}
