# Solid Batch — Functional Specification Document

**Version:** 2.1.0
**Date:** 2026-04-11
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
- Automatic restoration of broken circles on the result (native boolean operations destroy `ArcCurve` associations; the plugin welds matching segments back into single-click selectable circles)
- Configurable threshold to skip restoration on very large objects (performance)

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
| **Process** | Open a `UI.inputbox` with two fields: `Auto-repair circles on large objects` (Yes/No) and `Large object threshold (edges)` (integer). Persist both values to the SketchUp registry. |
| **Output** | Confirmation messagebox listing both saved values |
| **Persistence** | Stored under `SolidBatch/auto_repair_large` (string Yes/No) and `SolidBatch/large_threshold` (integer) |
| **Defaults** | `Yes` and `10000` edges |

#### FR-05: Automatic Circle Restoration (Phase 3 of Combine All)

| Field | Description |
|-------|-------------|
| **Input** | The solid resulting from phases 1 and 2 of Combine All |
| **Precondition** | `result.valid?` |
| **Process** | 1. Count edges in the result (`CircleRestore.count_edges`). 2. If `edge_count <= threshold` OR `auto_repair_large == 'Yes'` → run `CircleRestore.restore_in_solid` which detects circles via circumcircle geometry and `entities.weld()` segments back into a Curve. 3. Otherwise → show a modal messagebox explaining that the repair was skipped and how to enable it. |
| **Output** | Circles restored as `Sketchup::Curve` selectable in one click, OR modal messagebox if skipped |
| **Algorithm** | Adapted from the Re-Cercle plugin (Claude Code, 2026) — 2-stage detection: (1) loose edges grouped by circumcircle then welded, (2) curve fragments grouped by center/radius/normal then welded |
| **Constants** | `MIN_SEGMENTS = 8`, `TOLERANCE = 0.1` (radius-adaptive) |
| **Undo** | Phase 3 chained to the single undo of phases 1/2 via transparent operation |

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
| NFR-08 | Circle restoration applied only at the end (Phase 3), never on intermediate steps — for performance and reliability |
| NFR-09 | The `large_threshold` and `auto_repair_large` toggle persist in the SketchUp registry |

## 5. Architecture

### 5.1 File Structure

```
solid_batch.rb                # Entry point — extension registration
solid_batch/
  version.rb                  # VERSION constant
  main.rb                     # Menu, toolbar, commands, business logic
  circle_restore.rb           # CircleRestore module — circle restoration
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
  VERSION                     # "2.1.0"

  # Color management
  subtract_color()            # Read persisted color
  save_subtract_color(color)  # Write color to registry
  color_match?(c1, c2)        # Compare two colors by RGB
  is_subtract_solid?(entity)  # Check if entity has subtract color

  # Circle repair options
  auto_repair_large()         # Read persisted Yes/No toggle
  save_auto_repair_large(v)   # Write toggle to registry
  large_threshold()           # Read persisted edge threshold
  save_large_threshold(v)     # Write threshold to registry

  # Validation
  get_solids(min_count)        # Filter selection to valid solids

  # Commands
  do_combine_all_pro(mode)    # Batch union/shell + subtract + circle restore
  do_set_subtract_color()     # Register subtract color
  do_set_repair_options()     # Configure auto-repair + threshold

SolidBatch::CircleRestore   # Circle restoration module
  TOLERANCE                   # 0.1
  MIN_SEGMENTS                # 8
  count_edges(solid)          # Recursive edge count
  restore_in_solid(solid)     # 2-stage restoration, returns # of welded circles
  # + internal helpers: circumcircle, closed_chain?, group_by_circle_geometry, etc.
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
  +---> Phase 3: circle restoration on the final result
  |   edge_count = CircleRestore.count_edges(result)
  |   if edge_count <= threshold OR auto_repair_large == 'Yes':
  |     start_operation(transparent = true)
  |     CircleRestore.restore_in_solid(result) -> commit
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
| Unexpected exception | Abort operation, log backtrace (first 10 lines), show error message |

## 9. Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-04-03 | Initial release — custom boolean engine (union, subtract, split) |
| 2.0.0 | 2026-04-04 | Removed custom engine. Added Combine All (Union/Shell) using native Pro methods. Added Set Subtract Color. Removed Union, Subtract, Split individual operations. Transparent operations for fast commits + single undo. Status bar progress display. |
| 2.1.0 | 2026-04-11 | Added Phase 3: automatic restoration of broken circles on the result (`CircleRestore` module adapted from Re-Cercle). Added `Set Repair Options` command to configure threshold and auto-repair toggle. Persistence of new options. New `repair_circles_*.png` icon. |
