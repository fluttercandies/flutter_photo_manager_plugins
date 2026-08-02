// Copyright 2018 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'location_editor.dart';

/// Entry point for location-tagged asset saving on iOS and macOS.
///
/// Use [editor] to save photos and videos with geographic coordinates. This
/// package links CoreLocation so the core `photo_manager` package can stay
/// CoreLocation-free.
///
/// ```dart
/// final AssetEntity asset = await PhotoManagerLocation.editor.saveImage(
///   bytes,
///   filename: 'IMG_0001.jpg',
///   latitude: 31.2304,
///   longitude: 121.4737,
/// );
/// ```
class PhotoManagerLocation {
  const PhotoManagerLocation._();

  /// Saves assets with location coordinates.
  static const LocationEditor editor = LocationEditor();
}
