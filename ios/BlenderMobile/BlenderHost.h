#import <Foundation/Foundation.h>

@interface BlenderHost : NSObject
+ (void)prepareRuntime;
+ (BOOL)canLaunchBlender;
+ (int)runBlenderWithArgc:(int)argc argv:(char **)argv;
@end
