import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'photo_manager_adapter_mvimg_android_platform_interface.dart';

/// An implementation of [PhotoManagerAdapterMvimgAndroidPlatform] that uses method channels.
class MethodChannelPhotoManagerAdapterMvimgAndroid extends PhotoManagerAdapterMvimgAndroidPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('photo_manager_adapter_mvimg_android');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
