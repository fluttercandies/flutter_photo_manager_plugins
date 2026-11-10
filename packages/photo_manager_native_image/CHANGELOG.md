## 0.2.0

- `NativeAssetHdrView`: an opt-in native view that draws an image with its
  gain map applied on HDR displays (iOS 17+ `UIImageView` with
  `preferredImageDynamicRange: .high`; Android 14+ `ImageView` in a Hybrid
  Composition platform view). It stays transparent for SDR photos, on older
  OS versions and on failure, so it is meant to sit above a regular image.
  The Android activity window must be in `COLOR_MODE_HDR`; the plugin does
  not change it.
- Existing API unchanged.

## 0.1.0

- `NativeImageProvider`, `NativeAssetImage`, `NativeImageException` /
  `NativeImageErrorCode` (the whole public API): load a
  `photo_manager` `AssetEntity` thumbnail as native RGBA pixels handed to
  Flutter through `dart:ffi` and `ImageDescriptor.raw`, with no JPEG round
  trip.
- iOS: `PHImageManager.requestImage` on a worker queue, `vImage` downscale,
  XPC reconnect retry, `icloud_not_downloaded` classification, low-priority
  queue for network attempts; cancelling a network attempt stops its iCloud
  download.
- iCloud-only assets: local first, then one network attempt only when
  PhotoKit needs it. Nothing to configure.
- Android: MediaStore system thumbnail or the original through `ImageDecoder`
  on API 29+, decoded to the requested size in sRGB,
  `MediaStore.*.Thumbnails` and `BitmapFactory` with orientation correction on
  API 26–28, JNI `malloc` buffers. Video thumbnails smaller than the request
  fall back to a `MediaMetadataRetriever` frame sized from the video, and an
  unreadable cached system thumbnail falls back to the source.
- Flutter 3.24 or later; Swift Package Manager builds need Flutter 3.44.
- Decoded pixels capped at `size² × 4`, so panoramas stay bounded.
- Cancellation that recognises the `ImageCache` listener, so scrolled-away
  cells stop their native work without false cancels on `imageCache.clear()`.
