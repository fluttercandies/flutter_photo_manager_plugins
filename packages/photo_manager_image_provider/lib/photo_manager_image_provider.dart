// Copyright 2018 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

library photo_manager_image_provider;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data' as typed_data;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:photo_manager/photo_manager.dart';

final _lockDecode = <AssetEntityImageProvider, Completer<ui.Codec>>{};
final _lockImageTypes = <AssetEntityImageProvider, Completer<ImageFileType>>{};

const ThumbnailSize pmDefaultGridThumbnailSize = ThumbnailSize.square(200);
const String _libraryName = 'photo_manager';

/// The [ImageProvider] that handles [AssetEntity].
///
/// Only support [AssetType.image] and [AssetType.video],
/// others will throw errors during the resolving.
///
/// If [isOriginal] is true:
///   * Fetch [AssetEntity.thumbnailData] for [AssetType.video].
///   * Fetch [AssetEntity.file] and convert to bytes for HEIF(HEIC) images.
///   * Fetch [AssetEntity.originBytes] for images.
/// Else, fetch [AssetEntity.thumbnailDataWithOption] with the given
/// [thumbnailSize] and the [thumbnailFormat].
@immutable
class AssetEntityImageProvider extends ImageProvider<AssetEntityImageProvider> {
  const AssetEntityImageProvider(
    this.entity, {
    this.isOriginal = true,
    this.thumbnailSize = pmDefaultGridThumbnailSize,
    this.thumbnailFormat = ThumbnailFormat.jpeg,
    this.frame = 0,
    this.progressHandler,
  }) : assert(
          isOriginal || thumbnailSize != null,
          "thumbSize must not be null when it's not original",
        );

  /// {@macro photo_manager.AssetEntity}
  final AssetEntity entity;

  /// Choose if original data or thumb data should be loaded.
  /// 选择载入原数据还是缩略图数据。
  final bool isOriginal;

  /// Size for thumb data.
  /// 缩略图的大小。
  final ThumbnailSize? thumbnailSize;

  /// {@macro photo_manager.ThumbnailFormat}
  final ThumbnailFormat thumbnailFormat;

  /// {@macro photo_manager.ThumbnailOption.frame}
  final int frame;

  /// {@macro photo_manager.PMProgressHandler}
  final PMProgressHandler? progressHandler;

  /// File type for the image asset, use it for some special type detection.
  /// 图片资源的类型，用于某些特殊类型的判断。
  Future<ImageFileType> get imageFileType async {
    if (_lockImageTypes[this] != null) {
      return _lockImageTypes[this]!.future;
    }
    return _getType();
  }

