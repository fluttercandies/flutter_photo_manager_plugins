import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_native_image/photo_manager_native_image.dart';

AssetEntity _image({int modified = 0}) => AssetEntity(
      id: 'a',
      typeInt: AssetType.image.index,
      width: 4032,
      height: 3024,
      modifiedDateSecond: modified,
    );

List<MethodCall> _mockPlatformViews() {
  final List<MethodCall> creates = <MethodCall>[];
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform_views,
      (MethodCall call) async {
    if (call.method == 'create') {
      creates.add(call);
    }
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });
  return creates;
}

Widget _host(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS builds a UiKitView with assetId and size', (tester) async {
    _mockPlatformViews();
    await tester.pumpWidget(_host(NativeAssetHdrView(_image(), size: 2217)));

    final UiKitView view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, 'photo_manager_native_image/hdr_view');
    expect(view.creationParams, <String, Object?>{'assetId': 'a', 'size': 2217});
  },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('Android builds a hybrid composition PlatformViewLink',
      (tester) async {
    final List<MethodCall> creates = _mockPlatformViews();
    await tester.pumpWidget(_host(NativeAssetHdrView(_image(), size: 2217)));
    await tester.pump();

    final PlatformViewLink link =
        tester.widget<PlatformViewLink>(find.byType(PlatformViewLink));
    expect(link.viewType, 'photo_manager_native_image/hdr_view');
    expect(creates, hasLength(1));
    final Map<Object?, Object?> args =
        creates.single.arguments as Map<Object?, Object?>;
    expect(args['viewType'], 'photo_manager_native_image/hdr_view');
    expect(args['hybrid'], true);
  },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('other platforms build nothing native', (tester) async {
    await tester.pumpWidget(_host(NativeAssetHdrView(_image(), size: 2217)));

    expect(find.byType(UiKitView), findsNothing);
    expect(find.byType(PlatformViewLink), findsNothing);
    expect(find.byType(SizedBox), findsOneWidget);
  },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('never takes pointers', (tester) async {
    _mockPlatformViews();
    await tester.pumpWidget(_host(NativeAssetHdrView(_image(), size: 2217)));

    final IgnorePointer ignore = tester.widget<IgnorePointer>(
      find.ancestor(
        of: find.byType(UiKitView),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(ignore.ignoring, true);
  },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('a new size or modified date makes a new view', (tester) async {
    final List<MethodCall> creates = _mockPlatformViews();
    await tester.pumpWidget(_host(NativeAssetHdrView(_image(), size: 2000)));
    await tester.pump();
    expect(creates, hasLength(1));

    await tester.pumpWidget(_host(NativeAssetHdrView(_image(), size: 2217)));
    await tester.pump();
    expect(creates, hasLength(2));

    await tester
        .pumpWidget(_host(NativeAssetHdrView(_image(modified: 9), size: 2217)));
    await tester.pump();
    expect(creates, hasLength(3));
  },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('asserts on a video entity', (tester) async {
    final AssetEntity video = AssetEntity(
      id: 'v',
      typeInt: AssetType.video.index,
      width: 10,
      height: 10,
      duration: 3,
    );
    await tester.pumpWidget(_host(NativeAssetHdrView(video, size: 100)));
    expect(tester.takeException(), isA<AssertionError>());
  });
}
