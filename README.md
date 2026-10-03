<p align="center">
  <img src="assets/logo.svg" width="112" alt="Split logo">
</p>

<h1 align="center">Split</h1>

<p align="center">Windows 11-style Snap Layouts for macOS.<br>Room for everything on screen.</p>

---

> **Status: pre-release.** The features below work when built from source. There is no notarised download yet.

## What it is

macOS tiling stops at halves and quarters. Split is a menu bar app that brings the full Snap Layouts experience from Windows 11 to the Mac:

- **Layout picker.** Click the menu bar icon or press <kbd>⌃</kbd><kbd>⌥</kbd><kbd>S</kbd>, then click a zone. The window you were just using snaps into it.
- **Snap Assist.** After you snap one window, Split shows your other windows in each empty zone so you can fill the layout in a couple of clicks.
- **Snap Groups.** Windows snapped together stay together: drag a shared edge and the neighbours resize with it, focus one and the rest come forward, and restore a whole group from the menu bar.
- **Custom layouts.** Six built-in layouts (halves, two-thirds, thirds, quarters, half plus two stacked, narrow-wide-narrow) and an editor for your own: split a zone, drag the dividers, merge zones back.
- **Keyboard movement.** <kbd>⌃</kbd><kbd>⌥</kbd> + arrow keys move the focused window to the neighbouring zone, and across to the next display at the edge.

## Requirements

- macOS 26 or later
- Accessibility permission (to move and resize windows)
- Screen Recording permission (optional, for window thumbnails in Snap Assist)

## Roadmap

- [x] Layout model and geometry (`SplitCore`)
- [x] Snap a window to a zone; arrow-key movement
- [x] Layout picker in the menu bar
- [x] Snap Assist
- [x] Snap Groups with linked resize
- [x] Custom layout editor
- [x] Settings: shortcuts, launch at login, ignored apps
- [ ] Signed, notarised release with automatic updates

## Building from source

Requires Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
git clone https://github.com/angad-kandhari/split.git
cd split
xcodegen generate
open Split.xcodeproj
```

The core layout logic is a standalone Swift package and can be tested on its own:

```sh
cd Packages/SplitCore
swift test
```

## Releasing

`scripts/release.sh <version>` archives the app, signs it with Developer ID, notarises and staples it, builds a DMG and writes the Sparkle update feed. It needs a `notarytool` keychain profile named `split-notary` and the Sparkle signing key in the login keychain. `SKIP_NOTARIZE=1` stops after signing for a local dry run.

## Private API

Split uses two undocumented macOS calls, as other Mac window managers do: one maps an Accessibility window to its window ID, and one brings another app's window to the front, which is what lets a Snap Group come forward together. They may change in a future macOS release.

## Why not the Mac App Store?

Moving other apps' windows requires the Accessibility API, which sandboxed App Store apps cannot use. Split is distributed directly as a signed and notarised download.

## Licence

[MIT](LICENSE)
