// Native titlebar controls loaded into Relay's bundled scrcpy viewer.
// No accessibility permission, screen capture, or cross-process window embedding.
#import <Cocoa/Cocoa.h>
#import <dlfcn.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <stdint.h>
#include <stdbool.h>

// SDL 3's published event ABI, used with the pinned official viewer runtime.
// https://wiki.libsdl.org/SDL3/SDL_KeyboardEvent
typedef union {
    struct {
        uint32_t type, reserved;
        uint64_t timestamp;
        uint32_t windowID, which;
        int32_t scancode;
        uint32_t key;
        uint16_t mod, raw;
        bool down, repeat;
    } keyboard;
    uint8_t bytes[128];
} RelaySDLEvent;
_Static_assert(sizeof(RelaySDLEvent) == 128, "SDL event ABI size");

static NSString * const RelayAction = @"local.relay.viewer.action";
static NSString * const RelayState = @"local.relay.viewer.state";

static NSString *RelayEnv(NSString *key) {
    const char *value = getenv(key.UTF8String);
    return value ? [NSString stringWithUTF8String:value] : nil;
}
static NSDictionary *RelayEnvironment(void) {
    NSMutableDictionary *values = [NSMutableDictionary new];
    for (NSString *key in @[@"RELAY_CONTROL_TOKEN", @"RELAY_SESSION_ID", @"RELAY_VIEWER_INSTANCE", @"RELAY_DEVICE_NAME", @"RELAY_WINDOW_TITLE", @"RELAY_VIEWER_OPTIONS", @"RELAY_RECORDING", @"RELAY_READ_ONLY"]) {
        NSString *value = RelayEnv(key); if (value) values[key] = value;
    }
    return values;
}

@interface RelayFlippedView : NSView @end
@implementation RelayFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface RelayToolbar : NSObject
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, strong) NSTitlebarAccessoryViewController *accessory;
@property(nonatomic, strong) NSTextField *status;
@property(nonatomic, strong) NSButton *recordButton;
@property(nonatomic, strong) NSButton *audioButton;
@property(nonatomic, strong) NSButton *cameraButton;
@property(nonatomic, strong) NSPanel *screenshotToast;
@property(nonatomic, strong) NSURL *screenshotURL;
@property(nonatomic, strong) NSWindow *screenshotPreview;
@property(nonatomic, strong) NSTimer *screenshotTimer;
@property(nonatomic) NSUInteger statusRevision;
@property(nonatomic, strong) NSPanel *settingsPanel;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSControl *> *fields;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *configuration;
@property(nonatomic, copy) NSString *token;
@property(nonatomic, copy) NSString *session;
@property(nonatomic) BOOL recording;
@property(nonatomic) BOOL busy;
@property(nonatomic, strong) id stateObserver;
@property(nonatomic, strong) id keyMonitor;
@property(nonatomic, strong) id resizeObserver;
@property(nonatomic, strong) id closeObserver;
- (instancetype)initWithWindow:(NSWindow *)window;
@end

@implementation RelayToolbar
- (NSButton *)button:(NSString *)symbol label:(NSString *)label action:(SEL)action x:(CGFloat)x {
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(x, 1, 27, 26)];
    button.bordered = NO;
    button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label];
    button.imagePosition = NSImageOnly;
    button.contentTintColor = NSColor.whiteColor;
    button.toolTip = label;
    button.accessibilityLabel = label;
    button.target = self; button.action = action;
    [self.accessory.view addSubview:button];
    return button;
}

