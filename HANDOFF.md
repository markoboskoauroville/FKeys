# FKeys, handoff

Public repo. macOS menu bar app, one click switches F1-F12 between function
keys and media controls.

## The mechanism, and why the obvious routes fail

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
