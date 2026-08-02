## 1.0.0

- Initial release.
- Adds `PhotoManagerLocation.editor` with `saveImage`, `saveImageWithPath`,
  and `saveVideo` for saving assets with geographic coordinates on iOS/macOS.
- Links CoreLocation so that the core `photo_manager` package can stay
  CoreLocation-free (issue
  [flutter_photo_manager#1428](https://github.com/fluttercandies/flutter_photo_manager/issues/1428)).