- (instancetype)initWithWindow:(NSWindow *)window {
    if (!(self = [super init])) return nil;
    NSDictionary *env = RelayEnvironment();
    self.window = window; self.token = env[@"RELAY_CONTROL_TOKEN"]; self.session = env[@"RELAY_SESSION_ID"];
    NSData *data = [env[@"RELAY_VIEWER_OPTIONS"] dataUsingEncoding:NSUTF8StringEncoding];
    self.configuration = data ? [[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] mutableCopy] : [NSMutableDictionary new];
    if (!self.configuration) self.configuration = [NSMutableDictionary new];
    self.recording = [env[@"RELAY_RECORDING"] isEqualToString:@"1"];
    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    window.backgroundColor = [NSColor colorWithSRGBRed:0.26 green:0.28 blue:0.68 alpha:1];
    self.accessory = [NSTitlebarAccessoryViewController new];
    self.accessory.layoutAttribute = NSLayoutAttributeRight;
    self.accessory.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 294, 28)];
    self.accessory.view.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    self.cameraButton = [self button:@"camera.fill" label:@"Screenshot and copy · ⌘⇧S" action:@selector(screenshot:) x:0];
    self.recordButton = [self button:@"video.fill" label:@"Start recording · ⌘⇧R" action:@selector(record:) x:29];
    self.audioButton = [self button:@"headphones" label:@"Toggle phone audio" action:@selector(audio:) x:58];
    [self button:@"arrow.up.left.and.arrow.down.right" label:@"Toggle fullscreen · ⌘F" action:@selector(fullscreen:) x:87];
    [self button:@"gearshape.fill" label:@"Device menu" action:@selector(menu:) x:116];
    self.status = [NSTextField labelWithString:env[@"RELAY_DEVICE_NAME"] ?: @"Android"];
    self.status.frame = NSMakeRect(151, 6, 134, 18);
    self.status.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    self.status.textColor = NSColor.whiteColor;
    self.status.lineBreakMode = NSLineBreakByTruncatingTail;
    self.status.alignment = NSTextAlignmentRight;
    [self.accessory.view addSubview:self.status];
    [window addTitlebarAccessoryViewController:self.accessory];
    [self layoutTitlebar];
    [self updateButtons];
    __weak RelayToolbar *weakSelf = self;
    self.resizeObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidResizeNotification object:window queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [weakSelf layoutTitlebar];
        [weakSelf positionScreenshotToast];
    }];
    self.closeObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:window queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [weakSelf dismissScreenshotToast];
        [weakSelf.screenshotPreview close]; weakSelf.screenshotPreview = nil;
    }];
    self.stateObserver = [NSDistributedNotificationCenter.defaultCenter addObserverForName:RelayState object:self.token queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        RelayToolbar *owner = weakSelf;
        if (!owner || ![note.userInfo[@"session"] isEqual:owner.session]) return;
        if (note.userInfo[@"busy"]) owner.busy = [note.userInfo[@"busy"] boolValue];
        NSString *message = note.userInfo[@"status"];
        if (message) {
            owner.status.stringValue = message;
            NSUInteger revision = ++owner.statusRevision;
            BOOL screenshot = [message isEqual:@"Screenshot copied"];
            if (screenshot) [owner showScreenshotToast:note.userInfo[@"screenshotPath"]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (screenshot ? 3 : 4) * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                if (owner.statusRevision == revision) owner.status.stringValue = RelayEnv(@"RELAY_DEVICE_NAME") ?: @"Android";
            });
        }
        [owner updateButtons];
    }];
    self.keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        RelayToolbar *owner = weakSelf;
        if (!owner || event.window != owner.window || owner.settingsPanel) return event;
        NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
        NSString *key = event.charactersIgnoringModifiers.lowercaseString;
        if ((flags & NSEventModifierFlagCommand) && (flags & NSEventModifierFlagShift)) {
            if ([key isEqual:@"s"]) { [owner screenshot:nil]; return nil; }
            if ([key isEqual:@"r"]) { [owner record:nil]; return nil; }
        }
        if ((flags & NSEventModifierFlagCommand) && [key isEqual:@","]) { [owner showSettings:nil]; return nil; }
        return event;
    }];
    return self;
}

