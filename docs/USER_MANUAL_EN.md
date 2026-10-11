# Solid Batch — User Manual

## Overview

Solid Batch is a SketchUp Pro plugin that performs batch boolean operations on multiple solids in a single click. It uses SketchUp Pro's native boolean engine for reliable results.

The plugin provides four commands accessible via the **Extensions > Solid Batch** menu and the **Solid Batch** toolbar.

## Requirements

- **SketchUp Pro** 2017 or later
- All objects must be **solid** groups or components (manifold geometry — every edge borders exactly 2 faces)

### Compatibility by version

| SketchUp version | Available features |
|---|---|
| Pro 2017 – 2019 | Combine All (Union), Combine All (Shell), Set Subtract Color |
| Pro 2020.1+ | All of the above + automatic circle/arc restoration + Set Repair Options |

## Commands

### Combine All (Union)

Merges all selected solids into one, using native `union` for base solids and native `subtract` for color-marked tool solids.

**Behavior:**
1. Separates the selection into two sets based on the subtract color:
   - **Base solids** — all solids that do NOT have the subtract color
   - **Tool solids** — all solids that DO have the subtract color
2. **Phase 1 (Union):** Merges all base solids into one using sequential `union` calls. If there is only one base solid, this phase is skipped.
3. **Phase 2 (Subtract):** Subtracts each tool solid from the merged base, one by one.
4. **Phase 3 (Circle AND arc restoration):** Detects circles AND arcs broken by the native boolean operations and rebuilds them as **native SketchUp circles and arcs** (center inference, radius and segments in Entity Info). When a native rebuild is not possible, they are welded into a `Curve` selectable in a single click (see [What Phase 3 produces](#what-phase-3-produces)). This phase can be disabled for very large objects via **Set Repair Options**.
5. The entire operation is wrapped in a single undo step.

**When to use:** When you want to merge solids while preserving internal voids (e.g., merging walls that have window openings).

### Combine All (Shell)

Same workflow as Combine All (Union), but uses `outer_shell` instead of `union` in Phase 1.

**Difference with Union:**
- **Union** preserves internal geometry (voids, internal faces)
- **Outer Shell** removes all internal geometry and keeps only the outer surface

**When to use:** When you want a clean outer envelope without any internal faces (e.g., creating a simplified solid for volume calculation or 3D printing).

### Set Subtract Color

Registers a color to identify which solids should be subtracted during Combine All operations.

**How to use:**
1. Select a group or component that has a material/color applied to it
2. Click **Set Subtract Color**
3. The color is saved and persists across SketchUp sessions

**Default color:** Red (RGB 255, 0, 0)

### Set Repair Options

Configures the **Phase 3** behavior (automatic circle AND arc restoration) at the end of Combine All operations.

**Why it matters:** SketchUp Pro's native boolean operations break the `ArcCurve` association of both circles and arcs: a circle or an arc becomes a series of small individual segments (or a plain curve without center inference). Phase 3 detects them and rebuilds them as native circles and arcs. On very large objects (tens of thousands of edges), this can take several seconds; this option lets you skip it in that case.

**How to use:**
1. Click **Set Repair Options** (no selection required)
2. A dialog opens with three fields:
   - **Auto-repair circles on large objects** (Yes/No): if `Yes`, restoration always runs, even on large objects; if `No`, it is skipped above the threshold and a message warns you
   - **Large object threshold (edges)**: number of edges above which an object is considered "large"
   - **Min segments for arc detection**: minimum number of segments for a chain of edges to be considered an arc. Lower = catches shorter arcs but risks false positives. Higher = safer but may miss short arcs.
3. Click **OK** — values are remembered across sessions

**Defaults:** Auto-repair = `Yes`, Threshold = `10000` edges, Min arc segments = `6` (if you saved these options with an earlier version, your saved value is kept: check it in the dialog)

**Choosing `Min segments for arc detection`:**

An arc is only recognized when its segments have the same length and turn by the same angle (at most 60° each). Circles always need 6 segments or more. The default of `6` matches circles; some reference points:

| Arc type | Segments | Detected with threshold = 6? |
|----------|----------|------------------------------|
| 360° with 24 segments (refined native circle) | 24 | ✓ (circle) |
| 270° with 12 segments (default native arc) | 9 | ✓ |
| 180° with 12 segments | 6 | ✓ |
| 90° with 24 segments | 6 | ✓ |
| 90° with 12 segments | 3 | ✗ — lower threshold to 3 |

If you work with many short arcs, lower the threshold (minimum `3`). If equal-sided polygon fragments are turned into arcs, raise it.

**Phase 3 decision (summary):**

| Case | Action |
|------|--------|
| Result ≤ threshold | Restoration always runs |
| Result > threshold AND auto-repair = Yes | Restoration runs |
| Result > threshold AND auto-repair = No | Restoration skipped + modal message |

### What Phase 3 produces

| Case in the result | Result |
|--------------------|--------|
| Through hole, blind hole, pin (box ± cylinder), truncated cone | Both end circles become **native** (rebuilt with a Push/Pull) |
| Circle or arc lying on a flat face | **Native** circle or arc |
| Circle crossed by a line | **Native** arcs between the crossings |
| Arcs of a rounded edge (fillet), cylinder cut by an edge, intersecting or stacked holes, circle on a curved surface, oblique cylinder | **Welded** into one curve (one click selects it, no center inference) |
| Circles already native | Unchanged |

A summary is shown in the status bar and, with the reason of each weld, in the Ruby Console (**Window > Ruby Console**).

**Limitations:** the faces rebuilt around a repaired circle (hole wall, caps, host face) keep their material, tag and orientation, but lose their texture position and attributes. A regular polygon of 6 sides or more (hexagon…) cannot be told apart from a circle and becomes one.

## Workflow

### Basic Workflow

1. **Model your solids** — Create all the groups/components you want to combine. Make sure they are all valid solids (Entity Info should show "Solid Group" or "Solid Component").

2. **Paint the tools** — Apply a specific color (e.g., red) to all objects that should be subtracted from the final result.

3. **Register the subtract color** — Select one of the painted tool objects and click **Set Subtract Color**. You only need to do this once (the color is remembered).

4. **Select everything** — Select all the solids you want to process (both bases and tools).

5. **Run the operation** — Click **Combine All (Union)** or **Combine All (Shell)**.

6. **Result** — A single solid remains. If something went wrong, press **Ctrl+Z** to undo the entire operation.

### Example: Wall with Windows

1. Create a wall as a solid group
2. Create window opening shapes as solid groups
3. Paint the window shapes red
4. Set subtract color to red (if not already done)
5. Select the wall + all window shapes
6. Click **Combine All (Union)**
7. Result: wall with window openings cut out

### Example: Merging Multiple Rooms

1. Create each room as a solid group (walls, floor, ceiling)
2. No objects need the subtract color
3. Select all room groups
4. Click **Combine All (Shell)** for a clean outer envelope
5. Result: one solid representing the entire building shell

## Toolbar Icons

| Icon | Command | Description |
|------|---------|-------------|
| Combine Union | Combine All (Union) | Native union + subtract + circle & arc restoration |
| Combine Shell | Combine All (Shell) | Native outer shell + subtract + circle & arc restoration |
| Set Color | Set Subtract Color | Pick color from selection |
| Circle ✓ | Set Repair Options | Configure auto-repair, edge threshold, min arc segments |

## Troubleshooting

### "This function requires SketchUp Pro"
You are using SketchUp Make or SketchUp Free. The native boolean methods are only available in SketchUp Pro.

### "Select at least 2 solid group(s) or component(s)"
Your selection contains fewer than 2 valid solids. Check that:
- You have selected at least 2 objects
- Each object is a Group or ComponentInstance
- Each object is a valid solid (check Entity Info — it should say "Solid")

### "No base objects found"
All selected objects have the subtract color. At least one object must have a different color to serve as the base.

### Operation fails at a specific step
One of the boolean operations failed. This usually means:
- Two solids don't intersect (nothing to union/subtract)
- The geometry is too complex or has coplanar faces
- Try reordering or simplifying the problematic solids

### "Circle and arc restoration failed"
A circle could not be rebuilt. Only the restoration is undone: the Combine All result is kept and its circles stay as they were. The Ruby Console shows the details.

### Progress
During batch operations, the status bar at the bottom of the SketchUp window shows real-time progress: `Solid Batch — Subtract 7/13 (54%)`. A final message confirms completion, with the circle restoration summary: `Solid Batch — Done (13 operations) — 4 circle(s)/arc(s) rebuilt as native circles`.

### Undo
All Combine All operations are wrapped in a single undo step. Press **Ctrl+Z** (Cmd+Z on Mac) to revert the entire operation.

## Tips

- **Check solids first:** Use SketchUp's Entity Info panel to verify each object is a valid solid before running operations.
- **Subtract color is global:** The subtract color applies to all models. Set it once and it persists.
- **Union vs Shell:** If you're not sure which to use, start with Union. It preserves more geometry, so you can always simplify later.
- **Order matters for subtract:** Tool solids are subtracted in selection order. If results are unexpected, try changing the selection order.
- **Back up your model:** Although Ctrl+Z works, save your model before large batch operations.
