// Hardware-free UI verification harness. Never packaged with the release app.
#import <Cocoa/Cocoa.h>
#import <dlfcn.h>

@interface NSObject (RelayPreviewVerification)
- (void)previewScreenshot:(id)sender;
@end

@interface PreviewDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTextField *result;
@property(nonatomic, strong) NSURL *fixtureImage;
@property(nonatomic) BOOL previewNextCapture;
@end
@implementation PreviewDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 430, 740) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Toolbar verification — Relay";
    self.window.contentView.wantsLayer = YES;
    self.window.contentView.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    NSTextField *label = [NSTextField wrappingLabelWithString:@"Toolbar verification\nNo Android device connected\n\nControls below report received actions."];
    label.frame = NSMakeRect(35, 400, 360, 170); label.alignment = NSTextAlignmentCenter;
    label.font = [NSFont systemFontOfSize:16 weight:NSFontWeightMedium];
    [self.window.contentView addSubview:label];
    self.result = [NSTextField wrappingLabelWithString:@"Waiting for toolbar action"];
    self.result.frame = NSMakeRect(30, 100, 370, 280); self.result.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    [self.window.contentView addSubview:self.result];
    NSButton *previewCheck = [NSButton buttonWithTitle:@"Check screenshot preview" target:self action:@selector(checkScreenshotPreview:)];
    previewCheck.frame = NSMakeRect(100, 30, 230, 30); [self.window.contentView addSubview:previewCheck];
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:240 pixelsHigh:420 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [[NSColor colorWithSRGBRed:0.25 green:0.26 blue:0.62 alpha:1] setFill]; NSRectFill(NSMakeRect(0, 0, 240, 420));
    [@"Relay\n\nPreview test image\nNo phone connected" drawInRect:NSMakeRect(22, 150, 196, 190) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:19 weight:NSFontWeightMedium], NSForegroundColorAttributeName:NSColor.whiteColor}];
    [NSGraphicsContext restoreGraphicsState];
    self.fixtureImage = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"RelayScreenshotPreview-%@.png", NSUUID.UUID.UUIDString]]];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToURL:self.fixtureImage atomically:YES];
    __weak PreviewDelegate *weakSelf = self;
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:@"local.relay.viewer.action" object:@"relay-toolbar-verification" queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        weakSelf.result.stringValue = [NSString stringWithFormat:@"Received: %@\n%@", note.userInfo[@"action"], note.userInfo];
        if ([note.userInfo[@"action"] isEqual:@"screenshot"]) {
            // Simulate only success feedback; do not overwrite the user's clipboard.
            [[NSSound soundNamed:@"Pop"] play];
            [NSDistributedNotificationCenter.defaultCenter postNotificationName:@"local.relay.viewer.state" object:@"relay-toolbar-verification" userInfo:@{@"session": @"verification", @"status": @"Screenshot copied", @"screenshotPath": weakSelf.fixtureImage.path} deliverImmediately:YES];
            if (weakSelf.previewNextCapture) {
                weakSelf.previewNextCapture = NO;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 3), dispatch_get_main_queue(), ^{
                    [[weakSelf cameraButton].target previewScreenshot:nil];
                });
            }
        }
    }];
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (event.modifierFlags & NSEventModifierFlagCommand) {
            NSString *key = event.charactersIgnoringModifiers.lowercaseString;
            if ([@[@"f", @"r", @"o"] containsObject:key]) {
                weakSelf.result.stringValue = [NSString stringWithFormat:@"Received viewer shortcut: Command %@%@", (event.modifierFlags & NSEventModifierFlagShift) ? @"Shift " : @"", key];
                if ([key isEqual:@"f"]) [weakSelf.window toggleFullScreen:nil];
                return nil;
            }
        }
        return event;
    }];
    [self.window center]; [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
- (NSButton *)cameraButton {
    for (NSTitlebarAccessoryViewController *accessory in self.window.titlebarAccessoryViewControllers) {
        for (NSView *view in accessory.view.subviews) {
            if ([view isKindOfClass:NSButton.class] && [((NSButton *)view).accessibilityLabel hasPrefix:@"Screenshot and copy"]) return (NSButton *)view;
        }
    }
    return nil;
}
- (void)checkScreenshotPreview:(id)sender { self.previewNextCapture = YES; [[self cameraButton] performClick:nil]; }
- (void)applicationWillTerminate:(NSNotification *)notification { [NSFileManager.defaultManager removeItemAtURL:self.fixtureImage error:nil]; }
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        setenv("RELAY_CONTROL_TOKEN", "relay-toolbar-verification", 1);
        setenv("RELAY_SESSION_ID", "verification", 1);
        setenv("RELAY_DEVICE_NAME", "UI verification", 1);
        setenv("RELAY_WINDOW_TITLE", "Toolbar verification — Relay", 1);
        setenv("RELAY_VIEWER_OPTIONS", "{\"bitrate\":\"16\",\"resolution\":\"1920\",\"fps\":\"60\",\"decoder\":\"auto\",\"audio\":\"1\",\"stayAwake\":\"1\"}", 1);
        [NSApplication sharedApplication];
        NSMenu *bar = [NSMenu new];
        NSMenuItem *appItem = [NSMenuItem new];
        NSMenu *appMenu = [NSMenu new];
        [appMenu addItemWithTitle:@"Quit Preview" action:@selector(terminate:) keyEquivalent:@"q"];
        appItem.submenu = appMenu; [bar addItem:appItem]; NSApp.mainMenu = bar;
        NSString *resources = NSBundle.mainBundle.resourcePath;
        void *library = dlopen([[resources stringByAppendingPathComponent:@"libRelayToolbar.dylib"] fileSystemRepresentation], RTLD_NOW);
        if (!library) { fprintf(stderr, "%s\n", dlerror()); return 1; }
        NSApp.activationPolicy = NSApplicationActivationPolicyRegular;
        PreviewDelegate *delegate = [PreviewDelegate new]; NSApp.delegate = delegate;
        [NSApp run];
    }
    return 0;
}
