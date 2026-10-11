# Solid Batch — Functional Specification Document

**Version:** 2.3.0
**Date:** 2026-10-11
**Author:** DRO

---

## 1. Purpose

Solid Batch is a SketchUp Pro plugin that enables batch boolean operations on multiple solids in a single action. It targets users who need to combine and subtract many solid objects efficiently (e.g., architectural modeling, 3D printing preparation, mechanical assemblies).

## 2. Scope

### In scope
- Batch union of multiple solid objects using native SketchUp Pro API
- Batch outer shell of multiple solid objects using native SketchUp Pro API
- Batch subtract of color-marked solid objects from the merged result
- Persistent color-based identification of subtract objects
- Single undo step for the entire batch operation
- Automatic restoration of broken circles AND arcs on the result (native boolean operations destroy `ArcCurve` associations; the plugin rebuilds them as **native circles/arcs** — `ArcCurve` with center inference — using the Re-Cercle method, and welds them into single-click selectable curves when a native rebuild is not possible)
- Configurable threshold to skip restoration on very large objects (performance)
- Configurable minimum segment count for arc detection (tradeoff between catching short arcs and avoiding false positives)

### Out of scope
- Custom boolean engine (removed in v2.0 — plugin relies entirely on native Pro methods)
- Individual union/subtract/split operations (available natively in SketchUp Pro)
- SketchUp Make / Free compatibility

## 3. Target Users

- Architects and designers working with complex multi-solid models in SketchUp Pro
- Users who frequently combine many solids into one (walls + openings, assemblies, molds)
- Users preparing models for 3D printing or volume calculation

## 4. Requirements

### 4.1 System Requirements

| Requirement | Value |
|-------------|-------|
| SketchUp version | Pro 2017 or later |
| Operating system | Windows / macOS (any OS supported by SketchUp) |
| Ruby API methods | `Group#union`, `Group#outer_shell`, `Group#subtract`, `Group#manifold?` |
| Circle/arc restoration | Requires SketchUp 2020.1+ (`Entities#weld`, used by the weld fallback). On older versions, Phase 3 is silently skipped and the Set Repair Options command is hidden. |

### 4.2 Functional Requirements

#### FR-01: Combine All (Union)

| Field | Description |
|-------|-------------|
| **Input** | Selection of 2+ solid groups/components |
| **Precondition** | At least one solid must NOT have the subtract color |
| **Process** | 1. Separate selection into base solids and tool solids by subtract color. 2. Sequentially union all base solids using `Group#union`. 3. Sequentially subtract all tool solids using `Group#subtract`. |
| **Output** | A single solid group/component containing the result |
| **Undo** | Entire operation reverts with a single Ctrl+Z |
| **Error handling** | If any step fails, abort and revert; show error message with step number |

#### FR-02: Combine All (Shell)

| Field | Description |
|-------|-------------|
| **Input** | Selection of 2+ solid groups/components |
| **Precondition** | At least one solid must NOT have the subtract color |
| **Process** | Same as FR-01 but Phase 1 uses `Group#outer_shell` instead of `Group#union` |
| **Output** | A single solid group/component (outer envelope only) |
| **Undo** | Entire operation reverts with a single Ctrl+Z |
| **Error handling** | Same as FR-01 |

#### FR-03: Set Subtract Color

| Field | Description |
|-------|-------------|
| **Input** | Selection containing at least one group/component with a material applied |
| **Process** | Read the material color from the first matching entity; persist RGB values to SketchUp registry |
| **Output** | Confirmation message showing the registered RGB color |
| **Persistence** | Color is stored in SketchUp registry under `SolidBatch` namespace; survives application restart |
| **Default** | Red (255, 0, 0) if no color has been set |

#### FR-04: Set Repair Options

| Field | Description |
|-------|-------------|
| **Input** | None (no selection required) |
| **Process** | Open a `UI.inputbox` with three fields: `Auto-repair circles on large objects` (Yes/No), `Large object threshold (edges)` (integer), `Min segments for arc detection` (integer ≥ 3). Persist all three values to the SketchUp registry. |
| **Output** | Confirmation messagebox listing all three saved values + brief explanation of the low/high tradeoff for min arc segments |
| **Persistence** | Stored under `SolidBatch/auto_repair_large` (string Yes/No), `SolidBatch/large_threshold` (integer), `SolidBatch/min_arc_segments` (integer) |
| **Defaults** | `Yes`, `10000` edges, `6` segments (a value already saved in the registry takes precedence) |

#### FR-05: Automatic Circle AND Arc Restoration (Phase 3 of Combine All)

