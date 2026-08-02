#import "PMManager.h"

#import <CoreLocation/CoreLocation.h>
#import <Photos/Photos.h>

@implementation PMLocationManager

#pragma mark - Helpers

/// Returns YES when the incoming argument is a real value rather than
/// `nil` / `NSNull` (the two ways the Dart side encodes "not provided").
static BOOL PMLocationHasValue(NSNumber *number) {
    return number != nil && ![number isKindOfClass:[NSNull class]];
}

/// Builds the photo_manager asset dictionary for a freshly-saved asset.
///
/// Mirrors `PMConvertUtils +convertPHAssetToMap:needTitle:` with
/// `needTitle:NO` — the exact field set the Dart converter expects. The core
/// plugin's private headers cannot be imported here, so the map is built
/// directly from the `PHAsset`.
- (NSDictionary *)mapFromAsset:(PHAsset *)asset {
    long createDt = (long)asset.creationDate.timeIntervalSince1970;
    long modifiedDt = asset.modificationDate != nil
        ? (long)asset.modificationDate.timeIntervalSince1970
        : 0;

    int typeInt = 0;
    switch (asset.mediaType) {
        case PHAssetMediaTypeImage:
            typeInt = 1;
            break;
        case PHAssetMediaTypeVideo:
            typeInt = 2;
            break;
        case PHAssetMediaTypeAudio:
            typeInt = 3;
            break;
        default:
            break;
    }

    CLLocation *location = asset.location;
    return @{
        @"id": asset.localIdentifier ?: @"",
        @"createDt": @(createDt),
        @"width": @(asset.pixelWidth),
        @"height": @(asset.pixelHeight),
        @"favorite": @(asset.favorite),
        @"duration": @(lround(asset.duration)),
        @"type": @(typeInt),
        @"modifiedDt": @(modifiedDt),
        @"lng": location != nil ? @(location.coordinate.longitude) : [NSNull null],
        @"lat": location != nil ? @(location.coordinate.latitude) : [NSNull null],
        @"title": @"",
        @"subtype": @(asset.mediaSubtypes),
    };
}

/// Reports the save outcome through [block]: the asset map on success, or the
/// supplied [error] / a synthesized one when the asset could not be resolved.
- (void)replyWithAssetId:(NSString *)assetId
                   error:(nullable NSError *)error
                   block:(PMLocationAssetBlock)block {
    if (error != nil) {
        block(nil, error);
        return;
    }
    if (assetId.length == 0) {
        block(nil,
              [NSError errorWithDomain:@"PMLocation"
                                  code:-1
                              userInfo:@{
                                  NSLocalizedDescriptionKey:
                                      @"Save succeeded but no asset identifier was returned."
                              }]);
        return;
    }
    PHFetchResult<PHAsset *> *result =
        [PHAsset fetchAssetsWithLocalIdentifiers:@[assetId] options:nil];
    PHAsset *asset = result.firstObject;
    if (asset == nil) {
        block(nil,
              [NSError errorWithDomain:@"PMLocation"
                                  code:-2
                              userInfo:@{
                                  NSLocalizedDescriptionKey: [NSString
                                      stringWithFormat:
                                          @"Could not fetch the saved asset %@.", assetId]
                              }]);
        return;
    }
    block([self mapFromAsset:asset], nil);
}

#pragma mark - Save

- (void)saveImage:(NSData *)data
         filename:(NSString *)filename
             desc:(NSString *)desc
         latitude:(NSNumber *)latitude
        longitude:(NSNumber *)longitude
     creationDate:(NSNumber *)creationDate
            block:(PMLocationAssetBlock)block {
    __block NSString *assetId = nil;
    __weak typeof(self) weakSelf = self;
    [[PHPhotoLibrary sharedPhotoLibrary]
        performChanges:^{
            PHAssetCreationRequest *request =
                [PHAssetCreationRequest creationRequestForAsset];
            PHAssetResourceCreationOptions *options =
                [PHAssetResourceCreationOptions new];
            [options setOriginalFilename:filename];
            [request addResourceWithType:PHAssetResourceTypePhoto
                                    data:data
                                 options:options];

            // Set location if provided.
            if (PMLocationHasValue(latitude) && PMLocationHasValue(longitude)) {
                CLLocation *location = [[CLLocation alloc]
                    initWithLatitude:[latitude doubleValue]
                          longitude:[longitude doubleValue]];
                [request setLocation:location];
            }

            // Set creation date if provided.
            if (PMLocationHasValue(creationDate)) {
                NSDate *date = [NSDate
                    dateWithTimeIntervalSince1970:[creationDate doubleValue] / 1000.0];
                [request setCreationDate:date];
            }

            assetId = request.placeholderForCreatedAsset.localIdentifier;
        }
        completionHandler:^(BOOL success, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            [strongSelf replyWithAssetId:assetId
                                   error:success ? nil : error
                                   block:block];
        }];
}

