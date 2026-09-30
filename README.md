# MacOS Xbox Controller Helper

A macOS app that launches Steam with Xbox identification for compatible Switch Pro controllers.

## How to use

1. Open Xbox Controller Helper.app.
2. Connect the controller in Switch Pro mode.
3. Click Open Steam or Restart Steam to apply the fix.

Auto-detect controllers prompts when a matching controller connects and Steam needs the fix. Show menu bar icon keeps status and shortcuts available. Swap A/B and X/Y changes the face-button mapping on the next Steam launch.

Hide keeps the helper running. Reopen it or use the menu bar icon to return to settings. Preferences are saved between launches.

## How it works

The fix is the bundled library xbox-identity.dylib. The helper starts Steam with DYLD_INSERT_LIBRARIES so macOS loads the library into Steam's process.

The library intercepts SDL3 controller identification calls and reports matching controllers as Xbox One. Optional event translation swaps A/B and X/Y presses and releases. The fix lasts for that Steam session.

The helper uses IOKit to detect controller connections and checks Steam's loaded libraries to determine whether the fix is active.

## Compatibility

Requires an Apple silicon Mac, macOS 13 or later, and Steam. Matching controllers report vendor/product IDs 057e:2009 in Switch Pro mode.

Game compatibility depends on how each game reads controller identity. Steam updates may require changes to the library.

## Build

Requires Xcode Command Line Tools.

```sh
./scripts/build.sh
./scripts/test.sh
open 'dist/Xbox Controller Helper.app'
```

The build creates a locally signed app in dist. The app runs on arm64; the library includes arm64 and x86_64 support for game processes.
