// Copyright 2018 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'dart:io';
import 'dart:typed_data' as typed_data;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

const String _kChannelName = 'com.fluttercandies/photo_manager_location';

/// Host bridge for the location-saving Darwin code.
///
/// Exposes [saveImage], [saveImageWithPath] and [saveVideo], which mirror the
/// core [PhotoManagerPlugin]'s save methods argument-for-argument but target
/// the separate [_kChannelName] method channel implemented by the native
/// `PMLocationPlugin` (the only code path that links CoreLocation).
class LocationPlugin {
  const LocationPlugin._();

  static const LocationPlugin instance = LocationPlugin._();

  static const MethodChannel channel = MethodChannel(_kChannelName);

  /// Save image bytes with a location.
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
  }) async {
    final Map<dynamic, dynamic> result = await channel.invokeMethod(
      'saveImage',
      <String, dynamic>{
        'image': data,
        'filename': filename,
        'title': title,
        'desc': desc,
        'relativePath': relativePath,
        'orientation': orientation,
        'latitude': latitude,
        'longitude': longitude,
        'creationDate': creationDate?.millisecondsSinceEpoch,
      },
    );
    return _convertMapToAsset(
      result.cast<String, dynamic>(),
      title: filename,
    );
  }

  /// Save an image located at [inputFilePath] with a location.
  Future<AssetEntity> saveImageWithPath(
    String inputFilePath, {
    String? title,
    String? desc,
    String? relativePath,
    int? orientation,
    double? latitude,
    double? longitude,
    DateTime? creationDate,
  }) async {
    final File file = File(inputFilePath);
    if (!file.existsSync()) {
      throw ArgumentError('The input file $inputFilePath does not exists.');
    }

    final String filePath = file.absolute.path;
    title = title?.trim();
    if (title == null || title.isEmpty) {
      title = p.basename(filePath);
    }

    final Map<dynamic, dynamic> result = await channel.invokeMethod(
      'saveImageWithPath',
      <String, dynamic>{
        'path': filePath,
        'title': title,
        'desc': desc,
        'relativePath': relativePath,
        'orientation': orientation,
        'latitude': latitude,
        'longitude': longitude,
        'creationDate': creationDate?.millisecondsSinceEpoch,
      },
    );
    return _convertMapToAsset(result.cast<String, dynamic>(), title: title);
  }

  /// Save a video [inputFile] with a location.
  Future<AssetEntity> saveVideo(
    File inputFile, {
    required String? title,
    String? desc,
    String? relativePath,
    int? orientation,
    double? latitude,
    double? longitude,
    DateTime? creationDate,
  }) async {
    if (!inputFile.existsSync()) {
      throw ArgumentError(
        'The input file ${inputFile.path} does not exists.',
      );
    }

    final String filePath = inputFile.absolute.path;
    title = title?.trim();
    if (title == null || title.isEmpty) {
      title = p.basename(filePath);
    }

    final Map<dynamic, dynamic> result = await channel.invokeMethod(
      'saveVideo',
      <String, dynamic>{
        'path': filePath,
        'title': title,
        'desc': desc ?? '',
        'relativePath': relativePath,
        'orientation': orientation,
        'latitude': latitude,
        'longitude': longitude,
        'creationDate': creationDate?.millisecondsSinceEpoch,
      },
    );
    return _convertMapToAsset(result.cast<String, dynamic>(), title: title);
  }

  /// Reconstruct an [AssetEntity] from the native asset map.
  //
  // `photo_manager` does not export `ConvertUtils`, so this mirrors
  // `ConvertUtils.convertMapToAsset` field-for-field. The map is produced by
  // the native `PMLocationManager` (the `convertPHAssetToMap` field set).
  // `latitude`/`longitude` are deprecated on the constructor post-3.8.0; the
  // ignore keeps this version-agnostic across the supported range.
  // ignore_for_file: deprecated_member_use
  static AssetEntity _convertMapToAsset(
    Map<String, dynamic> data, {
    String? title,
  }) {
    final Object? rawLat = data['lat'];
    final double? lat = rawLat is num ? rawLat.toDouble() : null;
    final Object? rawLng = data['lng'];
    final double? lng = rawLng is num ? rawLng.toDouble() : null;

    return AssetEntity(
      id: data['id'] as String,
      typeInt: data['type'] as int,
      width: data['width'] as int,
      height: data['height'] as int,
      duration: data['duration'] as int? ?? 0,
      isFavorite: data['favorite'] as bool? ?? false,
      title: data['title'] as String? ?? title,
      subtype: data['subtype'] as int? ?? 0,
      createDateSecond: data['createDt'] as int?,
      modifiedDateSecond: data['modifiedDt'] as int?,
      latitude: lat,
      longitude: lng,
    );
  }
}