| Field | Description |
|-------|-------------|
| **Input** | The solid resulting from phases 1 and 2 of Combine All |
| **Precondition** | `result.valid?` |
| **Process** | 1. Count edges in the result (`CircleRestore.count_edges`). 2. If `edge_count <= threshold` OR `auto_repair_large == 'Yes'` → run `CircleRestore.restore_in_solid(result, min_arc_segments: <user_setting>)` (see Algorithm). 3. Otherwise → show a modal messagebox explaining that the repair was skipped and how to enable it. |
| **Output** | Hash `{native: N, welded: M, unwelded: K, reasons: {reason => n}}`. Circles and arcs rebuilt as native `Sketchup::ArcCurve` (center inference, radius and segments in Entity Info), or welded into a `Sketchup::Curve` (fallback), OR modal messagebox if skipped. Summary in the Ruby Console (with the weld reasons) and in the status bar. |
| **Algorithm** | Re-Cercle v2.0.0 method, copied into the plugin (`solid_batch/circle_restore/`, no dependency on Re-Cercle). (1) **Detection** on every edge of the result (nested groups/components included): chains of equal segments whose corners lie on one circle and turn by the same angle (± 1 %), segments split by extra vertices merged; closed chain ≥ 6 segments = circle, open chain ≥ `min_arc_segments` = arc; tolerance `max(0.001", 0.5 % × r)`; intact native circles and soft/hidden rings ignored. (2) **Classification** of each chain, detected again just before its rebuild: `:native` (nothing to do), `:planar` (all faces touching it in its plane → erase + `add_arc` with the same center, radius, segment count and phase + `find_faces` + face properties restored by probe point), `:volume` (end of a straight cylinder or truncated cone: hole, pin → wall erased, circle redrawn with `add_arc`, `Face#pushpull` to the other end, cone scaled, wall/caps properties restored: both ends become native), `:weld` (anything else → `Entities#weld`, reason logged). Lines attached to a circle split it into native arcs. (3) **Check** after each native rebuild: one `ArcCurve` per piece with the expected segment count; otherwise an exception aborts Phase 3. |
| **Constants** | `Detector::MIN_CIRCLE = 6`, `Detector::MIN_ARC = 3` (floor), `DEFAULT_MIN_ARC_SEGMENTS = 6` (configurable), `BASE_TOL = 0.001"`, `REL_TOL = 0.5 %`, `STEP_TOL = 1 %`, `MAX_STEP = 60°` |
| **Undo** | Phase 3 chained to the single undo of phases 1/2 via transparent operation |
| **Failure** | Exception during Phase 3 → only Phase 3 is aborted: the boolean result is kept, its circles stay as they were, a messagebox explains it |
| **Limitations** | Recreated faces (hole wall, caps, host face) keep material, tag and orientation but lose their texture position and attributes; entity IDs change. A regular polygon of 6+ sides (hexagon…) is indistinguishable from a circle. Stay welded (not native): arcs of a rounded edge (fillet), circle on a curved surface, cylinder cut by an edge, intersecting or stacked holes, oblique cylinder, triangulated face, line attached to a cylinder circle. |

#### FR-06: Solid Validation

| Field | Description |
|-------|-------------|
| **Input** | Current selection |
| **Process** | Filter entities to Groups and ComponentInstances that pass `manifold?` check |
| **Output** | Array of valid solids, or error message if fewer than required minimum |

### 4.3 Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NFR-01 | No custom boolean engine — rely exclusively on native SketchUp Pro methods |
| NFR-02 | Single undo step for all batch operations |
| NFR-03 | Subtract color persists across sessions via SketchUp registry |
| NFR-04 | Console logging (`puts`) for each operation step for debugging |
| NFR-05 | Graceful error handling with abort + revert on failure |
| NFR-06 | Status bar progress display during batch operations (`Solid Batch — Subtract 7/13 (54%)`) |
| NFR-07 | Transparent operations: each boolean step has its own start/commit (fast small deltas) chained via `transparent = true` for single undo |
| NFR-08 | Circle and arc restoration applied only at the end (Phase 3), never on intermediate steps — for performance and reliability |
| NFR-09 | The `large_threshold`, `auto_repair_large` and `min_arc_segments` settings persist in the SketchUp registry |
| NFR-10 | Each chain is detected again just before its rebuild (rebuilding a cylinder also rebuilds its other end); each native rebuild is checked |
| NFR-11 | Self-contained plugin: the circle engine is a copy of Re-Cercle v2.0.0 under `SolidBatch::CircleRestore`, no dependency on another plugin or shared library |

## 5. Architecture

### 5.1 File Structure

