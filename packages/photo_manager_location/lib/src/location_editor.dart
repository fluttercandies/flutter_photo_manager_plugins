// Copyright 2018 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'dart:io';
import 'dart:typed_data' as typed_data;

import 'package:photo_manager/photo_manager.dart';

import 'plugin.dart';

/// Saves photos and videos to the photo library **with location coordinates**
/// on iOS and macOS.
///
/// This mirrors [Editor.saveImage], [Editor.saveImageWithPath] and
/// [Editor.saveVideo] exactly, but routes every call to the separate
/// `com.fluttercandies/photo_manager_location` method channel implemented by
/// the Darwin native code in this package — the only place CoreLocation is
/// linked. Use it instead of the core editor when you need location-tagged
/// saves:
///
/// ```dart
/// final AssetEntity asset = await PhotoManagerLocation.editor.saveImage(
///   bytes,
///   filename: 'IMG_0001.jpg',
///   latitude: 31.2304,
///   longitude: 121.4737,
/// );
/// ```
class LocationEditor {
  const LocationEditor();

  /// Save image to gallery from [data] with a location.
  ///
  /// [filename] is the original filename used by the asset.
  ///
  /// {@macro photo_manager.Editor.DescriptionWhenSaving}
  /// {@macro photo_manager.Editor.RelativePathWhenSaving}
  /// {@macro photo_manager.Editor.OrientationWhenSaving}
  /// {@macro photo_manager.Editor.LocationWhenSaving}
  /// {@macro photo_manager.Editor.CreationDateWhenSaving}
  Future<AssetEntity> saveImage(
    typed_data.Uint8List data, {
    required String filename,
    String? title,
    String? desc,
    String? relativePath,
    int? orientation,
    double? latitude,
    double? longitude,
    DateTime? creationDate,
  }) {
    return LocationPlugin.instance.saveImage(
      data,
      filename: filename,
      title: title,
      desc: desc,
      relativePath: relativePath,
      orientation: orientation,
      latitude: latitude,
      longitude: longitude,
      creationDate: creationDate,
    );
  }

  /// Save image to gallery from the given [filePath] with a location.
  ///
  /// {@macro photo_manager.Editor.TitleWhenSaving}
  /// {@macro photo_manager.Editor.DescriptionWhenSaving}
  /// {@macro photo_manager.Editor.RelativePathWhenSaving}
  /// {@macro photo_manager.Editor.OrientationWhenSaving}
  /// {@macro photo_manager.Editor.LocationWhenSaving}
  /// {@macro photo_manager.Editor.CreationDateWhenSaving}
  Future<AssetEntity> saveImageWithPath(
    String filePath, {
    String? title,
    String? desc,
    String? relativePath,
    int? orientation,
    double? latitude,
    double? longitude,
    DateTime? creationDate,
  }) {
    return LocationPlugin.instance.saveImageWithPath(
      filePath,
      title: title,
      desc: desc,
      relativePath: relativePath,
      orientation: orientation,
      latitude: latitude,
      longitude: longitude,
      creationDate: creationDate,
    );
  }

  /// Save video to gallery from the given [file] with a location.
  ///
  /// {@macro photo_manager.Editor.TitleWhenSaving}
  /// {@macro photo_manager.Editor.DescriptionWhenSaving}
  /// {@macro photo_manager.Editor.RelativePathWhenSaving}
  /// {@macro photo_manager.Editor.OrientationWhenSaving}
  /// {@macro photo_manager.Editor.LocationWhenSaving}
  /// {@macro photo_manager.Editor.CreationDateWhenSaving}
  Future<AssetEntity> saveVideo(
    File file, {
    String? title,
    String? desc,
    String? relativePath,
    int? orientation,
    double? latitude,
    double? longitude,
    DateTime? creationDate,
  }) {
    return LocationPlugin.instance.saveVideo(
      file,
      title: title,
      desc: desc,
      relativePath: relativePath,
      orientation: orientation,
      latitude: latitude,
      longitude: longitude,
      creationDate: creationDate,
    );
  }
}