- (void)saveImageWithPath:(NSString *)path
                 filename:(NSString *)filename
                     desc:(NSString *)desc
                 latitude:(NSNumber *)latitude
                longitude:(NSNumber *)longitude
             creationDate:(NSNumber *)creationDate
                    block:(PMLocationAssetBlock)block {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        block(nil,
              [NSError errorWithDomain:@"PMLocation"
                                  code:-3
                              userInfo:@{
                                  NSLocalizedDescriptionKey:
                                      [NSString stringWithFormat:@"File does not exist at %@", path]
                              }]);
        return;
    }

    NSURL *fileURL = [NSURL fileURLWithPath:path];
    __block NSString *assetId = nil;
    __weak typeof(self) weakSelf = self;
    [[PHPhotoLibrary sharedPhotoLibrary]
        performChanges:^{
            PHAssetCreationRequest *request =
                [PHAssetCreationRequest creationRequestForAsset];
            PHAssetResourceCreationOptions *options =
                [PHAssetResourceCreationOptions new];
            if (filename) {
                [options setOriginalFilename:filename];
            }
            [request addResourceWithType:PHAssetResourceTypePhoto
                                fileURL:fileURL
                                 options:options];

            if (PMLocationHasValue(latitude) && PMLocationHasValue(longitude)) {
                CLLocation *location = [[CLLocation alloc]
                    initWithLatitude:[latitude doubleValue]
                          longitude:[longitude doubleValue]];
                [request setLocation:location];
            }

            if (PMLocationHasValue(creationDate)) {
                NSDate *date = [NSDate
                    dateWithTimeIntervalSince1970:[creationDate doubleValue] / 1000.0];
                [request setCreationDate:date];
            }

            assetId = request.placeholderForCreatedAsset.localIdentifier;
        }
        completionHandler:^(BOOL success, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            [strongSelf replyWithAssetId:assetId
                                   error:success ? nil : error
                                   block:block];
        }];
}

- (void)saveVideo:(NSString *)path
         filename:(NSString *)filename
             desc:(NSString *)desc
         latitude:(NSNumber *)latitude
        longitude:(NSNumber *)longitude
     creationDate:(NSNumber *)creationDate
            block:(PMLocationAssetBlock)block {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        block(nil,
              [NSError errorWithDomain:@"PMLocation"
                                  code:-3
                              userInfo:@{
                                  NSLocalizedDescriptionKey:
                                      [NSString stringWithFormat:@"File does not exist at %@", path]
                              }]);
        return;
    }

    NSURL *fileURL = [NSURL fileURLWithPath:path];
    __block NSString *assetId = nil;
    __weak typeof(self) weakSelf = self;
    [[PHPhotoLibrary sharedPhotoLibrary]
        performChanges:^{
            PHAssetCreationRequest *request =
                [PHAssetCreationRequest creationRequestForAsset];
            PHAssetResourceCreationOptions *options =
                [PHAssetResourceCreationOptions new];
            if (filename) {
                [options setOriginalFilename:filename];
            }
            [request addResourceWithType:PHAssetResourceTypeVideo
                                fileURL:fileURL
                                 options:options];

            if (PMLocationHasValue(latitude) && PMLocationHasValue(longitude)) {
                CLLocation *location = [[CLLocation alloc]
                    initWithLatitude:[latitude doubleValue]
                          longitude:[longitude doubleValue]];
                [request setLocation:location];
            }

            if (PMLocationHasValue(creationDate)) {
                NSDate *date = [NSDate
                    dateWithTimeIntervalSince1970:[creationDate doubleValue] / 1000.0];
                [request setCreationDate:date];
            }

            assetId = request.placeholderForCreatedAsset.localIdentifier;
        }
        completionHandler:^(BOOL success, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            [strongSelf replyWithAssetId:assetId
                                   error:success ? nil : error
                                   block:block];
        }];
}

@end
