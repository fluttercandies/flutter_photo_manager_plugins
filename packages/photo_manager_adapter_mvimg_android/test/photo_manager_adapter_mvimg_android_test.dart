import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager_adapter_mvimg_android/photo_manager_adapter_mvimg_android.dart';
import 'package:photo_manager_adapter_mvimg_android/photo_manager_adapter_mvimg_android_platform_interface.dart';
import 'package:photo_manager_adapter_mvimg_android/photo_manager_adapter_mvimg_android_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPhotoManagerAdapterMvimgAndroidPlatform
    with MockPlatformInterfaceMixin
    implements PhotoManagerAdapterMvimgAndroidPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final PhotoManagerAdapterMvimgAndroidPlatform initialPlatform = PhotoManagerAdapterMvimgAndroidPlatform.instance;

  test('$MethodChannelPhotoManagerAdapterMvimgAndroid is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelPhotoManagerAdapterMvimgAndroid>());
  });

  test('getPlatformVersion', () async {
    PhotoManagerAdapterMvimgAndroid photoManagerAdapterMvimgAndroidPlugin = PhotoManagerAdapterMvimgAndroid();
    MockPhotoManagerAdapterMvimgAndroidPlatform fakePlatform = MockPhotoManagerAdapterMvimgAndroidPlatform();
    PhotoManagerAdapterMvimgAndroidPlatform.instance = fakePlatform;

    expect(await photoManagerAdapterMvimgAndroidPlugin.getPlatformVersion(), '42');
  });
}