```
solid_batch.rb                # Entry point — extension registration
solid_batch/
  version.rb                  # VERSION constant
  main.rb                     # Menu, toolbar, commands, business logic
  circle_restore.rb           # CircleRestore module — restoration entry point (Phase 3)
  circle_restore/             # Copy of the Re-Cercle v2.0.0 engine
    detector.rb               # Chain detection and classification
    rebuilder.rb              # Planar native rebuild, weld fallback
    volume.rb                 # Push/Pull native rebuild of cylinders and cones
  icons/
    combine_pro_union_16.png  # Toolbar icons (16px and 24px)
    combine_pro_union_24.png
    combine_pro_shell_16.png
    combine_pro_shell_24.png
    setcolor_16.png
    setcolor_24.png
    repair_circles_16.png     # New Set Repair Options icon
    repair_circles_24.png
```

### 5.2 Module Structure

```
SolidBatch                  # Top-level namespace
  PLUGIN_DIR                  # Plugin directory path
  PLUGIN_NAME                 # "Solid Batch"
  VERSION                     # "2.3.0"

  # Color management
  subtract_color()            # Read persisted color
  save_subtract_color(color)  # Write color to registry
  color_match?(c1, c2)        # Compare two colors by RGB
  is_subtract_solid?(entity)  # Check if entity has subtract color

  # Circle and arc repair options
  auto_repair_large()         # Read persisted Yes/No toggle
  save_auto_repair_large(v)   # Write toggle to registry
  large_threshold()           # Read persisted edge threshold
  save_large_threshold(v)     # Write threshold to registry
  min_arc_segments()          # Read persisted min arc segments
  save_min_arc_segments(v)    # Write min arc segments to registry

  # Validation
  get_solids(min_count)        # Filter selection to valid solids

  # Commands
  do_combine_all_pro(mode)    # Batch union/shell + subtract + circle & arc restore
  do_set_subtract_color()     # Register subtract color
  do_set_repair_options()     # Configure auto-repair + threshold + min arc segments

SolidBatch::CircleRestore   # Circle and arc restoration module
  DEFAULT_MIN_ARC_SEGMENTS    # 6 (arcs, configurable)
  count_edges(solid)          # Recursive edge count
  restore_in_solid(solid, min_arc_segments:)  # Returns {native:, welded:, unwelded:, reasons:}
  summary(result, reasons:)   # One-line report (console, status bar)
  restore_chain(...)          # Redetect, classify, rebuild one chain (Re-Cercle restore_chain)
  check_planar / check_volume # Post-rebuild checks (raise on failure)
  Detector                    # Copy of Re-Cercle detector.rb (chains, analyse)
  Rebuilder                   # Copy of Re-Cercle rebuilder.rb (planar, weld)
  Volume                      # Copy of Re-Cercle volume.rb (detect, rebuild)
```

### 5.3 Operation Flow

```
User clicks "Combine All (Union)" or "(Shell)"
  |
  v
get_solids(2) — validate selection
  |
  v
Check native method availability (respond_to?)
  |
  v
Separate solids by subtract color
  |
  v
Phase 1: sequential union/outer_shell of base solids
  |   For each step:
  |     start_operation(transparent = !first_op)
  |     base[0].union(base[1]) -> commit
  |     start_operation(transparent = true)
  |     result.union(base[2]) -> commit -> ...
  |
  +---> Phase 2: sequential subtract of tool solids
  |   For each step:
  |     start_operation(transparent = true)
  |     tool[0].subtract(result) -> commit
  |     tool[1].subtract(result) -> commit -> ...
  |
  +---> Status bar: "Solid Batch — Subtract 7/13 (54%)"
  |
  +---> Phase 3: circle AND arc restoration on the final result
  |   edge_count = CircleRestore.count_edges(result)
  |   if edge_count <= threshold OR auto_repair_large == 'Yes':
  |     start_operation(transparent = true)
  |     CircleRestore.restore_in_solid(result, min_arc_segments: ...)
  |       Detector.find_chains (circles ≥ 6, arcs ≥ min_arc_segments segments)
  |       for each chain: redetect -> analyse ->
  |         :planar -> Rebuilder.planar (native)   -> check
  |         :volume -> Volume.rebuild (Push/Pull)  -> check
  |         :weld   -> Rebuilder.weld (Curve, reason logged)
  |     -> commit   (exception -> abort Phase 3 only, boolean result kept)
  |   else:
  |     UI.messagebox modal "Repair skipped"
  |
  v
All steps chained via transparent operations → single Ctrl+Z
  |
  v
Select result
```

### 5.4 Native API Usage

The plugin uses the following SketchUp Pro Ruby API methods:

