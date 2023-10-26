# image_provider for photo_manager

The package is a plugin for [photo_manager][].

Its function is to make it easier to use `ImageProvider` in flutter
to load images provided by photo_manager.

It was originally part of [photo_manager][], However, as the flutter sdk is updated, the obsolescence of the old API will cause incompatibility in photo_manager.

So, the parts related to image_provider are split here, which is used to ensure the compatibility between the photo_manager version and the flutter version.

See [doc of compatibility][compatibility] to get plugin version compatibility information.

## Usage

```yaml
dependencies:
  photo_manager_image_provider: #version
```

```dart
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';


Widget buildWidget(AssetEntity entity) {
  return Image(
    image: AssetEntityImageProvider(entity),
  );
}

Widget buildWidget(AssetEntity entity) {
  return AssetEntityImage(entity);
}

```

[photo_manager]: https://pub.dev/packages/photo_manager
[compatibility]: https://fluttercandies.github.io/flutter_photo_manager_plugins/image_provider/compatibility/