- (void)dealloc {
    if (_stateObserver) [NSDistributedNotificationCenter.defaultCenter removeObserver:_stateObserver];
    if (_keyMonitor) [NSEvent removeMonitor:_keyMonitor];
    if (_resizeObserver) [NSNotificationCenter.defaultCenter removeObserver:_resizeObserver];
    if (_closeObserver) [NSNotificationCenter.defaultCenter removeObserver:_closeObserver];
    [_screenshotTimer invalidate];
    [_screenshotToast orderOut:nil];
}

- (void)showScreenshotToast:(NSString *)path {
    if (![path isKindOfClass:NSString.class] || !path.isAbsolutePath || ![path.pathExtension.lowercaseString isEqual:@"png"]) return;
    NSURL *url = [NSURL fileURLWithPath:path];
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
    if (!image || !self.window.visible) return;
    [self dismissScreenshotToast];
    self.screenshotURL = url;
    CGFloat width = MIN(324, MAX(240, self.window.contentView.bounds.size.width - 24));
    NSPanel *toast = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, width, 118)
        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
        backing:NSBackingStoreBuffered defer:NO];
    toast.title = @"Screenshot copied";
    toast.opaque = NO; toast.backgroundColor = NSColor.clearColor; toast.hasShadow = YES;
    toast.becomesKeyOnlyIfNeeded = YES; toast.hidesOnDeactivate = NO;
    toast.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorTransient | NSWindowCollectionBehaviorIgnoresCycle;
    NSVisualEffectView *card = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, width, 118)];
    card.material = NSVisualEffectMaterialHUDWindow; card.state = NSVisualEffectStateActive;
    card.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    card.wantsLayer = YES; card.layer.cornerRadius = 13; card.layer.masksToBounds = YES;
    toast.contentView = card;
    NSImageView *thumbnail = [[NSImageView alloc] initWithFrame:NSMakeRect(13, 13, 57, 92)];
    thumbnail.image = image; thumbnail.imageScaling = NSImageScaleProportionallyUpOrDown;
    thumbnail.wantsLayer = YES; thumbnail.layer.cornerRadius = 5; thumbnail.layer.masksToBounds = YES;
    [card addSubview:thumbnail];
    NSImageView *check = [[NSImageView alloc] initWithFrame:NSMakeRect(83, 79, 15, 15)];
    check.image = [NSImage imageWithSystemSymbolName:@"checkmark.circle.fill" accessibilityDescription:@"Copied"];
    check.contentTintColor = NSColor.systemGreenColor; [card addSubview:check];
    NSTextField *heading = [NSTextField labelWithString:@"Screenshot copied"];
    heading.frame = NSMakeRect(103, 77, width - 111, 20);
    heading.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    heading.autoresizingMask = NSViewWidthSizable;
    heading.lineBreakMode = NSLineBreakByTruncatingTail; [card addSubview:heading];
    NSTextField *detail = [NSTextField labelWithString:@"Ready to paste. PNG saved."];
    detail.frame = NSMakeRect(83, 56, width - 91, 17);
    detail.font = [NSFont systemFontOfSize:10]; detail.textColor = NSColor.secondaryLabelColor;
    detail.autoresizingMask = NSViewWidthSizable;
    detail.lineBreakMode = NSLineBreakByTruncatingTail; [card addSubview:detail];
    NSButton *preview = [NSButton buttonWithTitle:@"Preview" target:self action:@selector(previewScreenshot:)];
    preview.frame = NSMakeRect(80, 16, 72, 28); preview.accessibilityLabel = @"Preview screenshot";
    [card addSubview:preview];
    NSButton *save = [NSButton buttonWithTitle:@"Save As…" target:self action:@selector(saveScreenshot:)];
    save.frame = NSMakeRect(154, 16, 76, 28); save.accessibilityLabel = @"Save screenshot as";
    [card addSubview:save];
    self.screenshotToast = toast;
    [self positionScreenshotToast];
    [self.window addChildWindow:toast ordered:NSWindowAbove];
    toast.alphaValue = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 1 : 0;
    [toast orderFront:nil];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : 0.16;
        toast.animator.alphaValue = 1;
    } completionHandler:nil];
    self.cameraButton.contentTintColor = NSColor.systemGreenColor;
    __weak RelayToolbar *weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:3 repeats:NO block:^(NSTimer *timer) {
        [weakSelf dismissScreenshotToast];
    }];
    self.screenshotTimer = timer;
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    NSAccessibilityPostNotificationWithUserInfo(card, NSAccessibilityAnnouncementRequestedNotification,
        @{NSAccessibilityAnnouncementKey: @"Screenshot copied", NSAccessibilityPriorityKey: @(NSAccessibilityPriorityMedium)});
}

