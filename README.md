# FKeys

Switch the F1 to F12 keys between function keys and media controls with one
click in the menu bar.

- **F** means F1 to F12 are plain function keys.
- **C** means they are the printed controls: brightness, volume, playback.

Both letters are white.

Left click the letter to switch. Right click for the menu.

Or press **⌃⌥⌘K** from anywhere. Hovering the letter shows the shortcut along
with what the keys currently do.

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

The ⌃⌥⌘K shortcut is a registered hotkey, not a keyboard monitor. FKeys asks the
window server to deliver that one combination and never sees any other keystroke,
which is why it still needs no Accessibility or Input Monitoring grant.

## How it works

FKeys swaps the top row using **key remapping**, the one keyboard mechanism
Apple documents, applied through their own `hidutil` tool. Each key's
pressed-alone code and its with-fn code are exchanged, so F1 to F12 work
directly and brightness, volume and the rest move onto fn.

It reads your Mac's own key table rather than assuming a layout, so it is
correct on any model.

Three other approaches were tried first and all failed on Apple Silicon:
`defaults write com.apple.keyboard.fnState` persists the value but changes
nothing until the next login; the old `IOHIDSystem` call accepts the write,
reports success and does nothing; and the private event system call crashes the
process outright. None of them are used any more.

**The System Settings checkbox will stay unticked** while your keyboard behaves
as though it were ticked. FKeys no longer touches that setting, because on this
hardware it cannot be made to work.

Two consequences worth knowing: hidutil replaces the whole remapping table, so
a mapping set by another tool is overwritten; and a reboot clears the mapping,
which FKeys re-applies automatically at launch and after waking.

## Build from source

```
swift build -c release
VERSION=1.0.0 BUILD=1 ./scripts/build_app.sh
```

Requires macOS 13 or later.

## Licence

MIT.
