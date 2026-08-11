# FKeys, handoff

Public repo. macOS menu bar app. Swaps the top row so F1 to F12 work on their
own, with the printed controls still on fn. Distributed as a Homebrew cask.

## The mechanism, after three failed ones

**Key remapping through `/usr/bin/hidutil`. Nothing else.**

Do not reintroduce any of these, all three were tried and all three failed on
Apple Silicon:

1. `defaults write com.apple.keyboard.fnState` — persists the value, changes
   nothing until the next login.
2. `IOHIDSystem` + `IOConnectSetCFProperty` on `HIDFKeyMode` — **accepts the
   write, returns KERN_SUCCESS, and does nothing.** This shipped and made the
   menu bar letter flip while the keyboard ignored it. A success code from that
   API means nothing.
3. `IOHIDEventSystemClient` / `IOHIDServiceClientSetProperty` on `HIDFKeyMode` —
   **traps the process with SIGTRAP and no message** on the write, while reads
   work. It killed the app on every click.

`HIDFKeyMode` does not exist as a hidutil property either: `--set` echoes it
back and `--get` returns `(null)`.

`UserKeyMapping` is the one keyboard mechanism Apple documents (TN2450) and it
works, unprivileged, no permissions.

## How the mapping is built

Every Mac publishes `FnFunctionUsageMap` in the IO registry, pairing each top
row key's with-fn code against its pressed-alone code. `FnKeyMap` reads it with
`ioreg -l -w 0 -k FnFunctionUsageMap` and swaps every pair **both ways**, so
pressing alone gives the function key and holding fn gives back the printed
control. A built in table covers Macs that publish nothing, such as Touch Bar
models.

**Widening is the silent trap.** The registry packs page and usage into 32 bits;
hidutil wants 64, upper half page, lower half usage. `0x000c00e9` becomes
`0xc000000e9`. Get it wrong and hidutil accepts the number and nothing happens.

## Things that will surprise someone later

- **The System Settings checkbox stays unticked** while the keyboard behaves as
  though it were ticked. Nothing touches `fnState` any more. This is expected,
  not a bug.
- **hidutil replaces the whole `UserKeyMapping` table, it does not merge.** Any
  mapping set by another tool is lost when FKeys writes.
- **A reboot or unplugging the last keyboard clears the mapping.** The chosen
  state is stored in `UserDefaults` and `reapplyIfNeeded()` restores it at
  launch, on wake, and when a session becomes active.
- Reading state is a subprocess call, so it never runs on the launch path. The
  letter is painted from the remembered choice first and corrected in the
  background. An item with no title renders zero pixels wide and looks exactly
  like the app failing to start; that shipped once.

## Inherited traps, already applied

- `Package.swift` is **swift-tools-version 5.9. Do not raise it.**
- `build_app.sh` probes for `xcbuild`; universal builds need full Xcode.
- No bash arrays in scripts, macOS bash 3.2 aborts on empty array expansion.
- Artwork in tracked `assets/`; `packaging/` is gitignored generated output.
- Rolling `latest` release tag, fixed asset name `FKeys.zip`, hardcoded in the
  cask. Do not rename either.

## Hotkey

Control Option Command K, via Carbon `RegisterEventHotKey`. **Never replace with
a CGEvent tap**: a tap sees every keystroke and needs Accessibility permission.
FKeys still requires no permissions at all.