- (void)positionScreenshotToast {
    if (!self.screenshotToast) return;
    NSRect content = [self.window convertRectToScreen:self.window.contentLayoutRect];
    NSRect frame = self.screenshotToast.frame;
    frame.size.width = MIN(324, MAX(240, content.size.width - 24));
    frame.origin = NSMakePoint(MAX(NSMinX(content) + 8, NSMaxX(content) - frame.size.width - 12), NSMinY(content) + 14);
    [self.screenshotToast setFrame:frame display:NO];
}

- (void)dismissScreenshotToast {
    [self.screenshotTimer invalidate]; self.screenshotTimer = nil;
    if (self.screenshotToast) {
        [self.window removeChildWindow:self.screenshotToast];
        [self.screenshotToast orderOut:nil]; self.screenshotToast = nil;
    }
    self.screenshotURL = nil;
    self.cameraButton.contentTintColor = NSColor.whiteColor;
}

- (void)previewScreenshot:(id)sender {
    NSURL *url = self.screenshotURL;
    [self dismissScreenshotToast];
    NSImage *image = url ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
    if (!image) return;
    [self.screenshotPreview close];
    NSWindow *preview = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 440, 640)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    preview.title = @"Screenshot Preview"; preview.releasedWhenClosed = NO;
    preview.minSize = NSMakeSize(280, 300);
    preview.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    NSImageView *canvas = [[NSImageView alloc] initWithFrame:NSMakeRect(16, 60, 408, 564)];
    canvas.image = image; canvas.imageScaling = NSImageScaleProportionallyUpOrDown;
    canvas.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    canvas.accessibilityLabel = @"Captured screenshot";
    [preview.contentView addSubview:canvas];
    NSButton *save = [NSButton buttonWithTitle:@"Save As…" target:self action:@selector(saveScreenshot:)];
    save.frame = NSMakeRect(332, 15, 92, 30); save.autoresizingMask = NSViewMinXMargin;
    save.cell.representedObject = url; save.accessibilityLabel = @"Save screenshot as";
    [preview.contentView addSubview:save];
    self.screenshotPreview = preview;
    [preview center]; [preview makeKeyAndOrderFront:nil];
}

