
import 'photo_manager_adapter_mvimg_android_platform_interface.dart';

class PhotoManagerAdapterMvimgAndroid {
  Future<String?> getPlatformVersion() {
    return PhotoManagerAdapterMvimgAndroidPlatform.instance.getPlatformVersion();
  }
}
