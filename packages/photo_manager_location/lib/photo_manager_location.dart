// Copyright 2018 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

/// An opt-in companion to `photo_manager` that links CoreLocation so apps can
/// save assets tagged with geographic coordinates on iOS and macOS.
///
/// Import `package:photo_manager_location/photo_manager_location.dart` and use
/// [PhotoManagerLocation.editor] to save photos and videos with a location.
library photo_manager_location;

export 'src/location_editor.dart';
export 'src/photo_manager_location.dart';
