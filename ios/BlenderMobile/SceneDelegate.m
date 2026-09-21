#import "SceneDelegate.h"
#import "ViewController.h"
#import "BlenderHost.h"
#import <dlfcn.h>
#import <stdbool.h>

@interface SceneDelegate ()
@property (nonatomic, strong) id sdlSceneDelegate;
@end

static void BlenderStartEditor(void)
{
#ifdef BLENDER_IOS_HAS_NATIVE
  typedef void (*SetPumpFn)(bool);
  SetPumpFn setPump = (SetPumpFn)dlsym(RTLD_DEFAULT, "SDL_SetiOSEventPump");
  if (setPump != NULL) {
    setPump(true);
  }
  extern int blender_ios_start(int argc, char **argv);
  static char arg0[] = "blender";
  static char arg1[] = "--gpu-backend";
  static char arg2[] = "vulkan";
  char *argv[] = {arg0, arg1, arg2, NULL};
  blender_ios_start(3, argv);
#else
  (void)0;
#endif
}

@implementation SceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions
{
  /* This SDK refuses to launch without a scene. Newer SDL builds own that
   * scene themselves and start the editor. Older builds need us to start it. */
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
  dispatch_async(dispatch_get_main_queue(), ^{
    BlenderStartEditor();
  });
}

@end
