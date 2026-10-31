# Changelog

All notable changes to PinMac are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-10-28

Picture-in-picture features and a new look.

### Added
- **Crop**: float only part of a pinned window, such as just the video in a
  browser tab. Choose the area in an overlay, drag to move it, press Return.
- **Crop shortcut ⌃⌘R**: in a pinned window, opens the crop view, or shows the
  whole window again if it's cropped. Elsewhere, resets every cropped window.
- **Opacity While Floating**: make a pinned window 80%–20% see-through while it
  floats over other windows.
- **Click Through**: clicks pass through a floating window to what's underneath.
- Per-window options menu under 📌 → *Pinned*, with *Bring to Front* and *Unpin*.
- **Shortcuts…** popover for changing every shortcut.
- **Opacity shortcut ⌃⌘O**: steps a pinned window's opacity from 100% down to
  20%, with an on-screen label. Hover over a pinned window to pick it.
- The About window lists all three shortcuts.
- **Smooth Switching** option: keeps pinned windows' copies live, so switching
  never shows an old frame. The screen-recording indicator stays on.

### Changed
- README and Welcome Guide cover the new features, with a quick start,
  shortcut list, menu reference, and troubleshooting.
- New app icon: PinMac's own tilted pin on deep purple. The menu-bar icon uses
  the same pin (outline when nothing is pinned, filled when something is).

### Fixed
- With more than one global shortcut, each now triggers only its own action.
- The crop overlay's buttons fit on narrow windows.
- Pinned windows no longer flicker when you click a window behind them or
  switch apps.

## [1.0.0] - 2026-08-31

First release.

### Added
- Pin the frontmost window on top with **⌃⌘T**, like PowerToys' Always On Top.
- Pinned windows keep their order among themselves and stay above all others.
- Colored border that follows each window's corner radius, hidden while the
  window moves.
- Border colors: accent color, 8 presets, or a custom color with a
  saturation/brightness picker, hex input, and saved colors.
- Pinned windows follow you to every Space, including full-screen apps.
- Custom pin shortcut, pin/unpin sounds, and Launch at Login.
- Welcome window that explains the shortcut and sets up permissions.
- About window with links to the project.
- Screen capture runs only while a pinned window is covered, so macOS's purple
  recording indicator turns off when pinned windows are in front.

### Fixed
- Crash when opening the welcome window.
- Empty "PinMac" windows showing in Mission Control and App Exposé.

[1.1.0]: https://github.com/ElleDiablo/PinMac/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ElleDiablo/PinMac/releases/tag/v1.0.0
