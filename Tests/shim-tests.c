#include <assert.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef union {
    uint32_t type;
    struct { uint32_t type, reserved; uint64_t timestamp; uint32_t which; uint8_t button, down, pad1, pad2; } button;
    uint64_t storage[16];
} Event;
typedef bool (*Callback)(void *, Event *);
typedef struct { uint32_t type, id; uint8_t button; bool down; unsigned calls; } Expected;
static bool receive(void *context, Event *event) {
    Expected *expected = context;
    assert(event->type == expected->type);
    assert(event->button.which == expected->id);
    assert(event->button.button == expected->button);
    assert(event->button.down == expected->down);
    assert(event->button.timestamp == 12345);
    ++expected->calls;
    return true;
}
int main(int argc, char **argv) {
    assert(argc == 2);
    void *library = dlopen(argv[1], RTLD_NOW);
    assert(library);
    uint16_t (*vendor)(uint32_t) = dlsym(library, "SDL_GetJoystickVendorForID");
    uint16_t (*product)(uint32_t) = dlsym(library, "SDL_GetJoystickProductForID");
    int (*type)(uint32_t) = dlsym(library, "SDL_GetGamepadTypeForID");
    const char *(*name)(uint32_t) = dlsym(library, "SDL_GetGamepadNameForID");
    bool (*add)(Callback, void *) = dlsym(library, "SDL_AddEventWatch");
    void (*remove)(Callback, void *) = dlsym(library, "SDL_RemoveEventWatch");
    void (*emit)(uint32_t, uint32_t, uint8_t, bool) = dlsym(library, "Mock_Emit");
    assert(vendor && product && type && name && add && remove && emit);
    assert(vendor(1) == 0x045e && product(1) == 0x02e0 && type(1) == 3);
    assert(!strcmp(name(1), "Xbox One Controller"));
    assert(vendor(2) == 0x054c && product(2) == 0x0ce6 && type(2) == 6);
    assert(vendor(3) == 0x057e && product(3) == 0x2008);
    Expected expected = {0};
    assert(add(receive, &expected));
    bool swap = !getenv("X5_SWAP_FACE_BUTTONS") || strcmp(getenv("X5_SWAP_FACE_BUTTONS"), "0");
    uint32_t types[] = {0x603, 0x604, 0x651, 0x652, 0x600};
    for (uint32_t id = 1; id <= 3; ++id) {
        for (unsigned t = 0; t < sizeof(types)/sizeof(types[0]); ++t) {
            for (uint8_t button = 0; button < 8; ++button) {
                for (unsigned down = 0; down < 2; ++down) {
                    expected.type = types[t]; expected.id = id; expected.down = down;
                    expected.button = id == 1 && swap && button < 4 && types[t] != 0x600 ? button ^ 1 : button;
                    unsigned before = expected.calls;
                    emit(types[t], id, button, down);
                    assert(expected.calls == before + 1);
                }
            }
        }
    }
    remove(receive, &expected);
    unsigned before = expected.calls;
    emit(0x651, 1, 0, true);
    assert(expected.calls == before);
    printf("PASS: Xbox identity, swap=%s, press/release, unrelated devices/buttons/events, watcher removal\n", swap ? "on" : "off");
    dlclose(library);
}
