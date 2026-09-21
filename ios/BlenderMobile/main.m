#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "BlenderHost.h"

int main(int argc, char *argv[])
{
  @autoreleasepool {
    [BlenderHost prepareRuntime];
    /* Our app delegate adopts UIScene. SDL_RunApp installs a delegate that
     * does not, and this SDK then refuses to launch. */
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}