- (void)saveScreenshot:(id)sender {
    NSURL *source = self.screenshotURL;
    NSWindow *parent = self.window;
    if ([sender isKindOfClass:NSButton.class]) {
        id represented = ((NSButton *)sender).cell.representedObject;
        if ([represented isKindOfClass:NSURL.class]) source = represented;
        if (((NSButton *)sender).window == self.screenshotPreview) parent = self.screenshotPreview;
    }
    [self dismissScreenshotToast];
    if (!source) return;
    NSSavePanel *save = [NSSavePanel savePanel];
    save.allowedContentTypes = @[UTTypePNG];
    save.nameFieldStringValue = source.lastPathComponent;
    save.message = @"Save another copy of your screenshot. The original stays in Relay’s captures.";
    [save beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || !save.URL) return;
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfURL:source options:0 error:&error];
        if (data && [data writeToURL:save.URL options:NSDataWritingAtomic error:&error]) return;
        NSAlert *alert = [NSAlert new]; alert.messageText = @"Couldn’t save the screenshot";
        alert.informativeText = error.localizedDescription ?: @"The original screenshot is still saved in Relay’s captures.";
        [alert beginSheetModalForWindow:parent completionHandler:nil];
    }];
}
- (void)layoutTitlebar {
    CGFloat width = MIN(294, MAX(145, self.window.frame.size.width - 88));
    self.accessory.view.frame = NSMakeRect(0, 0, width, 28);
    self.status.hidden = width < 190;
    self.status.frame = NSMakeRect(151, 6, MAX(30, width - 160), 18);
}
- (void)updateButtons {
    self.recordButton.image = [NSImage imageWithSystemSymbolName:self.recording ? @"stop.circle.fill" : @"video.fill" accessibilityDescription:self.recording ? @"Stop recording" : @"Start recording"];
    self.recordButton.contentTintColor = self.recording ? NSColor.systemRedColor : NSColor.whiteColor;
    self.recordButton.toolTip = self.recording ? @"Stop recording and copy saved file · ⌘⇧R" : @"Start recording · ⌘⇧R";
    BOOL audio = [self.configuration[@"audio"] isEqual:@"1"];
    BOOL fallback = [RelayEnv(@"RELAY_AUDIO_PLAYBACK_FALLBACK") isEqual:@"1"];
    NSString *audioLabel = fallback ? @"Mac audio unavailable. Retry playback" : (audio ? @"Mute phone audio" : @"Enable phone audio");
    self.audioButton.image = [NSImage imageWithSystemSymbolName:audio && !fallback ? @"headphones" : @"speaker.slash.fill" accessibilityDescription:audioLabel];
    self.audioButton.toolTip = audioLabel;
    self.audioButton.accessibilityLabel = audioLabel;
    self.recordButton.enabled = !self.busy; self.audioButton.enabled = !self.busy;
}
- (void)send:(NSString *)action values:(NSDictionary *)values {
    if (self.busy && ![action isEqual:@"screenshot"]) return;
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:values ?: @{}];
    info[@"session"] = self.session; info[@"action"] = action;
    NSString *instance = RelayEnv(@"RELAY_VIEWER_INSTANCE");
    if (instance) info[@"instance"] = instance;
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:RelayAction object:self.token userInfo:info deliverImmediately:YES];
}
- (void)screenshot:(id)sender { [self send:@"screenshot" values:nil]; }
- (void)record:(id)sender { [self send:@"record" values:nil]; }
- (void)audio:(id)sender { [self send:@"audio" values:nil]; }