  @override
  ImageStreamCompleter loadImage(
    AssetEntityImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: '${key.entity.runtimeType}-'
          '${key.entity.id}-'
          '${isOriginal ? 'origin-' : ''}'
          '${isOriginal ? '' : '$thumbnailFormat'}',
      informationCollector: () {
        return <DiagnosticsNode>[
          DiagnosticsProperty<ImageProvider>('Image provider', this),
          DiagnosticsProperty<AssetEntityImageProvider>('Image key', key),
          DiagnosticsProperty<AssetEntity>('entity', entity),
          DiagnosticsProperty<bool>('isOriginal', isOriginal),
          DiagnosticsProperty<ThumbnailSize>('thumbnailSize', thumbnailSize),
          DiagnosticsProperty<ThumbnailFormat>(
            'thumbnailFormat',
            thumbnailFormat,
          ),
          DiagnosticsProperty<int>('frame', frame),
        ];
      },
    );
  }

  @override
  Future<AssetEntityImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<AssetEntityImageProvider>(this);
  }

  Future<ui.Codec> _loadAsync(
    AssetEntityImageProvider key,
    ImageDecoderCallback decode, // ignore: deprecated_member_use
  ) {
    if (_lockDecode.containsKey(key)) {
      return _lockDecode[key]!.future;
    }
    final lock = Completer<ui.Codec>();
    _lockDecode[key] = lock;
    Future(() async {
      try {
        assert(key == this);
        if (key.entity.type == AssetType.audio ||
            key.entity.type == AssetType.other) {
          throw UnsupportedError(
            'Image data for the ${key.entity.type} is not supported.',
          );
        }
        final imageType =
            await _lockImageTypes[key]?.future ?? await key.imageFileType;
        _lockImageTypes[key] ??= Completer.sync()..complete(imageType);

        typed_data.Uint8List? data;
        if (isOriginal) {
          if (key.entity.type == AssetType.video) {
            data = await key.entity.thumbnailDataWithOption(
              _thumbOption(const ThumbnailSize.square(500)),
              progressHandler: progressHandler,
            );
          } else {
            final file = await key.entity.loadFile(
              isOrigin: imageType != ImageFileType.heic,
              progressHandler: progressHandler,
            );
            data = await file?.readAsBytes();
          }
        } else {
          data = await key.entity.thumbnailDataWithOption(
            _thumbOption(thumbnailSize!),
            progressHandler: progressHandler,
          );
        }
        if (data == null) {
          throw StateError('The data of the entity is null: $entity');
        }
        final buffer = await ui.ImmutableBuffer.fromUint8List(data);
        return decode(buffer);
      } catch (e, s) {
        if (kDebugMode) {
          FlutterError.presentError(
            FlutterErrorDetails(
              exception: e,
              stack: s,
              library: _libraryName,
            ),
          );
        }
        // Depending on where the exception was thrown, the image cache may not
        // have had a chance to track the key in the cache at all.
        // Schedule a microtask to give the cache a chance to add the key.
        Future<void>.microtask(() => _evictCache(key));
        rethrow;
      }
    }).then(lock.complete).catchError(lock.completeError).whenComplete(() {
      _lockDecode.remove(key);
    });
    return lock.future;
  }

  ThumbnailOption _thumbOption(ThumbnailSize size) {
    if (Platform.isIOS || Platform.isMacOS) {
      return ThumbnailOption.ios(size: size, format: thumbnailFormat);
    }
    return ThumbnailOption(size: size, format: thumbnailFormat, frame: frame);
  }

  /// Get image type by reading the file extension.
  /// 从图片后缀判断图片类型
  Future<ImageFileType> _getType([String? filename]) async {
    if (_lockImageTypes[this] != null) {
      return _lockImageTypes[this]!.future;
    }
    final lock = Completer<ImageFileType>();
    _lockImageTypes[this] = lock;
    Future(() async {
      String? extension = filename?.split('.').last;
      if (extension == null || extension.trim().isEmpty) {
        extension = entity.mimeType?.split('.').last;
      }
      if (extension == null || extension.trim().isEmpty) {
        extension = entity.title?.split('.').last;
      }
      if (extension == null || extension.trim().isEmpty) {
        extension = (await entity.titleAsync).split('.').last;
      }
      if (extension.trim().isEmpty) {
        extension = null;
      }
      ImageFileType? type;
      if (extension != null) {
        switch (extension.toLowerCase()) {
          case 'jpg':
          case 'jpeg':
            type = ImageFileType.jpg;
            break;
          case 'png':
            type = ImageFileType.png;
            break;
          case 'gif':
            type = ImageFileType.gif;
            break;
          case 'tiff':
            type = ImageFileType.tiff;
            break;
          case 'heic':
            type = ImageFileType.heic;
            break;
          default:
            type = ImageFileType.other;
            break;
        }
      }
      return type ?? ImageFileType.other;
    }).then(lock.complete).catchError(lock.completeError);
    return lock.future;
  }

  static void _evictCache(AssetEntityImageProvider key) {
    // ignore: unnecessary_cast
    ((PaintingBinding.instance as PaintingBinding).imageCache as ImageCache)
        .evict(key);
  }

  @override
  bool operator ==(Object other) {
    if (other is! AssetEntityImageProvider) {
      return false;
    }
    if (identical(this, other)) {
      return true;
    }
    return entity == other.entity &&
        isOriginal == other.isOriginal &&
        thumbnailSize == other.thumbnailSize &&
        thumbnailFormat == other.thumbnailFormat &&
        frame == other.frame &&
        progressHandler == other.progressHandler;
  }

  @override
  int get hashCode =>
      entity.hashCode ^
      isOriginal.hashCode ^
      thumbnailSize.hashCode ^
      thumbnailFormat.hashCode ^
      frame.hashCode ^
      progressHandler.hashCode;
}

/// A widget that displays an [AssetEntity] image.
///
/// The widget uses [AssetEntityImageProvider] internally to resolve assets.
class AssetEntityImage extends Image {
  AssetEntityImage(
    AssetEntity entity, {
    bool isOriginal = true,
    ThumbnailSize? thumbnailSize = pmDefaultGridThumbnailSize,
    ThumbnailFormat thumbnailFormat = ThumbnailFormat.jpeg,
    int frame = 0,
    PMProgressHandler? progressHandler,
    Key? key,
    ImageFrameBuilder? frameBuilder,
    ImageLoadingBuilder? loadingBuilder,
    ImageErrorWidgetBuilder? errorBuilder,
    String? semanticLabel,
    bool excludeFromSemantics = false,
    double? width,
    double? height,
    Color? color,
    Animation<double>? opacity,
    BlendMode? colorBlendMode,
    BoxFit? fit,
    AlignmentGeometry alignment = Alignment.center,
    ImageRepeat repeat = ImageRepeat.noRepeat,
    Rect? centerSlice,
    bool matchTextDirection = false,
    bool gaplessPlayback = false,
    bool isAntiAlias = false,
    FilterQuality filterQuality = FilterQuality.low,
  }) : super(
          key: key,
          image: AssetEntityImageProvider(
            entity,
            isOriginal: isOriginal,
            thumbnailSize: thumbnailSize,
            thumbnailFormat: thumbnailFormat,
            frame: frame,
            progressHandler: progressHandler,
          ),
          frameBuilder: frameBuilder,
          loadingBuilder: loadingBuilder,
          errorBuilder: errorBuilder,
          semanticLabel: semanticLabel,
          excludeFromSemantics: excludeFromSemantics,
          width: width,
          height: height,
          color: color,
          opacity: opacity,
          colorBlendMode: colorBlendMode,
          fit: fit,
          alignment: alignment,
          repeat: repeat,
          centerSlice: centerSlice,
          matchTextDirection: matchTextDirection,
          gaplessPlayback: gaplessPlayback,
          isAntiAlias: isAntiAlias,
          filterQuality: filterQuality,
        );
}
