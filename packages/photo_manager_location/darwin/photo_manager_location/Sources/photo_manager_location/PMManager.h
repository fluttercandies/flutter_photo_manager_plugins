#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Reports the result of a location-tagged save.
///
/// On success `map` holds the asset dictionary (the `convertPHAssetToMap`
/// field set) and `error` is `nil`; on failure `map` is `nil` and `error`
/// describes what went wrong.
typedef void (^PMLocationAssetBlock)(NSDictionary *_Nullable map,
                                     NSObject *_Nullable error);

/// Performs the CoreLocation-touching asset saves.
///
/// The class name is intentionally distinct from the core `PMManager` so both
/// can coexist in one application binary.
@interface PMLocationManager : NSObject

/// Save image [data] with an optional filename and location.
- (void)saveImage:(NSData *)data
         filename:(NSString *)filename
             desc:(NSString *)desc
         latitude:(NSNumber *)latitude
        longitude:(NSNumber *)longitude
     creationDate:(NSNumber *)creationDate
            block:(PMLocationAssetBlock)block;

/// Save the image at [path] with an optional filename and location.
- (void)saveImageWithPath:(NSString *)path
                 filename:(NSString *)filename
                     desc:(NSString *)desc
                 latitude:(NSNumber *)latitude
                longitude:(NSNumber *)longitude
             creationDate:(NSNumber *)creationDate
                    block:(PMLocationAssetBlock)block;

/// Save the video at [path] with an optional filename and location.
- (void)saveVideo:(NSString *)path
         filename:(NSString *)filename
             desc:(NSString *)desc
         latitude:(NSNumber *)latitude
        longitude:(NSNumber *)longitude
     creationDate:(NSNumber *)creationDate
            block:(PMLocationAssetBlock)block;

@end

NS_ASSUME_NONNULL_END
