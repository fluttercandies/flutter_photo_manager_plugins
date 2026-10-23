// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/painting.dart';

/// Tells the [ImageCache]'s own listener apart from widget listeners so a
/// completer can cancel native work only when nobody but the cache is waiting.
///
/// [ImageCache.putIfAbsent] always attaches the first listener, before the
/// provider attaches any [ImageStream] listener. That first listener is locked
/// in as the cache listener. Cancellation then triggers exactly once, when the
/// last non-cache listener leaves while no image has arrived. This keeps
/// [ImageCache.clear] (which only detaches the cache listener) and a cache
/// listener that detaches synchronously from producing false cancels.
mixin CacheAwareListenerTracker on ImageStreamCompleter {
  ImageStreamListener? _cacheListener;
  bool _sawFirstListener = false;
  int _widgetListeners = 0;
  bool _hasImage = false;
  bool _cancelRequested = false;
  bool _inAddListener = false;

  /// Whether the cancel condition has fired.
  bool get cancelRequested => _cancelRequested;

  /// Widget listeners currently attached (the cache listener excluded).
  int get widgetListenerCount => _widgetListeners;

  /// Called once when only the cache (or nobody) is waiting and no image has
  /// arrived. Implementations stop the native request and evict the key.
  void onCancelRequested();

  @override
  void addListener(ImageStreamListener listener) {
    if (!_sawFirstListener) {
      _sawFirstListener = true;
      _cacheListener = listener;
    } else {
      _widgetListeners++;
    }
    _inAddListener = true;
    try {
      super.addListener(listener);
    } finally {
      _inAddListener = false;
    }
  }

  @override
  void removeListener(ImageStreamListener listener) {
    if (identical(listener, _cacheListener)) {
      _cacheListener = null;
      if (_inAddListener) {
        // Detached synchronously from inside addListener (the completer had
        // an image): the cache never really waited, so treat the first real
        // widget listener as such.
        _sawFirstListener = false;
      }
    } else if (_widgetListeners > 0) {
      _widgetListeners--;
    }
    super.removeListener(listener);
    _evaluateCancel();
  }

  @override
  void setImage(ImageInfo image) {
    _hasImage = true;
    super.setImage(image);
  }

  void _evaluateCancel() {
    if (_cancelRequested || _hasImage || _widgetListeners > 0) {
      return;
    }
    _cancelRequested = true;
    onCancelRequested();
  }
}
