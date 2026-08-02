#import <TargetConditionals.h>

#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Flutter plugin that owns the `com.fluttercandies/photo_manager_location`
/// method channel and saves assets with location coordinates on iOS/macOS.
///
/// This is the opt-in companion to the core `photo_manager` `PMPlugin`. Its
/// class name is intentionally distinct so both plugins can be linked into the
/// same application without symbol collisions.
@interface PMLocationPlugin : NSObject <FlutterPlugin>

/// Wires up the method channel and manager, mirroring the core plugin.
- (void)registerPlugin:(NSObject <FlutterPluginRegistrar> *)registrar;

@end

NS_ASSUME_NONNULL_END
