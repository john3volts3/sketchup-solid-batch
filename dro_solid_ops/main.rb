require_relative 'version'
require_relative 'boolean_ops'

module DRO_SolidOps
  unless @loaded
    submenu = UI.menu('Extensions').add_submenu(PLUGIN_NAME)

    submenu.add_item('Union') { self.do_union }
    submenu.add_item('Subtract') { self.do_subtract }
    submenu.add_item('Split') { self.do_split }
    submenu.add_separator
    submenu.add_item('Combine All') { self.do_combine_all }
    submenu.add_item('Combine All PRO (Union)') { self.do_combine_all_pro(:union) }
    submenu.add_item('Combine All PRO (Shell)') { self.do_combine_all_pro(:outer_shell) }
    submenu.add_separator
    submenu.add_item('Set Subtract Color') { self.do_set_subtract_color }

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

    cmd_combine = UI::Command.new('Combine All') { self.do_combine_all }
    cmd_combine.tooltip = 'Combine All — union + subtract by color'
    cmd_combine.small_icon = File.join(icons_dir, 'combine_16.png')
    cmd_combine.large_icon = File.join(icons_dir, 'combine_24.png')
    toolbar.add_item(cmd_combine)

    cmd_combine_pro_union = UI::Command.new('Combine All PRO (Union)') { self.do_combine_all_pro(:union) }
    cmd_combine_pro_union.tooltip = 'Combine All PRO (Union) — native union + subtract'
    cmd_combine_pro_union.small_icon = File.join(icons_dir, 'combine_pro_union_16.png')
    cmd_combine_pro_union.large_icon = File.join(icons_dir, 'combine_pro_union_24.png')
    toolbar.add_item(cmd_combine_pro_union)

    cmd_combine_pro_shell = UI::Command.new('Combine All PRO (Shell)') { self.do_combine_all_pro(:outer_shell) }
    cmd_combine_pro_shell.tooltip = 'Combine All PRO (Shell) — native outer shell + subtract'
    cmd_combine_pro_shell.small_icon = File.join(icons_dir, 'combine_pro_shell_16.png')
    cmd_combine_pro_shell.large_icon = File.join(icons_dir, 'combine_pro_shell_24.png')
    toolbar.add_item(cmd_combine_pro_shell)

    cmd_setcolor = UI::Command.new('Set Subtract Color') { self.do_set_subtract_color }
    cmd_setcolor.tooltip = 'Set Subtract Color — pick color from selection'
    cmd_setcolor.small_icon = File.join(icons_dir, 'setcolor_16.png')
    cmd_setcolor.large_icon = File.join(icons_dir, 'setcolor_24.png')
    toolbar.add_item(cmd_setcolor)

    toolbar.show
    @loaded = true
  end

  # -------------------------------------------------------------------
  # Subtract color management (persisted across sessions)
  # -------------------------------------------------------------------
  DEFAULT_SUBTRACT_COLOR = [255, 0, 0].freeze

  def self.subtract_color
    r = Sketchup.read_default('DRO_SolidOps', 'subtract_color_r', DEFAULT_SUBTRACT_COLOR[0]).to_i
    g = Sketchup.read_default('DRO_SolidOps', 'subtract_color_g', DEFAULT_SUBTRACT_COLOR[1]).to_i
    b = Sketchup.read_default('DRO_SolidOps', 'subtract_color_b', DEFAULT_SUBTRACT_COLOR[2]).to_i
    Sketchup::Color.new(r, g, b)
  end

  def self.save_subtract_color(color)
    Sketchup.write_default('DRO_SolidOps', 'subtract_color_r', color.red)
    Sketchup.write_default('DRO_SolidOps', 'subtract_color_g', color.green)
    Sketchup.write_default('DRO_SolidOps', 'subtract_color_b', color.blue)
  end

  def self.color_match?(c1, c2)
    c1.red == c2.red && c1.green == c2.green && c1.blue == c2.blue
  end

  def self.is_subtract_solid?(entity)
    return false unless entity.material
    color_match?(entity.material.color, subtract_color)
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

  def self.do_set_subtract_color
    model = Sketchup.active_model
    sel = model.selection.to_a
    entity = sel.find { |e|
      (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && e.material
    }

    unless entity
      UI.messagebox(
        "Select a group or component with a material/color applied.\n" \
        "That color will be used to identify objects to subtract in Combine All.",
        MB_OK
      )
      return
    end

    color = entity.material.color
    save_subtract_color(color)
    UI.messagebox(
      "Subtract color set to RGB(#{color.red}, #{color.green}, #{color.blue}).\n" \
      "Objects with this color will be subtracted when using Combine All.",
      MB_OK
    )
  end

  def self.do_combine_all
    solids = get_solids(2)
    return unless solids

    sub_color = subtract_color
    union_solids = solids.reject { |s| is_subtract_solid?(s) }
    subtract_solids = solids.select { |s| is_subtract_solid?(s) }

    puts "[Solid Ops] Combine All: #{union_solids.length} union, #{subtract_solids.length} subtract"

    if union_solids.empty?
      UI.messagebox(
        "No base objects found (all selected objects have the subtract color).\n" \
        "At least one object must NOT have the subtract color RGB(#{sub_color.red}, #{sub_color.green}, #{sub_color.blue}).",
        MB_OK
      )
      return
    end

    model = Sketchup.active_model
    model.start_operation('Solid Ops — Combine All', true)
    begin
      # Phase 1: Union all non-subtract solids
      if union_solids.length >= 2
        puts "[Solid Ops]   Phase 1: Union #{union_solids.length} solids..."
        result = BooleanOps.union(union_solids, model, wrap_operation: false)
        unless result&.valid?
          model.abort_operation
          UI.messagebox("Combine All failed: union step produced no valid result.", MB_OK)
          return
        end
      else
        result = union_solids[0]
        puts "[Solid Ops]   Phase 1: Single base solid, skipping union"
      end

      # Phase 2: Subtract all subtract-colored solids
      if subtract_solids.any?
        puts "[Solid Ops]   Phase 2: Subtract #{subtract_solids.length} solids..."
        subtract_solids.each_with_index do |tool, i|
          puts "[Solid Ops]     subtract step #{i + 1}/#{subtract_solids.length}..."
          result = BooleanOps.subtract(result, tool, model, wrap_operation: false)
          unless result&.valid?
            model.abort_operation
            UI.messagebox("Combine All failed at subtract step #{i + 1}.", MB_OK)
            return
          end
        end
      end

      model.commit_operation
      model.selection.clear
      model.selection.add(result) if result&.valid?
      puts "[Solid Ops] Combine All done."
    rescue => e
      model.abort_operation
      puts "[Solid Ops] Combine All error: #{e.message}"
      e.backtrace.first(10).each { |line| puts "  #{line}" }
      UI.messagebox("Combine All error: #{e.message}", MB_OK)
    end
  end

  def self.do_combine_all_pro(mode)
    solids = get_solids(2)
    return unless solids

    # Check if native Pro methods are available
    unless solids[0].respond_to?(mode)
      UI.messagebox(
        "This function requires SketchUp Pro.\n" \
        "The native '#{mode}' method is not available in your version.",
        MB_OK
      )
      return
    end

    sub_color = subtract_color
    union_solids = solids.reject { |s| is_subtract_solid?(s) }
    subtract_solids = solids.select { |s| is_subtract_solid?(s) }

    mode_label = mode == :outer_shell ? 'Outer Shell' : 'Union'
    puts "[Solid Ops] Combine All PRO (#{mode_label}): #{union_solids.length} union, #{subtract_solids.length} subtract"

    if union_solids.empty?
      UI.messagebox(
        "No base objects found (all selected objects have the subtract color).\n" \
        "At least one object must NOT have the subtract color RGB(#{sub_color.red}, #{sub_color.green}, #{sub_color.blue}).",
        MB_OK
      )
      return
    end

    model = Sketchup.active_model
    model.start_operation("Solid Ops — Combine All PRO (#{mode_label})", true)
    begin
      # Phase 1: Union/Shell all non-subtract solids
      result = union_solids[0]
      if union_solids.length >= 2
        puts "[Solid Ops]   Phase 1: #{mode_label} #{union_solids.length} solids..."
        union_solids[1..-1].each_with_index do |other, i|
          puts "[Solid Ops]     #{mode_label} step #{i + 1}..."
          model.selection.clear
          result = result.send(mode, other)
          unless result&.valid?
            model.abort_operation
            UI.messagebox("Combine All PRO failed at #{mode_label} step #{i + 1}.", MB_OK)
            return
          end
        end
      else
        puts "[Solid Ops]   Phase 1: Single base solid, skipping #{mode_label}"
      end

      # Phase 2: Subtract all subtract-colored solids
      # Native subtract: tool.subtract(base) subtracts tool from base,
      # erases tool, returns modified base
      if subtract_solids.any?
        puts "[Solid Ops]   Phase 2: Subtract #{subtract_solids.length} solids..."
        subtract_solids.each_with_index do |tool, i|
          puts "[Solid Ops]     subtract step #{i + 1}/#{subtract_solids.length}..."
          model.selection.clear
          result = tool.subtract(result)
          unless result&.valid?
            model.abort_operation
            UI.messagebox("Combine All PRO failed at subtract step #{i + 1}.", MB_OK)
            return
          end
        end
      end

      model.commit_operation
      model.selection.clear
      model.selection.add(result) if result&.valid?
      puts "[Solid Ops] Combine All PRO (#{mode_label}) done."
    rescue => e
      model.abort_operation
      puts "[Solid Ops] Combine All PRO error: #{e.message}"
      e.backtrace.first(10).each { |line| puts "  #{line}" }
      UI.messagebox("Combine All PRO error: #{e.message}", MB_OK)
    end
  end
end