// Queue the viewer's documented shortcuts directly in SDL, avoiding global
// keyboard synthesis, accessibility permissions, and stuck modifier keys.
- (void)shortcut:(NSString *)key code:(unsigned short)code shift:(BOOL)shift {
    [self.window makeKeyAndOrderFront:nil];
    bool (*push)(void *) = dlsym(RTLD_DEFAULT, "SDL_PushEvent");
    void *(*focus)(void) = dlsym(RTLD_DEFAULT, "SDL_GetKeyboardFocus_REAL");
    uint32_t (*windowID)(void *) = dlsym(RTLD_DEFAULT, "SDL_GetWindowID_REAL");
    if (push && focus && windowID) {
        RelaySDLEvent event = {0};
        event.keyboard.windowID = windowID(focus());
        event.keyboard.key = [key characterAtIndex:0];
        event.keyboard.scancode = (int32_t)event.keyboard.key - 'a' + 4;
        event.keyboard.raw = code;
        event.keyboard.mod = 0x0400 | (shift ? 0x0001 : 0);
        event.keyboard.type = 0x300; event.keyboard.down = true; push(&event);
        event.keyboard.type = 0x301; event.keyboard.down = false; push(&event);
        return;
    }
    // Cocoa-only verification fixture, not the production SDL viewer.
    NSEventModifierFlags flags = NSEventModifierFlagCommand | (shift ? NSEventModifierFlagShift : 0);
    NSInteger number = self.window.windowNumber;
    NSTimeInterval time = NSProcessInfo.processInfo.systemUptime;
    for (NSNumber *type in @[@(NSEventTypeKeyDown), @(NSEventTypeKeyUp)]) {
        NSEventType t = type.unsignedIntegerValue;
        NSEvent *event = [NSEvent keyEventWithType:t location:NSZeroPoint modifierFlags:flags timestamp:time windowNumber:number context:nil characters:key charactersIgnoringModifiers:key isARepeat:NO keyCode:code];
        [NSApp postEvent:event atStart:NO];
    }
}
- (void)fullscreen:(id)sender { [self shortcut:@"f" code:3 shift:NO]; }
- (void)menu:(NSButton *)sender {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Device"];
    NSArray *entries = @[@[@"Wireless Mode", @"wifi", @"wireless"], @[@"Rotate Screen", @"rotate.right", @"rotate"], @[@"Screen On/Off", @"power", @"power"], @[@"Copy Logcat", @"doc.on.clipboard", @"logcat"], @[@"Settings…", @"gearshape", @"settings"]];
    for (NSArray *entry in entries) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:entry[0] action:@selector(menuAction:) keyEquivalent:@""];
        item.target = self; item.representedObject = entry[2];
        item.image = [NSImage imageWithSystemSymbolName:entry[1] accessibilityDescription:entry[0]];
        if ([entry[2] isEqual:@"power"]) {
            NSMenu *power = [[NSMenu alloc] initWithTitle:@"Screen power"];
            for (NSArray *powerEntry in @[@[@"Turn screen off", @"screenOff"], @[@"Turn screen on", @"screenOn"]]) {
                NSMenuItem *child = [[NSMenuItem alloc] initWithTitle:powerEntry[0] action:@selector(menuAction:) keyEquivalent:@""];
                child.target = self; child.representedObject = powerEntry[1]; [power addItem:child];
            }
            item.submenu = power;
        }
        [menu addItem:item];
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, -4) inView:sender];
}
- (void)menuAction:(NSMenuItem *)item {
    NSString *action = item.representedObject;
    if ([action isEqual:@"rotate"]) [self shortcut:@"r" code:15 shift:NO];
    else if ([action isEqual:@"screenOff"]) [self shortcut:@"o" code:31 shift:NO];
    else if ([action isEqual:@"screenOn"]) [self shortcut:@"o" code:31 shift:YES];
    else if ([action isEqual:@"settings"]) [self showSettings:nil];
    else [self send:action values:nil];
}
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (self.busy) return NO;
    BOOL viewOnly = [RelayEnv(@"RELAY_READ_ONLY") isEqual:@"1"];
    return !(viewOnly && [@[@"rotate", @"screenOff", @"screenOn", @"power"] containsObject:item.representedObject]);
}

