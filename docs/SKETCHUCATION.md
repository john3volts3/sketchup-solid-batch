# Solid Batch — SketchUcation Plugin Page Content

This file contains all text content for the SketchUcation PluginStore listing.
Copy-paste each section into the corresponding field in the Dev Tool.

---

## Metadata

- **Plugin name:** Solid Batch
- **Version:** 2.2.1
- **Author:** DRO
- **Category:** Construction, Modification
- **Compatibility:** v2017, v2018, v2019, v2020, v2021/22, v2023, v2024, v2025, v2026
- **Dependencies:** None
- **License:** Free
- **Platforms:** Windows & macOS
- **Icon:** `docs/Solid_Batch.png`
- **Short description (255 chars max):** Combine Union and Subtract in a single click. Paint objects with a color to mark them for subtraction, select all solids, click once: bases are unioned, colored tools are subtracted. Broken circles and arcs are automatically restored.

---

## Overview

### Description

Solid Batch automates batch boolean operations on multiple solids using SketchUp Pro's native boolean engine.

When designing technical parts for 3D printing or complex architectural models, a common workflow is to build up shapes from simple volumes — boxes, cylinders, extrusions — then combine them using boolean operations. Manually running union and subtract on dozens of objects one by one is tedious and error-prone. Solid Batch automates this: select all your solids, click once, and the plugin unions the bases and subtracts the tools in a single batch operation with a single undo step.

### Features

- **Combine All (Union)** — Select multiple solids, automatically union all base solids then subtract color-marked objects. Single undo step.
- **Combine All (Shell)** — Same workflow using Outer Shell instead of Union (merges overlapping volumes into one outer envelope).
- **Set Subtract Color** — Pick a color from a selected object to mark which solids should be subtracted during Combine All.
- **Automatic circle and arc restoration** (SketchUp 2020.1+) — Native boolean operations break circles and arcs into individual segments. Solid Batch detects and welds them back into single-click selectable curves.
- **Set Repair Options** (SketchUp 2020.1+) — Configure circle/arc restoration: auto-repair toggle, large object threshold, minimum segments for arc detection.
- **Status bar progress** — Real-time progress during batch operations (e.g. "Subtract 7/13 (54%)").
- **No dependencies** — Pure Ruby, no external libraries required.

### Compatibility

| SketchUp version | Available features |
|---|---|
| Pro 2017 – 2019 | Combine All (Union), Combine All (Shell), Set Subtract Color |
| Pro 2020.1+ | All of the above + automatic circle/arc restoration + Set Repair Options |

All operations use SketchUp Pro's native boolean engine (`union`, `outer_shell`, `subtract`) for maximum reliability.

### Requirements

- **SketchUp Pro** 2017 or later (the native boolean methods are Pro-only)
- Windows or macOS
- No dependencies

### Installation

1. Download the `solid_batch.rbz` file
2. In SketchUp: **Window > Extension Manager > Install Extension**
3. Select the downloaded `.rbz` file
4. Restart SketchUp
5. The toolbar and menu appear under **Extensions > Solid Batch**

### Quick Start

1. Paint the objects you want to subtract with a specific color of your choice
2. Select one of those painted objects, then click **Set Subtract Color** to register that color
3. Select all your solids (bases + tools)
4. Click **Combine All (Union)** or **Combine All (Shell)**
5. Done — one solid, one undo step

### Video Demo

https://youtu.be/y5_-0-7OkBw

---

## Release Notes

**v2.2.1** (2026-04-12)
- Backward compatibility with SketchUp Pro 2017+
- Circle/arc restoration gracefully skipped on SketchUp < 2020.1
- Set Repair Options hidden on versions without weld support

**v2.2.0** (2026-04-11)
- Automatic arc restoration in addition to circles
- New "Min segments for arc detection" parameter in Set Repair Options
- Improved detection algorithm (separate stages for circles and arcs)

**v2.1.0** (2026-04-11)
- Automatic circle restoration after boolean operations (Phase 3)
- New "Set Repair Options" command with configurable threshold
- New toolbar icon for repair options

**v2.0.0** (2026-04-04)
- Complete rewrite using native SketchUp Pro boolean methods
- Added Combine All (Union) and Combine All (Shell)
- Added Set Subtract Color with persistent color
- Status bar progress display
- Transparent operations for single undo step
- Removed custom boolean engine and individual operations

---

## Documentation (copy-paste this into the Documentation field)

## Features

- **Combine All (Union)** — Select multiple solids, automatically union all base solids then subtract color-marked objects. Single undo step.
- **Combine All (Shell)** — Same workflow using Outer Shell instead of Union (merges overlapping volumes into one outer envelope).
- **Set Subtract Color** — Pick a color from a selected object to mark which solids should be subtracted.
- **Automatic circle and arc restoration** (SketchUp 2020.1+) — Native boolean operations break circles and arcs into individual segments. Solid Batch detects and welds them back into single-click selectable curves.
- **Set Repair Options** (SketchUp 2020.1+) — Configure circle/arc restoration behavior.

## Compatibility

| SketchUp version | Available features |
|---|---|
| Pro 2017 – 2019 | Combine All (Union), Combine All (Shell), Set Subtract Color |
| Pro 2020.1+ | All of the above + circle/arc restoration + Set Repair Options |

## Workflow

1. Paint the objects you want to subtract with a color of your choice
2. Select one of those painted objects, click **Set Subtract Color** to register the color
3. Select all your solids (bases + tools)
4. Click **Combine All (Union)** or **Combine All (Shell)**

**Union vs Shell:**
- **Union** preserves internal geometry (voids, internal faces)
- **Outer Shell** removes all internal geometry and keeps only the outer surface

## Troubleshooting

- **"This function requires SketchUp Pro"** — The native boolean methods are Pro-only.
- **"Select at least 2 solid group(s)"** — Select at least 2 valid solid groups or components.
- **"No base objects found"** — All selected objects have the subtract color. At least one must be different.
- **Undo** — All operations revert with a single Ctrl+Z (Cmd+Z on Mac).

---

## Screenshots to capture

The user should capture the following screenshots in SketchUp:

1. **Toolbar** — The Solid Batch toolbar showing all buttons (3 buttons on SU2017, 4 buttons on SU2021+)
2. **Before** — A selection of multiple solids (bases in gray/default + tools in red), ready for Combine All
3. **After** — The result after Combine All (Union): a single merged solid
4. **Subtract color dialog** — The messagebox after setting the subtract color
5. **Progress** — The status bar showing progress during a batch operation
6. **Circle restoration** — Before/after showing circles restored as single-click selectable curves (SU2021+)
7. **Set Repair Options dialog** — The inputbox with the three configuration fields (SU2021+)
