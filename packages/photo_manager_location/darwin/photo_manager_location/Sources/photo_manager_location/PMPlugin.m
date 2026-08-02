#import "PMPlugin.h"
#import "PMManager.h"

#import <Photos/Photos.h>

@implementation PMLocationPlugin {
    FlutterMethodChannel *channel;
    PMLocationManager *manager;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    PMLocationPlugin *plugin = [PMLocationPlugin new];
    [plugin registerPlugin:registrar];
}

- (void)registerPlugin:(NSObject<FlutterPluginRegistrar> *)registrar {
    channel = [FlutterMethodChannel
        methodChannelWithName:@"com.fluttercandies/photo_manager_location"
              binaryMessenger:[registrar messenger]];
    manager = [PMLocationManager new];

    __weak typeof(self) weakSelf = self;
    [channel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
        [weakSelf handleMethodCall:call result:result];
    }];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString *method = call.method;

    // Routes the manager's outcome back onto the main thread as either the
    // asset map or a FlutterError.
    void (^replyBlock)(NSDictionary *_Nullable, NSObject *_Nullable) =
        ^(NSDictionary *_Nullable map, NSObject *_Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (map != nil) {
                    result(map);
                    return;
                }
                if ([error isKindOfClass:[NSError class]]) {
                    NSError *nsError = (NSError *)error;
                    result([FlutterError
                        errorWithCode:[NSString stringWithFormat:@"%ld", (long)nsError.code]
                               message:nsError.localizedDescription
                               details:nsError.userInfo]);
                    return;
                }
                result([FlutterError
                    errorWithCode:@"photo_manager_location_save_failed"
                           message:[NSString stringWithFormat:@"%@", error]
                           details:nil]);
            });
        };

    if ([method isEqualToString:@"saveImage"]) {
        NSData *data = [(id)call.arguments[@"image"] data];
        NSString *filename = call.arguments[@"filename"];
        NSString *desc = call.arguments[@"desc"];
        NSNumber *latitude = call.arguments[@"latitude"];
        NSNumber *longitude = call.arguments[@"longitude"];
        NSNumber *creationDate = call.arguments[@"creationDate"];
        [manager saveImage:data
                  filename:filename
                      desc:desc
                  latitude:latitude
                 longitude:longitude
              creationDate:creationDate
                     block:replyBlock];
    } else if ([method isEqualToString:@"saveImageWithPath"]) {
        NSString *path = call.arguments[@"path"];
        NSString *filename = call.arguments[@"title"];
        NSString *desc = call.arguments[@"desc"];
        NSNumber *latitude = call.arguments[@"latitude"];
        NSNumber *longitude = call.arguments[@"longitude"];
        NSNumber *creationDate = call.arguments[@"creationDate"];
        [manager saveImageWithPath:path
                          filename:filename
                              desc:desc
                          latitude:latitude
                         longitude:longitude
                      creationDate:creationDate
                             block:replyBlock];
    } else if ([method isEqualToString:@"saveVideo"]) {
        NSString *videoPath = call.arguments[@"path"];
        NSString *filename = call.arguments[@"title"];
        NSString *desc = call.arguments[@"desc"];
        NSNumber *latitude = call.arguments[@"latitude"];
        NSNumber *longitude = call.arguments[@"longitude"];
        NSNumber *creationDate = call.arguments[@"creationDate"];
        [manager saveVideo:videoPath
                  filename:filename
                      desc:desc
                  latitude:latitude
                 longitude:longitude
              creationDate:creationDate
                     block:replyBlock];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

@end