- (NSTextField *)label:(NSString *)text y:(CGFloat)y size:(CGFloat)size bold:(BOOL)bold in:(NSView *)view {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.frame = NSMakeRect(12, y, 336, size > 13 ? 28 : 34);
    label.font = [NSFont systemFontOfSize:size weight:bold ? NSFontWeightSemibold : NSFontWeightRegular];
    [view addSubview:label]; return label;
}
- (void)popup:(NSString *)key title:(NSString *)title choices:(NSArray *)choices values:(NSArray *)values y:(CGFloat *)y in:(NSView *)view {
    [self label:title y:*y size:11 bold:NO in:view]; *y += 21;
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, *y, 340, 28) pullsDown:NO];
    [popup addItemsWithTitles:choices];
    for (NSUInteger index = 0; index < values.count; index++) popup.itemArray[index].representedObject = values[index];
    NSString *current = self.configuration[key];
    for (NSMenuItem *item in popup.itemArray) if ([item.representedObject isEqual:current]) [popup selectItem:item];
    self.fields[key] = popup; [view addSubview:popup]; *y += 42;
}
- (void)toggle:(NSString *)key title:(NSString *)title y:(CGFloat *)y in:(NSView *)view {
    NSButton *button = [NSButton checkboxWithTitle:title target:nil action:nil];
    button.frame = NSMakeRect(12, *y, 338, 26);
    button.state = [self.configuration[key] isEqual:@"1"] ? NSControlStateValueOn : NSControlStateValueOff;
    if ([RelayEnv(@"RELAY_READ_ONLY") isEqual:@"1"] && [@[@"screenOff", @"stayAwake", @"international"] containsObject:key]) button.enabled = NO;
    self.fields[key] = button; [view addSubview:button]; *y += 34;
}
- (void)showSettings:(id)sender {
    if (self.settingsPanel) return;
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 410, 610) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    panel.title = @"Mirror settings"; panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    self.settingsPanel = panel; self.fields = [NSMutableDictionary new];
    NSTextField *heading = [NSTextField labelWithString:@"Mirror settings"];
    heading.frame = NSMakeRect(24, 565, 360, 26); heading.font = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
    [panel.contentView addSubview:heading];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 92, 370, 460)];
    scroll.hasVerticalScroller = YES; scroll.drawsBackground = NO;
    RelayFlippedView *document = [[RelayFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 358, 790)];
    scroll.documentView = document; [panel.contentView addSubview:scroll];
    CGFloat y = 10;
    [self label:@"Image Quality" y:y size:16 bold:YES in:document]; y += 42;
    [self popup:@"bitrate" title:@"Bitrate" choices:@[@"2 Mbps", @"4 Mbps", @"8 Mbps", @"16 Mbps", @"24 Mbps", @"32 Mbps", @"64 Mbps"] values:@[@"2", @"4", @"8", @"16", @"24", @"32", @"64"] y:&y in:document];
    [self popup:@"resolution" title:@"Resolution · longest edge" choices:@[@"720 px", @"1280 px", @"1920 px", @"2560 px", @"Native resolution"] values:@[@"720", @"1280", @"1920", @"2560", @"0"] y:&y in:document];
    [self popup:@"fps" title:@"Frame rate limit" choices:@[@"30 fps", @"60 fps", @"90 fps", @"120 fps"] values:@[@"30", @"60", @"90", @"120"] y:&y in:document];
    [self popup:@"decoder" title:@"Decoder" choices:@[@"Automatic", @"Apple VideoToolbox", @"Software"] values:@[@"auto", @"videotoolbox", @"disabled"] y:&y in:document];
    [self toggle:@"baseline" title:@"Force H.264 Baseline profile" y:&y in:document];
    [self toggle:@"international" title:@"International keyboard (UHID)" y:&y in:document];
    [self label:@"UHID may require choosing a physical keyboard layout on your Android phone." y:y size:10 bold:NO in:document]; y += 45;
    [self label:@"Presets" y:y size:14 bold:YES in:document]; y += 34;
    NSArray *presets = @[@"Low", @"Medium", @"High", @"Max"];
    for (NSUInteger i = 0; i < presets.count; i++) {
        NSButton *button = [NSButton buttonWithTitle:presets[i] target:self action:@selector(preset:)];
        button.tag = i; button.frame = NSMakeRect(10 + i * 85, y, 80, 30); [document addSubview:button];
    }
    y += 58;
    [self label:@"Device Settings" y:y size:16 bold:YES in:document]; y += 40;
    [self toggle:@"audio" title:@"Mirror phone audio (Android 11+)" y:&y in:document];
    [self toggle:@"screenOff" title:@"Turn phone screen off while mirroring" y:&y in:document];
    [self toggle:@"stayAwake" title:@"Keep phone awake while connected" y:&y in:document];
    [self toggle:@"alwaysOnTop" title:@"Keep mirror window always on top" y:&y in:document];
    document.frame = NSMakeRect(0, 0, 358, y + 20);
    NSTextField *note = [NSTextField wrappingLabelWithString:@"Saving restarts the mirror. A recording in progress is saved, then continues as a new clip."];
    note.frame = NSMakeRect(24, 49, 360, 34); note.font = [NSFont systemFontOfSize:10]; note.textColor = NSColor.secondaryLabelColor;
    [panel.contentView addSubview:note];
    NSArray *titles = @[@"Cancel", @"Defaults", @"Save"];
    SEL actions[] = {@selector(cancelSettings:), @selector(defaultSettings:), @selector(saveSettings:)};
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSButton *button = [NSButton buttonWithTitle:titles[i] target:self action:actions[i]];
        button.frame = NSMakeRect(142 + i * 82, 12, 76, 30); [panel.contentView addSubview:button];
        if (i == 2) button.keyEquivalent = @"\r";
        if (i == 0) button.keyEquivalent = @"\e";
    }
    [self.window beginSheet:panel completionHandler:nil];
}
- (void)select:(NSString *)key value:(NSString *)value {
    NSPopUpButton *popup = (NSPopUpButton *)self.fields[key];
    for (NSMenuItem *item in popup.itemArray) if ([item.representedObject isEqual:value]) [popup selectItem:item];
}
- (void)preset:(NSButton *)sender {
    NSArray *rates = @[@"2", @"8", @"16", @"24"];
    NSArray *sizes = @[@"720", @"1280", @"1920", @"0"];
    [self select:@"bitrate" value:rates[sender.tag]]; [self select:@"resolution" value:sizes[sender.tag]];
    [self select:@"fps" value:sender.tag == 0 ? @"30" : @"60"];
}
- (void)defaultSettings:(id)sender {
    [self select:@"bitrate" value:@"16"]; [self select:@"resolution" value:@"1920"];
    [self select:@"fps" value:@"60"]; [self select:@"decoder" value:@"auto"];
    for (NSString *key in @[@"baseline", @"international", @"screenOff", @"alwaysOnTop"]) ((NSButton *)self.fields[key]).state = NSControlStateValueOff;
    for (NSString *key in @[@"audio", @"stayAwake"]) ((NSButton *)self.fields[key]).state = NSControlStateValueOn;
}
- (void)cancelSettings:(id)sender { [self.window endSheet:self.settingsPanel]; self.settingsPanel = nil; }
- (void)saveSettings:(id)sender {
    NSMutableDictionary *values = [NSMutableDictionary new];
    for (NSString *key in self.fields) {
        NSControl *field = self.fields[key];
        if ([field isKindOfClass:NSPopUpButton.class]) values[key] = ((NSPopUpButton *)field).selectedItem.representedObject;
        else values[key] = ((NSButton *)field).state == NSControlStateValueOn ? @"1" : @"0";
    }
    [self cancelSettings:nil]; [self send:@"settings" values:values];
}
@end

