#include <dlfcn.h>
#include <stdint.h>
#include <stdbool.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Process-local metadata and optional face-button event shim. It intercepts
// dynamically resolved SDL3 calls, not the USB driver or input reports.
// Only Nintendo Switch Pro VID/PID 057e:2009 are eligible.
typedef uint16_t (*IDNumberFn)(uint32_t);
typedef uint16_t (*PadNumberFn)(void *);
typedef const char *(*IDNameFn)(uint32_t);
typedef const char *(*PadNameFn)(void *);
typedef int (*IDTypeFn)(uint32_t);
typedef int (*PadTypeFn)(void *);
typedef union {
    uint32_t type;
    struct { uint32_t type, reserved; uint64_t timestamp; uint32_t which; uint8_t button, down, pad1, pad2; } button;
    uint64_t storage[16]; // SDL3's public SDL_Event ABI is 128 bytes.
} SDLIdentityEvent;
typedef bool (*EventFilterFn)(void *, SDLIdentityEvent *);
typedef bool (*AddWatchFn)(EventFilterFn, void *);
typedef void (*RemoveWatchFn)(EventFilterFn, void *);
static IDNumberFn vendorID, productID;
static PadNumberFn vendorPad, productPad;
static IDNameFn gamepadNameID, joystickNameID;
static PadNameFn gamepadName;
static IDTypeFn gamepadTypeID;
static PadTypeFn gamepadType;
static AddWatchFn addWatch;
static RemoveWatchFn removeWatch;
static bool swapFaces = true;
typedef struct { EventFilterFn callback; void *userdata; bool active; } WrappedWatch;
static WrappedWatch watches[64];
static unsigned watchCount;
static pthread_mutex_t watchMutex = PTHREAD_MUTEX_INITIALIZER;
static int is_target_id(uint32_t id) {
    return vendorID && productID && vendorID(id) == 0x057e && productID(id) == 0x2009;
}
static int is_target_pad(void *pad) {
    return vendorPad && productPad && vendorPad(pad) == 0x057e && productPad(pad) == 0x2009;
}
static uint16_t fake_vendor_id(uint32_t id) { return is_target_id(id) ? 0x045e : vendorID(id); }
static uint16_t fake_product_id(uint32_t id) { return is_target_id(id) ? 0x02e0 : productID(id); }
static uint16_t fake_vendor_pad(void *pad) { return is_target_pad(pad) ? 0x045e : vendorPad(pad); }
static uint16_t fake_product_pad(void *pad) { return is_target_pad(pad) ? 0x02e0 : productPad(pad); }
static const char *fake_gamepad_name_id(uint32_t id) { return is_target_id(id) ? "Xbox One Controller" : gamepadNameID(id); }
static const char *fake_joystick_name_id(uint32_t id) { return is_target_id(id) ? "Xbox One Controller" : joystickNameID(id); }
static const char *fake_gamepad_name(void *pad) { return is_target_pad(pad) ? "Xbox One Controller" : gamepadName(pad); }
static int fake_gamepad_type_id(uint32_t id) { return is_target_id(id) ? 3 : gamepadTypeID(id); }
static int fake_gamepad_type(void *pad) { return is_target_pad(pad) ? 3 : gamepadType(pad); }

static bool translated_event(void *context, SDLIdentityEvent *event) {
    WrappedWatch *watch = context;
    if (swapFaces && (event->type == 0x603 || event->type == 0x604 || event->type == 0x651 || event->type == 0x652)
        && event->button.button < 4 && is_target_id(event->button.which)) {
        SDLIdentityEvent copy = *event;
        copy.button.button ^= 1; // A/B and X/Y; both press and release.
        return watch->callback(watch->userdata, &copy);
    }
    return watch->callback(watch->userdata, event);
}
static bool fake_add_watch(EventFilterFn callback, void *userdata) {
    pthread_mutex_lock(&watchMutex);
    if (watchCount == 64) { pthread_mutex_unlock(&watchMutex); return addWatch(callback, userdata); }
    WrappedWatch *watch = &watches[watchCount++];
    watch->callback = callback;
    watch->userdata = userdata;
    watch->active = true;
    pthread_mutex_unlock(&watchMutex);
    bool success = addWatch(translated_event, watch);
    if (!success) { pthread_mutex_lock(&watchMutex); watch->active = false; pthread_mutex_unlock(&watchMutex); }
    return success;
}
static void fake_remove_watch(EventFilterFn callback, void *userdata) {
    WrappedWatch *found = NULL;
    pthread_mutex_lock(&watchMutex);
    for (unsigned i = 0; i < watchCount; ++i) {
        if (watches[i].active && watches[i].callback == callback && watches[i].userdata == userdata) {
            found = &watches[i]; found->active = false; break;
        }
    }
    pthread_mutex_unlock(&watchMutex);
    if (found) removeWatch(translated_event, found);
    else removeWatch(callback, userdata);
    // Retain each context until process exit: an in-flight callback can still
    // reference it while SDL_RemoveEventWatch completes on another thread.
}

static void *identity_dlsym(void *handle, const char *symbol) {
    // dyld excludes calls originating inside the interposer itself from its
    // interposition, so this resolves the actual library implementation.
    void *original = dlsym(handle, symbol);
    if (!original || strncmp(symbol, "SDL_", 4)) return original;
    if (!vendorID) vendorID = (IDNumberFn)dlsym(handle, "SDL_GetJoystickVendorForID");
    if (!productID) productID = (IDNumberFn)dlsym(handle, "SDL_GetJoystickProductForID");
    if (!vendorPad) vendorPad = (PadNumberFn)dlsym(handle, "SDL_GetGamepadVendor");
    if (!productPad) productPad = (PadNumberFn)dlsym(handle, "SDL_GetGamepadProduct");
#define REPLACE(name, storage, wrapper) \
    if (!strcmp(symbol, name)) { storage = (__typeof__(storage))original; return (void *)&wrapper; }
    REPLACE("SDL_GetJoystickVendorForID", vendorID, fake_vendor_id)
    REPLACE("SDL_GetJoystickProductForID", productID, fake_product_id)
    REPLACE("SDL_GetGamepadVendor", vendorPad, fake_vendor_pad)
    REPLACE("SDL_GetGamepadProduct", productPad, fake_product_pad)
    REPLACE("SDL_GetGamepadNameForID", gamepadNameID, fake_gamepad_name_id)
    REPLACE("SDL_GetJoystickNameForID", joystickNameID, fake_joystick_name_id)
    REPLACE("SDL_GetGamepadName", gamepadName, fake_gamepad_name)
    REPLACE("SDL_GetGamepadTypeForID", gamepadTypeID, fake_gamepad_type_id)
    REPLACE("SDL_GetGamepadType", gamepadType, fake_gamepad_type)
    REPLACE("SDL_AddEventWatch", addWatch, fake_add_watch)
    REPLACE("SDL_RemoveEventWatch", removeWatch, fake_remove_watch)
    return original;
}

__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement; const void *original; } interposition = {
    (const void *)&identity_dlsym, (const void *)&dlsym
};

__attribute__((constructor)) static void announce(void) {
    const char *swap = getenv("X5_SWAP_FACE_BUTTONS");
    swapFaces = !swap || strcmp(swap, "0") != 0;
    if (getenv("X5_IDENTITY_DEBUG")) fprintf(stderr, "[X5 identity] Metadata shim loaded\n");
}
