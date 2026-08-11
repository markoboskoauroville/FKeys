# FKeys

Switch the F1 to F12 keys between function keys and media controls with one
click in the menu bar.

- **F** in dark orange means F1 to F12 are plain function keys.
- **C** means they are the printed controls: brightness, volume, playback.

Left click the letter to switch. Right click for the menu.

## Install

```
brew install --cask markoboskoauroville/pasty/fkeys
```

FKeys.app lands in your Applications folder. Open it once and the letter appears
in the menu bar. The cask installs a prebuilt app, so no Swift toolchain or
Xcode is needed.

## Permissions

None. FKeys needs no Accessibility grant, no Input Monitoring, no root.

It talks to the keyboard driver through IOKit the same way the System Settings
checkbox does, rather than using AppleScript to click that checkbox, which only
works on an English system.

## How it works

A change has to happen in three places to be both immediate and permanent:

1. `IOConnectSetCFProperty` on the IOHIDSystem service applies it to the
   hardware straight away.
2. `CFPreferences` writes `com.apple.keyboard.fnState` so it survives a reboot
   and so System Settings agrees.
3. A distributed notification tells anything already running to re-read it.

This is why `defaults write com.apple.keyboard.fnState` on its own appears to do
nothing until the next login. It does step 2 and skips step 1.

FKeys also re-reads the setting after waking from sleep and whenever anything
else changes it, so the letter never lies.

## Build from source

```
swift build -c release
VERSION=1.0.0 BUILD=1 ./scripts/build_app.sh
```

Requires macOS 13 or later.

## Licence

MIT.
