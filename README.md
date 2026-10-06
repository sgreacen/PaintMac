# Scottware PaintMac

**A Scottware utility.** Create. Edit. Make it yours.

Created by **Scottware Software** — Built clean. Runs smooth. The Scottware maker logo appears in the editor header and **Scottware PaintMac → About Scottware PaintMac**.

A native macOS raster editor inspired by Paint.NET, built with Swift, AppKit, Core Graphics, and Core Image. Runs directly on macOS 13+.

## Open the app

The compiled app is in **`dist/Scottware PaintMac.app`**. Double-click it, or run:

```sh
open "dist/Scottware PaintMac.app"
```

## Install

Run `bash scripts/build-installer.sh`, then open the disk image it writes to `dist/` (for example `dist/Scottware-PaintMac-1.0-Apple-Silicon.dmg`), drag **Scottware PaintMac.app** onto **Applications**, and eject the image. Launch the installed app from Applications.

The installer filename includes the version and build architecture (`Apple-Silicon`, `Intel`, or `Universal`), so you can pick the right image for your Mac. It requires macOS 13 or newer and includes installation instructions and an Applications shortcut. The app is ad-hoc signed for local use; the installer is not Developer ID signed or notarized, so macOS may ask you to approve the app under **System Settings → Privacy & Security** on first launch of a downloaded copy.

The script rebuilds the app, creates a compressed read-only disk image, verifies its integrity, mounts it to check the app signature and contents, and writes a SHA-256 checksum beside the installer.

## Features

- **12 tools:** brush, one-pixel pencil, eraser, flood fill, two-color gradient, color picker, line, rectangle, ellipse, text, rectangular selection, and layer movement.
- **Layers:** add, duplicate, rename, delete, reorder, hide, change opacity, and choose from seven blend modes. Import or paste images as new layers.
- **Selections:** constrain painting and effects, copy/cut, clear pixels, or crop the entire image.
- **Image operations:** resize, rotate clockwise, flip horizontally/vertically, flatten.
- **Effects:** grayscale, invert, sepia, Gaussian blur, sharpen, brighten, contrast, and saturation.
- **History:** undo/redo, recent-edits panel, and save-state tracking.
- **Files:** open common macOS-supported image formats, save editable `.paintmac` projects, and export PNG or JPEG.
- **Canvas:** transparency checkerboard, zoom, pan, pixel grid at high zoom, coordinate display, and drag-and-drop opening.

## Quick start

1. Paint on the default white canvas, or use **File → New** for custom dimensions and transparency.
2. Pick a tool on the left. Change size, opacity, bucket tolerance, shape fill, and text size along the top.
3. Click the primary or secondary color well to use the macOS color picker, or choose a palette swatch.
4. Add layers with **+** in the Layers panel. The selected layer receives your edits; the top row renders on top.
5. Save with **⌘S** to preserve layers. Export with **⇧⌘E** to create a PNG for sharing.

Text is rasterized when placed; put it on its own layer if you want to move or remove it independently. Layer names are committed with Return. Image imports/pastes retain their original pixel size, positioned at the selection origin or the top-left of the canvas. Pixels outside the canvas are clipped.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Brush / Pencil / Eraser | B / P / E |
| Fill / Gradient / Color picker | F / G / I |
| Line / Rectangle / Ellipse | L / R / O |
| Text / Select / Move layer | T / S / M |
| Brush size | [ / ] |
| Swap colors / reset to black and white | X / D |
| Sample visible color | Option-click |
| Paint with secondary color | Right-click/drag |
| Constrain shapes / snap line to 45° | Shift-drag |
| Pan | Space-drag or middle-button drag |
| Zoom | Pinch, ⌘-scroll, ⌘+ / ⌘− |
| Fit / actual pixels | ⌘0 / ⌘1 |
| Undo / redo | ⌘Z / ⇧⌘Z |
| Select all / deselect | ⌘A / ⌘D or Escape |
| Clear selected pixels on active layer | Delete |
| Crop all layers to selection | ⌘K |
| Copy active layer / copy visible composite | ⌘C / ⇧⌘C |
| Cut / paste as new layer | ⌘X / ⌘V |
| Add layer / duplicate layer | ⇧⌘N / ⇧⌘D |
| Save project / save as | ⌘S / ⇧⌘S |
| Import image as layer | ⇧⌘O |
| Export PNG | ⇧⌘E |

## Build

Requires Swift 5.9+ and Xcode Command Line Tools:

```sh
xcode-select --install  # if tools are not installed
bash scripts/build-app.sh
open "dist/Scottware PaintMac.app"
```

The script builds the release binary, assembles the app bundle, generates the app icon, lints and ad-hoc signs the result for local use. The output targets the build Mac's architecture. Developer ID signing and notarization are separate distribution steps.

## Verify

```sh
swift run -c release PaintCoreChecks
"./dist/Scottware PaintMac.app/Contents/MacOS/PaintMac" --smoke-test
```

Core checks cover exact pixel orientation, PNG/project round trips, alpha, compositing, flood fill, clipping, effects, transforms, and history. The UI smoke check builds the actual editor and synthesizes mouse gestures to verify drawing tools, selections, layer movement, undo/redo, and view rendering. It exits after completion. An optional `--snapshot /absolute/path.png` saves a rendering of the test window without screen-capture permissions.

## Scope and format

This is an independent Paint.NET-inspired editor, not a port or a complete feature-for-feature replacement. It uses its own `.paintmac` format, not Paint.NET `.pdn` files or plugins. A project is a versioned binary property list containing lossless PNG layers and layer properties. Selection and undo history are session-only.

The editor works on one document at a time and prompts to save before replacing or closing edited work. Exporting a flattened image does not mark the layered project as saved. There is no automatic crash recovery. Effects use fixed presets; moving a layer moves all its pixels and clips content at canvas edges. Eraser clears alpha at full strength. Brushes use per-segment opacity rather than a stroke-wide opacity mask.

Canvas dimensions are limited to 8192 pixels per side and 16 megapixels total. Documents allow up to 32 layers or 512 MB of uncompressed layer pixels. History retains up to 40 snapshots within an approximately 192 MB snapshot budget, with at least one undo retained. Large fills, effects, and file operations run synchronously and can briefly pause the interface.

## Source layout

- `Package.swift`: Swift package manifest for the three targets below.
- `scripts/Sources/PaintCore/`: pixel engine, compositing, project serialization, history.
- `scripts/Sources/PaintMac/`: native window, menus, drawing interactions, file workflows.
- `scripts/Sources/PaintCoreChecks/`: dependency-free integration checks.
- `Resources/Info.plist`: app metadata and project/image file associations.
- `Resources/Install.rtf`: instructions bundled into the installer disk image.
- `scripts/`: app packaging, installer packaging, and icon generation.

## License

MIT — see [LICENSE](LICENSE).