static NSMapTable<NSWindow *, RelayToolbar *> *controllers;
static void AttachToolbar(NSWindow *window) {
    if (!window || [controllers objectForKey:window]) return;
    NSString *title = RelayEnv(@"RELAY_WINDOW_TITLE");
    if (![window.title isEqual:title]) return;
    RelayToolbar *controller = [[RelayToolbar alloc] initWithWindow:window];
    [controllers setObject:controller forKey:window];
    [controller send:@"ready" values:nil];
}

static void FindViewerWindow(void) {
    for (NSWindow *window in NSApp.windows) AttachToolbar(window);
    // SDL may set the window title after its initial key-window notification.
    if (controllers.count == 0 && NSApp) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{ FindViewerWindow(); });
    }
}

__attribute__((constructor)) static void RelayToolbarLoad(void) {
    @autoreleasepool {
        if (!RelayEnv(@"RELAY_CONTROL_TOKEN")) return;
        // Keep viewer status logs timely when stdout is a manager-owned pipe.
        setvbuf(stdout, NULL, _IOLBF, 0);
        // The companion is for this viewer, not its long-lived ADB helpers.
        unsetenv("DYLD_INSERT_LIBRARIES");
        controllers = [NSMapTable weakToStrongObjectsMapTable];
        [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { AttachToolbar(note.object); }];
        [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            for (NSWindow *window in NSApp.windows) AttachToolbar(window);
        }];
        dispatch_async(dispatch_get_main_queue(), ^{ FindViewerWindow(); });
    }
}
