# Solid Batch — User Manual

## Overview

Solid Batch is a SketchUp Pro plugin that performs batch boolean operations on multiple solids in a single click. It uses SketchUp Pro's native boolean engine for reliable results.

The plugin provides three commands accessible via the **Extensions > Solid Batch** menu and the **Solid Batch** toolbar.

## Requirements

- **SketchUp Pro** 2017 or later
- All objects must be **solid** groups or components (manifold geometry — every edge borders exactly 2 faces)

## Commands

### Combine All PRO (Union)

Merges all selected solids into one, using native `union` for base solids and native `subtract` for color-marked tool solids.

**Behavior:**
1. Separates the selection into two sets based on the subtract color:
   - **Base solids** — all solids that do NOT have the subtract color
   - **Tool solids** — all solids that DO have the subtract color
2. **Phase 1 (Union):** Merges all base solids into one using sequential `union` calls. If there is only one base solid, this phase is skipped.
3. **Phase 2 (Subtract):** Subtracts each tool solid from the merged base, one by one.
4. The entire operation is wrapped in a single undo step.

**When to use:** When you want to merge solids while preserving internal voids (e.g., merging walls that have window openings).

### Combine All PRO (Shell)

Same workflow as Combine All PRO (Union), but uses `outer_shell` instead of `union` in Phase 1.

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

## Workflow

### Basic Workflow

1. **Model your solids** — Create all the groups/components you want to combine. Make sure they are all valid solids (Entity Info should show "Solid Group" or "Solid Component").

2. **Paint the tools** — Apply a specific color (e.g., red) to all objects that should be subtracted from the final result.

3. **Register the subtract color** — Select one of the painted tool objects and click **Set Subtract Color**. You only need to do this once (the color is remembered).

4. **Select everything** — Select all the solids you want to process (both bases and tools).

5. **Run the operation** — Click **Combine All PRO (Union)** or **Combine All PRO (Shell)**.

6. **Result** — A single solid remains. If something went wrong, press **Ctrl+Z** to undo the entire operation.

### Example: Wall with Windows

1. Create a wall as a solid group
2. Create window opening shapes as solid groups
3. Paint the window shapes red
4. Set subtract color to red (if not already done)
5. Select the wall + all window shapes
6. Click **Combine All PRO (Union)**
7. Result: wall with window openings cut out

### Example: Merging Multiple Rooms

1. Create each room as a solid group (walls, floor, ceiling)
2. No objects need the subtract color
3. Select all room groups
4. Click **Combine All PRO (Shell)** for a clean outer envelope
5. Result: one solid representing the entire building shell

## Toolbar Icons

| Icon | Command | Description |
|------|---------|-------------|
| Combine PRO Union | Combine All PRO (Union) | Native union + subtract |
| Combine PRO Shell | Combine All PRO (Shell) | Native outer shell + subtract |
| Set Color | Set Subtract Color | Pick color from selection |

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

### Undo
All Combine All operations are wrapped in a single undo step. Press **Ctrl+Z** (Cmd+Z on Mac) to revert the entire operation.

## Tips

- **Check solids first:** Use SketchUp's Entity Info panel to verify each object is a valid solid before running operations.
- **Subtract color is global:** The subtract color applies to all models. Set it once and it persists.
- **Union vs Shell:** If you're not sure which to use, start with Union. It preserves more geometry, so you can always simplify later.
- **Order matters for subtract:** Tool solids are subtracted in selection order. If results are unexpected, try changing the selection order.
- **Back up your model:** Although Ctrl+Z works, save your model before large batch operations.