| Method | Receiver | Argument | Returns | Side effect |
|--------|----------|----------|---------|-------------|
| `union(other)` | Solid A | Solid B | Merged solid | Erases B |
| `outer_shell(other)` | Solid A | Solid B | Shell solid | Erases B |
| `subtract(base)` | Tool (erased) | Base (kept) | Modified base | Erases tool |
| `manifold?` | Group/Component | — | Boolean | None |

**Important:** For `subtract`, the receiver is the tool (which gets erased) and the argument is the base (which is modified and returned). This is the reverse of what the method name might suggest.

## 6. Data Persistence

| Data | Storage | Key | Default |
|------|---------|-----|---------|
| Subtract color (R) | SketchUp registry | `SolidBatch/subtract_color_r` | 255 |
| Subtract color (G) | SketchUp registry | `SolidBatch/subtract_color_g` | 0 |
| Subtract color (B) | SketchUp registry | `SolidBatch/subtract_color_b` | 0 |
| Auto-repair circles on large objects | SketchUp registry | `SolidBatch/auto_repair_large` | `Yes` |
| "Large object" threshold in edges | SketchUp registry | `SolidBatch/large_threshold` | `10000` |
| Min segments for arc detection | SketchUp registry | `SolidBatch/min_arc_segments` | `6` |

## 7. User Interface

### 7.1 Menu

Located at **Extensions > Solid Batch**:
1. Combine All (Union)
2. Combine All (Shell)
3. *(separator)*
4. Set Subtract Color
5. Set Repair Options

### 7.2 Toolbar

Named "Solid Batch", contains 4 buttons with 16px and 24px icon variants:
1. Combine All (Union)
2. Combine All (Shell)
3. Set Subtract Color
4. Set Repair Options

### 7.3 Messages

All user-facing messages use `UI.messagebox` with `MB_OK`. Error messages include the step number where failure occurred.

## 8. Error Handling

| Scenario | Behavior |
|----------|----------|
| Fewer than 2 solids selected | Show count message, abort |
| SketchUp not Pro (method missing) | Show "requires SketchUp Pro" message, abort |
| All solids have subtract color | Show "no base objects" message, abort |
| Boolean step fails (nil/invalid result) | Abort operation (revert all changes), show step number |
| Circle/arc restoration fails (Phase 3) | Abort Phase 3 only (boolean result kept, circles left as they were), log backtrace, show message |
| Unexpected exception | Abort operation, log backtrace (first 10 lines), show error message |

## 9. Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-04-03 | Initial release — custom boolean engine (union, subtract, split) |
| 2.0.0 | 2026-04-04 | Removed custom engine. Added Combine All (Union/Shell) using native Pro methods. Added Set Subtract Color. Removed Union, Subtract, Split individual operations. Transparent operations for fast commits + single undo. Status bar progress display. |
| 2.1.0 | 2026-04-11 | Added Phase 3: automatic restoration of broken circles on the result (`CircleRestore` module adapted from Re-Cercle). Added `Set Repair Options` command to configure threshold and auto-repair toggle. Persistence of new options. New `repair_circles_*.png` icon. |
| 2.2.0 | 2026-04-11 | Phase 3 extended: automatic restoration of **arcs** in addition to circles via `find_arcs_by_geometry` + `open_chain?`. New `Min segments for arc detection` parameter configurable in `Set Repair Options` (default 8). `restore_in_solid` now returns `{circles:, arcs:, total:}`. Stage 1b inserted between circles and pre-existing curve fragments. |
| 2.2.1 | 2026-04-12 | Backward compatibility with SketchUp Pro 2017+. Replaced Ruby 2.3 safe navigation (`&.`) with classic nil checks for Ruby 2.2 compatibility. Added `respond_to?(:weld)` guard in `CircleRestore` — Phase 3 silently skipped on SketchUp < 2020.1. Set Repair Options menu/toolbar hidden on versions < 2020.1. |
| 2.3.0 | 2026-10-11 | Phase 3 rebuilt on the Re-Cercle v2.0.0 method, copied into the plugin (`solid_batch/circle_restore/`, no dependency): broken circles and arcs become **native** `ArcCurve` (center inference) — planar rebuild, Push/Pull rebuild of cylinders and truncated cones (holes, pins) — with weld only as a fallback (reason logged). Detection by chains of equal segments (tolerance `max(0.001", 0.5 % r)`), circles ≥ 6 segments, default `min_arc_segments` 8 → 6. Post-rebuild checks; a Phase 3 failure aborts Phase 3 only (boolean result kept). `restore_in_solid` returns `{native:, welded:, unwelded:, reasons:}`; summary in console and status bar. |
