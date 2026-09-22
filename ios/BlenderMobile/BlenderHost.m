#import "BlenderHost.h"
#import <dlfcn.h>
#import <stdlib.h>
#import <unistd.h>

#ifdef BLENDER_IOS_HAS_NATIVE
extern int blender_ios_main(int argc, char **argv);
#endif

static NSString *const kRuntimeVersion = @"5.2.0-ios-full5";

static void *g_blender_handle;
static int (*g_blender_main)(int, char **);

@implementation BlenderHost

+ (NSURL *)documentsURL
{
  return [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                              inDomains:NSUserDomainMask].firstObject;
}

+ (void)setEnv:(const char *)name value:(NSString *)value
{
  if (name == NULL || value.length == 0) {
    return;
  }
  setenv(name, value.UTF8String, 1);
}

+ (NSString *)frameworksDir
{
  return [[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks"] copy];
}

+ (void *)loadBundleLib:(NSString *)name
{
  NSString *path = [[self frameworksDir] stringByAppendingPathComponent:name];
  if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
    return NULL;
  }
  void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
  if (handle == NULL) {
    NSLog(@"BlenderHost: dlopen %@ failed: %s", name, dlerror());
  }
  return handle;
}

+ (void)loadNativeLibraries
{
  if (g_blender_main != NULL) {
    return;
  }
#ifdef BLENDER_IOS_HAS_NATIVE
  /* libblender is already linked. Do not dlopen Python or SDL again.
   * A second copy of libpython aborts during its startup constructors. */
  g_blender_main = blender_ios_main;
  return;
#endif
  [self loadBundleLib:@"MoltenVK.framework/MoltenVK"];
  [self loadBundleLib:@"libMoltenVK.dylib"];
  [self loadBundleLib:@"libSDL3.dylib"];
  [self loadBundleLib:@"SDL3.framework/SDL3"];
  [self loadBundleLib:@"libpython3.13.dylib"];
  [self loadBundleLib:@"Python.framework/Python"];
  [self loadBundleLib:@"libtbb.dylib"];
  g_blender_handle = [self loadBundleLib:@"libblender.dylib"];
  if (g_blender_handle == NULL) {
    g_blender_handle = dlopen("@rpath/libblender.dylib", RTLD_NOW | RTLD_GLOBAL);
  }
  if (g_blender_handle == NULL) {
    NSLog(@"BlenderHost: libblender.dylib is not in this app. Run ./ios/scripts/build_full_app.sh on the Mac.");
    return;
  }
  g_blender_main = (int (*)(int, char **))dlsym(g_blender_handle, "blender_ios_main");
  if (g_blender_main == NULL) {
    NSLog(@"BlenderHost: blender_ios_main missing: %s", dlerror());
  }
}

+ (void)prepareRuntime
{
  NSFileManager *fm = NSFileManager.defaultManager;
  NSURL *docs = [self documentsURL];
  if (docs == nil) {
    return;
  }

  NSURL *blenderDir = [docs URLByAppendingPathComponent:@"Blender" isDirectory:YES];
  [fm createDirectoryAtURL:blenderDir withIntermediateDirectories:YES attributes:nil error:nil];

  NSURL *runtime = [docs URLByAppendingPathComponent:@"blender" isDirectory:YES];
  NSURL *marker = [runtime URLByAppendingPathComponent:@"runtime_version.txt"];
  NSString *existing = [NSString stringWithContentsOfURL:marker
                                                encoding:NSUTF8StringEncoding
                                                   error:nil];
  NSURL *bundleRuntime = [[NSBundle mainBundle] URLForResource:@"Runtime" withExtension:nil];
  NSString *bundlePython = nil;
  if (bundleRuntime != nil) {
    bundlePython = [[[[bundleRuntime URLByAppendingPathComponent:@"blender"]
        URLByAppendingPathComponent:@"5.2"]
        URLByAppendingPathComponent:@"python"] path];
  }
  NSString *bundleEncodings =
      [bundlePython stringByAppendingPathComponent:@"lib/python3.13/encodings/__init__.py"];
  BOOL bundleHasPython = bundlePython != nil && [fm fileExistsAtPath:bundleEncodings];
  NSString *docEncodings = [[[runtime URLByAppendingPathComponent:@"blender/5.2/python"]
      URLByAppendingPathComponent:@"lib/python3.13/encodings/__init__.py"] path];
  if (bundleRuntime != nil &&
      (![existing isEqualToString:kRuntimeVersion] ||
       (bundleHasPython && ![fm fileExistsAtPath:docEncodings]))) {
    [fm removeItemAtURL:runtime error:nil];
    [fm createDirectoryAtURL:runtime withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *from = [bundleRuntime URLByAppendingPathComponent:@"blender"];
    if ([fm fileExistsAtPath:from.path]) {
      [fm copyItemAtURL:from toURL:[runtime URLByAppendingPathComponent:@"blender"] error:nil];
    }
  }

  NSString *home = docs.path;
  NSString *resources = [runtime URLByAppendingPathComponent:@"blender/5.2"].path;
  NSString *pythonHome = [resources stringByAppendingPathComponent:@"python"];
  NSString *encodings = [pythonHome stringByAppendingPathComponent:@"lib/python3.13/encodings/__init__.py"];
  if (![fm fileExistsAtPath:encodings] && bundleRuntime != nil) {
    NSString *bundled = [[[[bundleRuntime URLByAppendingPathComponent:@"blender"]
        URLByAppendingPathComponent:@"5.2"]
        URLByAppendingPathComponent:@"python"] path];
    NSString *bundledEnc = [bundled stringByAppendingPathComponent:@"lib/python3.13/encodings/__init__.py"];
    if ([fm fileExistsAtPath:bundledEnc]) {
      pythonHome = bundled;
      encodings = bundledEnc;
    }
  }
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
  if ([fm fileExistsAtPath:encodings]) {
    [self setEnv:"BLENDER_SYSTEM_PYTHON" value:pythonHome];
    [self setEnv:"PYTHONHOME" value:pythonHome];
    [kRuntimeVersion writeToURL:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"BlenderHost: Python stdlib %@", pythonHome);
  }
  else {
    NSLog(@"BlenderHost: missing Python encodings at %@", encodings);
  }
  [self loadNativeLibraries];
}

+ (BOOL)canLaunchBlender
{
  [self loadNativeLibraries];
  return g_blender_main != NULL;
}

+ (int)runBlenderWithArgc:(int)argc argv:(char **)argv
{
  [self loadNativeLibraries];
  if (g_blender_main == NULL) {
    return 1;
  }
  static const char *fallback[] = {"blender", "--gpu-backend", "vulkan", NULL};
  if (argc < 1 || argv == NULL) {
    argc = 3;
    argv = (char **)fallback;
  }
  return g_blender_main(argc, argv);
}

@end
