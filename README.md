# PinMac 📌

**Keep any window on top — on macOS.** A tiny menu-bar app inspired by the
*Always On Top* utility in Microsoft PowerToys.

Press **⌃⌘T** (Control + Command + T) to pin the frontmost window. Press it
again to unpin. You can change the shortcut from the menu bar. Pinned windows get a colored border and stay visible above
everything else.

## Install

1. Download the latest `PinMac-x.y.z.dmg` from [Releases](../../releases).
2. Open it and drag **PinMac** into **Applications**.
3. The app isn't notarized by Apple, so the first time, **right-click PinMac → Open → Open**.
   (Or run `xattr -dr com.apple.quarantine /Applications/PinMac.app`.)
4. The welcome window walks you through two permissions (System Settings → Privacy & Security):
   - **Screen Recording**: to show a live copy of the pinned window
   - **Accessibility**: to bring the real window forward when you click it

Requires macOS 14 Sonoma or later (Apple Silicon and Intel).

## Usage

| Action | How |
| --- | --- |
| Pin / unpin frontmost window | **⌃⌘T**, or menu bar 📌 → *Pin / Unpin Frontmost Window* |
| Change a shortcut | Menu bar 📌 → *Shortcuts…*, click the box, press new keys |
| Unpin a specific window | Menu bar 📌 → the window under *Pinned* → *Unpin* |
| Make a pinned window see-through | Menu bar 📌 → the window → *Opacity While Floating* |
| Float only part of a window | In a pinned window press **⌃⌘R**, or menu bar 📌 → the window → *Crop to Part of Window…*; drag a box, press Return |
| Show a cropped window whole again | **⌃⌘R** again, or menu bar 📌 → the window → *Reset to Whole Window* |
| Click through a pinned window | Menu bar 📌 → the window → *Click Through* (use *Bring to Front* to work in it) |
| Unpin everything | Menu bar 📌 → *Unpin All* |
| Show / hide the border | Menu bar 📌 → *Border* → *Show Border* |
| Change the border color | Menu bar 📌 → *Border* → pick a color, or *Custom Color…* |
| Turn the pin / unpin sounds on or off | Menu bar 📌 → *Play Sounds* |
| Start automatically | Menu bar 📌 → *Launch at Login* |

## How it works

Unlike Windows, macOS has **no public API that lets one app make another
app's window float**. Older tools injected code into other apps, which modern
macOS (with System Integrity Protection) blocks.

PinMac uses a different approach:

1. It captures the pinned window on its own with **ScreenCaptureKit**, which
   keeps working even when other windows cover it.
2. When something else is in front, PinMac shows that live capture in a
   borderless **floating panel** sitting exactly over the real window.
3. When the real window is already in front, the floating copy hides, so
   you're working with the real window directly.
4. Clicking the floating copy brings the real window to the front through
   the **Accessibility API**.
5. The floating copy can be made see-through, so you can watch a video or
   follow a reference while seeing your work underneath. (macOS doesn't let
   one app make another's real window transparent, so opacity applies while
   the copy is floating over other windows.)
6. Pinned windows follow you to every Space, including full-screen apps,
   where they appear as the live copy.

### Limitations

- While another app is in front, the pinned window is a live *view*: the
  first click brings the real window forward, and the next clicks go to it.
- Scrolling or typing into the pinned window requires clicking it first.
- On another Space or over a full-screen app, clicking a pinned window
  switches back to the Space it lives on.
- The border hides while a window is being dragged or resized, and comes
  back as soon as it stops.
- macOS shows its purple screen-recording indicator in the menu bar while
  PinMac is capturing. PinMac only captures while a pinned window is covered,
  so the indicator goes away when your pinned windows are in front.

## Build from source

You need the Xcode Command Line Tools (`xcode-select --install`) or Xcode.

```bash
git clone https://github.com/ElleDiablo/PinMac.git
cd PinMac
scripts/build.sh 1.0.0      # → build/PinMac.app and build/PinMac-1.0.0.dmg
open build/PinMac.app
```

> Local builds are ad-hoc signed by default, so macOS may ask for permissions
> again after each rebuild. To avoid that, sign with your own certificate:
> `SIGN_IDENTITY="Apple Development: you@example.com" scripts/build.sh`
> (list yours with `security find-identity -v -p codesigning`).

### Project layout

```
Sources/PinMac/
  main.swift            app entry point (menu-bar only)
  AppDelegate.swift     status-bar menu, hotkey, settings
  HotKey.swift          global shortcut registration (Carbon)
  Shortcut.swift        shortcut model, storage, and recorder popover
  BorderColorPicker.swift  border color popover
  Welcome.swift         first-launch guide and permission setup
  CropSelector.swift    overlay for choosing the part of a window to float
  About.swift           About window
  HostingWindow.swift   fixed-size windows for SwiftUI views
  PinManager.swift      tracks pinned windows ~30×/second
  PinnedWindow.swift    floating mirror panel + border for one window
  WindowStream.swift    ScreenCaptureKit live capture
  WindowList.swift      reads the on-screen window list
  Accessibility.swift   raises windows, permission helpers
scripts/
  build.sh              builds the .app and .dmg
  make-icon.swift       draws the app icon
```

### Releasing

Push a version tag and GitHub Actions builds the DMG and attaches it to a release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Contributing

Issues and pull requests are welcome!

## License

[MIT](LICENSE)
