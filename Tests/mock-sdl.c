#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

typedef union {
    uint32_t type;
    struct { uint32_t type, reserved; uint64_t timestamp; uint32_t which; uint8_t button, down, pad1, pad2; } button;
    uint64_t storage[16];
} Event;
typedef bool (*Callback)(void *, Event *);
static Callback watcher;
static void *watchContext;
uint16_t SDL_GetJoystickVendorForID(uint32_t id) { return id == 2 ? 0x054c : 0x057e; }
uint16_t SDL_GetJoystickProductForID(uint32_t id) { return id == 1 ? 0x2009 : id == 2 ? 0x0ce6 : 0x2008; }
const char *SDL_GetGamepadNameForID(uint32_t id) { return id == 1 ? "Nintendo Switch Pro Controller" : "Other Controller"; }
int SDL_GetGamepadTypeForID(uint32_t id) { return id == 1 ? 7 : 6; }
bool SDL_AddEventWatch(Callback callback, void *context) { watcher = callback; watchContext = context; return true; }
void SDL_RemoveEventWatch(Callback callback, void *context) {
    if (watcher == callback && watchContext == context) { watcher = NULL; watchContext = NULL; }
}
void Mock_Emit(uint32_t type, uint32_t id, uint8_t button, bool down) {
    Event event = {0};
    event.type = type;
    event.button.which = id;
    event.button.button = button;
    event.button.down = down;
    event.button.timestamp = 12345;
    if (watcher) watcher(watchContext, &event);
}
