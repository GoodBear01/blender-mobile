#import "BlenderHost.h"
#import <stdlib.h>
#import <unistd.h>

#ifdef BLENDER_IOS_HAS_NATIVE
extern int blender_ios_main(int argc, char **argv);
#endif

static NSString *const kRuntimeVersion = @"5.2.0-ios1";

@implementation BlenderHost

+ (NSURL *)documentsURL
{
  return [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                              inDomains:NSUserDomainMask].firstObject;
}

+ (void)setEnv:(const char *)name value:(NSString *)value
{
  if (value.length == 0) {
    return;
  }
  setenv(name, value.UTF8String, 1);
}

+ (void)prepareRuntime
{
  NSFileManager *fm = NSFileManager.defaultManager;
  NSURL *docs = [self documentsURL];
  NSURL *runtime = [docs URLByAppendingPathComponent:@"blender" isDirectory:YES];
  NSURL *marker = [runtime URLByAppendingPathComponent:@"runtime_version.txt"];
  NSString *existing = [NSString stringWithContentsOfURL:marker
                                                encoding:NSUTF8StringEncoding
                                                   error:nil];
  NSURL *bundleRuntime = [[NSBundle mainBundle] URLForResource:@"Runtime" withExtension:nil];
  if (bundleRuntime && ![existing isEqualToString:kRuntimeVersion]) {
    [fm removeItemAtURL:runtime error:nil];
    [fm createDirectoryAtURL:runtime withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *from = [bundleRuntime URLByAppendingPathComponent:@"blender"];
    if ([fm fileExistsAtPath:from.path]) {
      [fm copyItemAtURL:from toURL:[runtime URLByAppendingPathComponent:@"blender"] error:nil];
    }
    [kRuntimeVersion writeToURL:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
  }
  [fm createDirectoryAtURL:[docs URLByAppendingPathComponent:@"Blender" isDirectory:YES]
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];

  NSString *home = docs.path;
  NSString *resources = [runtime URLByAppendingPathComponent:@"blender/5.2"].path;
  [self setEnv:"HOME" value:home];
  [self setEnv:"TMPDIR" value:NSTemporaryDirectory()];
  [self setEnv:"BLENDER_IOS" value:@"1"];
  [self setEnv:"BLENDER_MOBILE" value:@"1"];
  [self setEnv:"BLENDER_USER_RESOURCES" value:home];
  [self setEnv:"BLENDER_SYSTEM_RESOURCES" value:resources];
  [self setEnv:"BLENDER_SYSTEM_SCRIPTS" value:[resources stringByAppendingPathComponent:@"scripts"]];
  [self setEnv:"BLENDER_IOS_DOCUMENTS" value:home];
  [self setEnv:"BLENDER_ANDROID_STORAGE" value:home];
  [self setEnv:"BLENDER_ANDROID_BLENDS" value:[home stringByAppendingPathComponent:@"Blender"]];
  [self setEnv:"BLENDER_ANDROID_DOCUMENTS" value:home];
  [self setEnv:"BLENDER_ANDROID_DOWNLOADS" value:home];
}

+ (BOOL)canLaunchBlender
{
#ifdef BLENDER_IOS_HAS_NATIVE
  return YES;
#else
  return NO;
#endif
}

+ (int)runBlenderWithArgc:(int)argc argv:(char **)argv
{
#ifdef BLENDER_IOS_HAS_NATIVE
  static const char *fallback[] = {"blender", "--gpu-backend", "vulkan", NULL};
  if (argc < 1 || argv == NULL) {
    argc = 3;
    argv = (char **)fallback;
  }
  return blender_ios_main(argc, argv);
#else
  (void)argc;
  (void)argv;
  return 1;
#endif
}

@end
