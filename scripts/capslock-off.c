// capslock-off — turn off the macOS Caps Lock state from the command line.
//
// There is no built-in CLI for this, so we talk to IOHIDSystem directly via
// IOKit. Reports the state before/after so you can see what happened.
//
// Build:
//   clang capslock-off.c -o ~/.local/bin/capslock-off \
//       -framework IOKit -framework CoreFoundation
//
// The capslock-off zsh function rebuilds this automatically if the binary is
// missing (e.g. on a freshly migrated Mac).

#include <IOKit/IOKitLib.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <IOKit/hidsystem/IOHIDParameter.h>
#include <stdbool.h>
#include <stdio.h>

int main(void) {
    // kIOMainPortDefault is available on macOS 12+ (all current Macs).
    io_service_t service = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass));
    if (!service) {
        fprintf(stderr, "capslock-off: could not find IOHIDSystem service\n");
        return 1;
    }

    io_connect_t connect = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(),
                                     kIOHIDParamConnectType, &connect);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "capslock-off: IOServiceOpen failed (0x%x)\n", kr);
        return 1;
    }

    bool state = false;
    IOHIDGetModifierLockState(connect, kIOHIDCapsLockState, &state);
    printf("Caps Lock was: %s\n", state ? "ON" : "off");

    IOHIDSetModifierLockState(connect, kIOHIDCapsLockState, false);

    IOHIDGetModifierLockState(connect, kIOHIDCapsLockState, &state);
    printf("Caps Lock now: %s\n", state ? "ON" : "off");

    IOServiceClose(connect);
    return state ? 1 : 0;
}
