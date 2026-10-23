// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

/// Load `photo_manager` thumbnails as native RGBA pixels, with no JPEG round
/// trip and cancellation that follows the Flutter image cache.
library;

export 'src/native_asset_image.dart' show NativeAssetImage;
export 'src/native_image_exception.dart'
    show NativeImageErrorCode, NativeImageException;
export 'src/native_image_provider.dart' show NativeImageProvider;
