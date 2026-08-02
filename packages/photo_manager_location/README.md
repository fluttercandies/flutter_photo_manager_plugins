# photo_manager_location

An opt-in plugin for [photo_manager][] that links CoreLocation to save assets
with geographic coordinates on iOS/macOS.

## Why

The core `photo_manager` package no longer links CoreLocation, so apps that do
not save assets with location are not flagged by Apple's static scan (which
treats any CoreLocation reference as requiring an
`NSLocationWhenInUseUsageDescription` purpose string — even from unused code
paths).

If you need to save photos or videos tagged with GPS coordinates on iOS/macOS,
install this plugin. It links CoreLocation explicitly and therefore requires
you to add the purpose string to your `Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Describe why your app needs to save location with media.</string>
```

Android is unaffected — location saving via MediaStore remains in the core
package.

## Usage

```dart
import 'package:photo_manager_location/photo_manager_location.dart';

final asset = await PhotoManagerLocation.editor.saveImage(
  bytes,
  filename: 'photo.jpg',
  latitude: 37.7749,
  longitude: -122.4194,
);
```

[photo_manager]: https://pub.dev/packages/photo_manager
