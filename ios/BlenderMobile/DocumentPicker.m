#import "DocumentPicker.h"
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface IOSDocumentPickerShim : NSObject <UIDocumentPickerDelegate>
@end

static IOSDocumentPickerShim *g_picker_shim;

static IOSDocumentPickerShim *picker_shim(void)
{
  if (g_picker_shim == nil) {
    g_picker_shim = [[IOSDocumentPickerShim alloc] init];
  }
  return g_picker_shim;
}

static void copy_url_into_documents(NSURL *url)
{
  NSFileManager *fm = NSFileManager.defaultManager;
  NSURL *docs = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
  NSURL *blenderDir = [docs URLByAppendingPathComponent:@"Blender" isDirectory:YES];
  [fm createDirectoryAtURL:blenderDir withIntermediateDirectories:YES attributes:nil error:nil];
  BOOL access = [url startAccessingSecurityScopedResource];
  NSString *name = url.lastPathComponent ?: @"import.blend";
  NSURL *dest = [blenderDir URLByAppendingPathComponent:name];
  [fm removeItemAtURL:dest error:nil];
  NSError *error = nil;
  [fm copyItemAtURL:url toURL:dest error:&error];
  if (access) {
    [url stopAccessingSecurityScopedResource];
  }
  if (error == nil) {
    NSURL *pending = [docs URLByAppendingPathComponent:@"pending_open.txt"];
    [dest.path writeToURL:pending atomically:YES encoding:NSUTF8StringEncoding error:nil];
  }
}

@implementation IOSDocumentPickerShim
- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
  (void)controller;
  if (urls.firstObject) {
    copy_url_into_documents(urls.firstObject);
  }
}
@end

void blender_ios_present_document_picker(void)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindow *window = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
      if (![candidate isKindOfClass:[UIWindowScene class]]) {
        continue;
      }
      UIWindowScene *scene = (UIWindowScene *)candidate;
      if (scene.activationState != UISceneActivationStateForegroundActive) {
        continue;
      }
      window = scene.keyWindow;
      if (window == nil) {
        window = scene.windows.firstObject;
      }
      break;
    }
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) {
      root = root.presentedViewController;
    }
    if (root == nil) {
      return;
    }
    UTType *blend = [UTType typeWithFilenameExtension:@"blend"];
    if (blend == nil) {
      blend = UTTypeData;
    }
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ blend ]];
    picker.allowsMultipleSelection = NO;
    picker.delegate = picker_shim();
    [root presentViewController:picker animated:YES completion:nil];
  });
}
