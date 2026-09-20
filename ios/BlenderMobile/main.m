#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "BlenderHost.h"

int main(int argc, char *argv[])
{
  @autoreleasepool {
    [BlenderHost prepareRuntime];
    if ([BlenderHost canLaunchBlender]) {
      return [BlenderHost runBlenderWithArgc:argc argv:argv];
    }
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}
