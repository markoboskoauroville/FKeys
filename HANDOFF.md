# FKeys, handoff

Public repo. macOS menu bar app, one click switches F1-F12 between function
keys and media controls.

## The crash fuse, per stage

**The click traps, the launch does not.** Reading the mode works on his Mac;
writing it kills the process with SIGTRAP and no message, which points at a
system framework calling `__builtin_trap` rather than a Swift error.

The first fuse guarded only the enumeration, so the flag was always cleared
before the fatal write and it could never trip. `HIDSafety` is now per stage:
`hidutil.write`, `devices.enumerate/write/read`, `services.enumerate/write/read`,
`legacy.write`. Every risky call is wrapped individually. A stage that kills the
app is disabled permanently at the next launch and the others carry on, so the
worst case is one crash per bad stage and the diagnostics then name it.

`HIDSafety.inspectPreviousRun()` must stay the first statement in
`applicationDidFinishLaunching`.

Order of attempts in `set` is deliberate: **`/usr/bin/hidutil` first**, because
it runs in a separate process and cannot take FKeys down whatever happens. Only
then the in-process routes.

## Old notes on the single fuse

`HIDSafety` writes a flag to `UserDefaults` and forces it to disk immediately
before entering the private symbol path, and clears it immediately after. If the
flag is still set at the next launch, the app did not survive the last attempt,
so the private path is disabled permanently and only the public `IOHIDManager`
and legacy routes are used.

This exists because a menu bar app that dies at launch leaves nothing to click
and no way out. Worst case FKeys crashes once and then heals itself. The menu
offers `Retry advanced keyboard access` to undo the fuse after a fix ships, and
diagnostics report whether it tripped.

`HIDSafety.inspectPreviousRun()` must stay the first statement in
`applicationDidFinishLaunching`, before anything can touch HID.

## Never touch HID on the launch path

**The status item must have a visible title before any HID call happens.**

A HID read waits on another process. If that wait is slow, `applicationDidFinishLaunching` has already created the `NSStatusItem` but has not yet given its button a title, so the item renders as a zero width sliver. The app is running perfectly and the menu bar looks empty. This shipped once and read as a crash.

The launch path therefore paints from `FnKeyMode.storedPreference`, which is a
local preference read and instant, then `refreshFromHardware()` does the real
read on a background queue and repaints. Toggling goes through the same split.

`render(functionKeys:)` is the only thing that writes the title, and it is
always called on the main thread with a value already in hand.

## Three layers, only one of which works on Apple Silicon

**IOHIDSystem accepts the write, returns KERN_SUCCESS, and does nothing.** That
was the original implementation and it shipped broken: the menu bar letter
flipped because the preference write succeeded, while the keyboard never
changed. A success return code from this API proves nothing.

Current order of attempts in `FnKeyMode.set`:

1. `HIDServices` — `IOHIDEventSystemClient` / `IOHIDServiceClientSetProperty`,
   per keyboard service. This is the layer System Settings uses and the one that
   works on Apple Silicon. The symbols are not in any public header, so they are
   resolved with `dlsym` and `isAvailable` guards the fallback.
2. `HIDDevices` — public `IOHIDManager`, same `HIDFKeyMode` property on the
   device. **Never call `IOHIDManagerOpen`**: enumerating needs no permission,
   opening triggers the Input Monitoring prompt and would cost FKeys its one
   real advantage.
3. `IOHIDSystem` — legacy, kept only for older Intel Macs.

**Nothing trusts a return code.** `set` reads the value back out of the hardware
and reports failure when the read back disagrees. `isFunctionKeyMode` also reads
from hardware first and only falls back to the stored preference when no
keyboard answers, so the letter cannot drift away from reality.

`Copy diagnostics` in the menu reports which layer answered. That is the first
thing to ask for when someone says it does not work.

## The preference, and why it is not enough

`defaults write -g com.apple.keyboard.fnState` **does not work on its own.** It
writes the preference but nothing reads it until the next login. Every "why
doesn't this work" thread about this setting is that mistake.

AppleScript clicking the System Settings checkbox works but only on an English
system, and breaks whenever Apple rearranges the pane.

`FnKeyMode` does all three necessary steps:

1. `IOServiceOpen` on `IOHIDSystem` with connect type **1**
   (`kIOHIDParamConnectType`, hardcoded because that enum is not surfaced to
   Swift), then `IOConnectSetCFProperty` on key `HIDFKeyMode`. This is what
   makes it immediate.
2. `CFPreferencesSetAppValue("fnState", …, "com.apple.keyboard")` to persist.
3. Post `com.apple.keyboard.fnstatedidchange` distributed notification so
   System Settings and anything else re-reads.

No Accessibility permission, no Input Monitoring, no root.

## Hotkey

⌃⌥⌘K toggles, via Carbon `RegisterEventHotKey` in `HotKeyCenter`.

**Never replace this with a CGEvent tap.** A tap sees every keystroke on the
system and requires Accessibility permission, which would throw away the app's
one real selling point. A registered hotkey receives that combination only.

If another app already owns the combination, registration fails, `isRegistered`
goes false, and the tooltip says so. Clicking still works, so this is never an
alert.

## Distribution

Repo is **public on purpose**, so a Homebrew **cask** can download the release
asset. A private repo cannot do this without credentials on every machine, and a
formula would build from source, which needs a working toolchain.

CI publishes to a **rolling `latest` tag** with a fixed asset name `FKeys.zip`.
The cask uses `version :latest` and `sha256 :no_check` because the artifact
changes on every push. **Do not rename the tag or the asset**, the cask URL is
hardcoded to both.

The cask's `postflight` strips the quarantine attribute, because the app is
ad-hoc signed rather than notarized and macOS would otherwise refuse to open it.

## Inherited traps, already applied here

- `Package.swift` is **swift-tools-version 5.9. Do not raise it.** The manifest
  is compiled by whatever Swift the user has, and `swiftLanguageModes` is 6.0
  only. Below 6.0 the default language mode is already Swift 5.
- `build_app.sh` probes for `xcbuild` before asking for a universal build.
  Universal builds need full Xcode; Command Line Tools alone cannot do it.
- No bash arrays in scripts. macOS bash 3.2 aborts on empty array expansion
  under `set -u`.
- Source artwork lives in `assets/` and is tracked. `packaging/` is gitignored
  generated output, and anything left there silently fails to ship.

## Open

- The menu bar letter is monospaced system font, white in both states. It is a
  plain white, not `labelColor`, so it does not follow the appearance setting.
  On a light menu bar it will be hard to read. Switch `letterColor` to
  `NSColor.labelColor` if that ever becomes a problem.
- If a specific typeface is wanted it has to be bundled into the app and
  registered at runtime.
- No preferences window. Everything is the right click menu.
