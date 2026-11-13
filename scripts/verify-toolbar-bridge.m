// Verify the exact SDL keyboard-event ABI without a phone or a GUI session.
#import <Cocoa/Cocoa.h>
#import <dlfcn.h>
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint32_t type, reserved;
    uint64_t timestamp;
    uint32_t windowID, which;
    int32_t scancode;
    uint32_t key;
    uint16_t mod, raw;
    bool down, repeat;
} Keyboard;
static Keyboard received[2];
static int count;
__attribute__((visibility("default"))) bool SDL_PushEvent(void *event) {
    assert(count < 2); received[count++] = *(Keyboard *)event; return true;
}
__attribute__((visibility("default"))) void *SDL_GetKeyboardFocus_REAL(void) { return (void *)1; }
__attribute__((visibility("default"))) uint32_t SDL_GetWindowID_REAL(void *window) { assert(window == (void *)1); return 77; }
@interface NSObject (RelayShortcutTest)
- (void)shortcut:(NSString *)key code:(unsigned short)code shift:(BOOL)shift;
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        assert(argc == 2);
        assert(dlopen(argv[1], RTLD_NOW));
        id toolbar = [NSClassFromString(@"RelayToolbar") new];
        for (NSString *key in @[@"r", @"o", @"f"]) {
            count = 0;
            BOOL shift = [key isEqual:@"o"];
            [toolbar shortcut:key code:0 shift:shift];
            assert(count == 2);
            assert(received[0].type == 0x300 && received[0].down);
            assert(received[1].type == 0x301 && !received[1].down);
            assert(received[0].windowID == 77);
            assert(received[0].key == [key characterAtIndex:0]);
            assert(received[0].scancode == [key characterAtIndex:0] - 'a' + 4);
            assert(received[0].mod == (0x0400 | (shift ? 1 : 0)));
        }
        puts("Verified SDL rotation, display power, and fullscreen event ABI.");
    }
    return 0;
}
