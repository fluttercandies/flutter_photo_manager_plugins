// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'cache_aware_listener_tracker.dart';
import 'native_image_exception.dart';

/// Single-frame completer that cancels its native request when only the image
/// cache is still waiting, and evicts the cache key on cancel and on error so
/// a later request starts fresh instead of joining a dead load.
class NativeImageStreamCompleter extends ImageStreamCompleter
    with CacheAwareListenerTracker {
  /// Starts [load] immediately.
  NativeImageStreamCompleter({
    required Future<ui.FrameInfo?> Function() load,
    required VoidCallback onCancel,
    required VoidCallback onFailure,
    String? debugLabel,
  })  : _onCancel = onCancel,
        _onFailure = onFailure {
    this.debugLabel = debugLabel;
    _run(load);
  }

  final VoidCallback _onCancel;
  final VoidCallback _onFailure;

  Future<void> _run(Future<ui.FrameInfo?> Function() load) async {
    ui.FrameInfo? frame;
    try {
      frame = await load();
    } on NativeImageException catch (exception, stack) {
      if (cancelRequested) {
        return;
      }
      reportError(
        context: ErrorDescription('loading a native thumbnail'),
        exception: exception,
        stack: stack,
        informationCollector: () => <DiagnosticsNode>[
          DiagnosticsProperty<String>('Asset', debugLabel),
        ],
        silent: true,
      );
      _onFailure();
      return;
    } catch (exception, stack) {
      if (cancelRequested) {
        return;
      }
      reportError(
        context: ErrorDescription('loading a native thumbnail'),
        exception: exception,
        stack: stack,
      );
      _onFailure();
      return;
    }
    if (frame == null) {
      // Cancelled; nobody is listening, and the cache entry is gone.
      return;
    }
    if (cancelRequested) {
      frame.image.dispose();
      return;
    }
    setImage(
      ImageInfo(image: frame.image, debugLabel: debugLabel),
    );
  }

  @override
  void onCancelRequested() => _onCancel();
}
