require_relative 'version'
require_relative 'boolean_ops'

module DRO_SolidOps
  unless @loaded
    submenu = UI.menu('Extensions').add_submenu(PLUGIN_NAME)

    submenu.add_item('Union') { self.do_union }
    submenu.add_item('Subtract') { self.do_subtract }
    submenu.add_item('Split') { self.do_split }

    toolbar = UI::Toolbar.new(PLUGIN_NAME)

    icons_dir = File.join(PLUGIN_DIR, 'dro_solid_ops', 'icons')

    cmd_union = UI::Command.new('Union') { self.do_union }
    cmd_union.tooltip = 'Union — merge solids, preserve internal voids'
    cmd_union.small_icon = File.join(icons_dir, 'union_16.png')
    cmd_union.large_icon = File.join(icons_dir, 'union_24.png')
    toolbar.add_item(cmd_union)

    cmd_subtract = UI::Command.new('Subtract') { self.do_subtract }
    cmd_subtract.tooltip = 'Subtract — click base, then tools to subtract'
    cmd_subtract.small_icon = File.join(icons_dir, 'subtract_16.png')
    cmd_subtract.large_icon = File.join(icons_dir, 'subtract_24.png')
    toolbar.add_item(cmd_subtract)

    cmd_split = UI::Command.new('Split') { self.do_split }
    cmd_split.tooltip = 'Split — divide solids at intersections'
    cmd_split.small_icon = File.join(icons_dir, 'split_16.png')
    cmd_split.large_icon = File.join(icons_dir, 'split_24.png')
    toolbar.add_item(cmd_split)

    toolbar.show
    @loaded = true
  end

  # -------------------------------------------------------------------
  # Validate selection: return array of manifold solids, or nil
  # -------------------------------------------------------------------
  def self.get_solids(min_count = 2)
    model = Sketchup.active_model
    sel = model.selection.to_a
    solids = sel.select { |e|
      (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) &&
        e.manifold?
    }

    if solids.length < min_count
      UI.messagebox(
        "Select at least #{min_count} solid group(s) or component(s).\n" \
        "Currently #{solids.length} valid solid(s) in selection.",
        MB_OK
      )
      return nil
    end
    solids
  end

  # -------------------------------------------------------------------
  # Actions
  # -------------------------------------------------------------------
  def self.do_union
    solids = get_solids(2)
    return unless solids
    result = BooleanOps.union(solids, Sketchup.active_model)
    Sketchup.active_model.selection.clear
    Sketchup.active_model.selection.add(result) if result&.valid?
  end

  def self.do_subtract
    Sketchup.active_model.select_tool(SubtractTool.new)
  end

  # Multi-subtract tool:
  # Click 1 = base solid (kept). Then click tools one by one,
  # each is subtracted from the base. Escape or switch tool to stop.
  class SubtractTool
    def activate
      @base = nil
      Sketchup.status_text = 'Subtract: click the BASE solid (the one to keep)'
    end

    def pick_solid(x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      path = ph.path_at(0)
      return nil unless path
      # Find the top-level group/component in the pick path
      path.each do |e|
        return e if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      end
      nil
    end

    def onLButtonDown(_flags, x, y, view)
      solid = pick_solid(x, y, view)
      return unless solid

      if @base.nil?
        # Step 1: select the base
        @base = solid
        view.model.selection.clear
        view.model.selection.add(@base)
        Sketchup.status_text = 'Subtract: click solids to subtract (Escape to finish)'
      else
        # Step 2+: subtract this solid from the base
        return if solid == @base
        Sketchup.status_text = 'Subtracting...'
        result = BooleanOps.subtract(@base, solid, view.model)
        if result&.valid?
          @base = result
          view.model.selection.clear
          view.model.selection.add(@base)
          Sketchup.status_text = 'Subtract: click next solid to subtract (Escape to finish)'
        else
          Sketchup.status_text = 'Subtract failed — click another solid or Escape'
        end
      end
    end

    def deactivate(view)
      Sketchup.status_text = ''
    end

    def onCancel(_reason, view)
      view.model.select_tool(nil)
    end
  end

  def self.do_split
    solids = get_solids(2)
    return unless solids
    if solids.length != 2
      UI.messagebox("Split requires exactly 2 solids.", MB_OK)
      return
    end
    results = BooleanOps.split(solids[0], solids[1], Sketchup.active_model)
    if results && !results.empty?
      Sketchup.active_model.selection.clear
      results.each { |r| Sketchup.active_model.selection.add(r) if r&.valid? }
    end
  end
end
