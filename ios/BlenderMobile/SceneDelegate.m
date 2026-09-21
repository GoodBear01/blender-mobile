#import "SceneDelegate.h"
#import "ViewController.h"
#import "BlenderHost.h"

@interface SceneDelegate ()
@property (nonatomic, strong) id sdlSceneDelegate;
@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions
{
  /* This SDK refuses to launch without a scene. Newer SDL builds own that
   * scene themselves; older builds still need a window here. */
  Class sdlClass = NSClassFromString(@"SDLUIKitSceneDelegate");
  if (sdlClass != Nil) {
    self.sdlSceneDelegate = [[sdlClass alloc] init];
    if ([self.sdlSceneDelegate respondsToSelector:@selector(scene:willConnectToSession:options:)]) {
      [self.sdlSceneDelegate scene:scene willConnectToSession:session options:connectionOptions];
      return;
    }
  }

  if (![scene isKindOfClass:[UIWindowScene class]]) {
    return;
  }
  UIWindowScene *windowScene = (UIWindowScene *)scene;
  self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
  self.window.backgroundColor = [UIColor colorWithRed:0.09 green:0.09 blue:0.09 alpha:1.0];
  self.window.rootViewController = [[ViewController alloc] init];
  [self.window makeKeyAndVisible];
  [BlenderHost prepareRuntime];
}

@end
