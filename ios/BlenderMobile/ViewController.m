#import "ViewController.h"
#import "BlenderHost.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation ViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor colorWithRed:0.09 green:0.09 blue:0.09 alpha:1.0];

  UILabel *title = [[UILabel alloc] init];
  title.text = @"Blender";
  title.textColor = UIColor.whiteColor;
  title.font = [UIFont systemFontOfSize:36 weight:UIFontWeightSemibold];
  title.textAlignment = NSTextAlignmentCenter;
  title.translatesAutoresizingMaskIntoConstraints = NO;

  UILabel *body = [[UILabel alloc] init];
  body.text = @"Developer Mode install is working.\n\n"
              @"This stub is the separate iOS app. On the Mac, build "
              @"ios_arm64 libraries and libblender, then Product → Run again "
              @"to load the full editor.\n\n"
              @"Import a .blend into Files → On My iPhone → Blender.";
  body.textColor = [UIColor colorWithWhite:0.82 alpha:1];
  body.font = [UIFont systemFontOfSize:16];
  body.numberOfLines = 0;
  body.textAlignment = NSTextAlignmentCenter;
  body.translatesAutoresizingMaskIntoConstraints = NO;

  UIButton *importButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [importButton setTitle:@"Import .blend" forState:UIControlStateNormal];
  importButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
  importButton.backgroundColor = [UIColor colorWithRed:0.92 green:0.45 blue:0.07 alpha:1];
  [importButton setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
  importButton.layer.cornerRadius = 10;
  importButton.translatesAutoresizingMaskIntoConstraints = NO;
  [importButton addTarget:self action:@selector(importBlend) forControlEvents:UIControlEventTouchUpInside];

  [self.view addSubview:title];
  [self.view addSubview:body];
  [self.view addSubview:importButton];

  [NSLayoutConstraint activateConstraints:@[
    [title.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [title.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-80],
    [body.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
    [body.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
    [body.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:16],
    [importButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [importButton.topAnchor constraintEqualToAnchor:body.bottomAnchor constant:24],
    [importButton.widthAnchor constraintEqualToConstant:220],
    [importButton.heightAnchor constraintEqualToConstant:48],
  ]];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
  return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)prefersStatusBarHidden
{
  return YES;
}

- (void)importBlend
{
  UTType *blend = [UTType typeWithFilenameExtension:@"blend"] ?: UTTypeData;
  UIDocumentPickerViewController *picker =
      [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ blend ]];
  picker.delegate = self;
  picker.allowsMultipleSelection = NO;
  [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
  NSURL *url = urls.firstObject;
  if (url == nil) {
    return;
  }
  NSFileManager *fm = NSFileManager.defaultManager;
  NSURL *docs = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
  NSURL *blenderDir = [docs URLByAppendingPathComponent:@"Blender" isDirectory:YES];
  [fm createDirectoryAtURL:blenderDir withIntermediateDirectories:YES attributes:nil error:nil];
  BOOL access = [url startAccessingSecurityScopedResource];
  NSURL *dest = [blenderDir URLByAppendingPathComponent:url.lastPathComponent];
  [fm removeItemAtURL:dest error:nil];
  NSError *error = nil;
  [fm copyItemAtURL:url toURL:dest error:&error];
  if (access) {
    [url stopAccessingSecurityScopedResource];
  }
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:error ? @"Import failed" : @"Imported"
                       message:error ? error.localizedDescription : dest.lastPathComponent
                preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

@end
