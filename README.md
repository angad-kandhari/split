<p align="center">
  <img src="assets/logo.svg" width="112" alt="Split logo">
</p>

<h1 align="center">Split</h1>

<p align="center">Windows 11-style Snap Layouts for macOS.<br>Room for everything on screen.</p>

---

> **Status: early development.** There is no release to download yet. This README describes what Split is being built to do; the roadmap below shows what works today.

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

## Why not the Mac App Store?

Moving other apps' windows requires the Accessibility API, which sandboxed App Store apps cannot use. Split is distributed directly as a signed and notarised download.

## Licence

[MIT](LICENSE)
