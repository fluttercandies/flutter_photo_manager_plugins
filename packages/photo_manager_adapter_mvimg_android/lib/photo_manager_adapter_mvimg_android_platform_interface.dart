import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'photo_manager_adapter_mvimg_android_method_channel.dart';

abstract class PhotoManagerAdapterMvimgAndroidPlatform extends PlatformInterface {
  /// Constructs a PhotoManagerAdapterMvimgAndroidPlatform.
  PhotoManagerAdapterMvimgAndroidPlatform() : super(token: _token);

  static final Object _token = Object();

  static PhotoManagerAdapterMvimgAndroidPlatform _instance = MethodChannelPhotoManagerAdapterMvimgAndroid();

  /// The default instance of [PhotoManagerAdapterMvimgAndroidPlatform] to use.
  ///
  /// Defaults to [MethodChannelPhotoManagerAdapterMvimgAndroid].
  static PhotoManagerAdapterMvimgAndroidPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [PhotoManagerAdapterMvimgAndroidPlatform] when
  /// they register themselves.
  static set instance(PhotoManagerAdapterMvimgAndroidPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
