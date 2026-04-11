require_relative 'version'
require_relative 'circle_restore'

module SolidBatch
  unless @loaded
    submenu = UI.menu('Extensions').add_submenu(PLUGIN_NAME)

    submenu.add_item('Combine All (Union)') { self.do_combine_all_pro(:union) }
    submenu.add_item('Combine All (Shell)') { self.do_combine_all_pro(:outer_shell) }
    submenu.add_separator
    submenu.add_item('Set Subtract Color') { self.do_set_subtract_color }
    submenu.add_item('Set Repair Options') { self.do_set_repair_options }

    toolbar = UI::Toolbar.new(PLUGIN_NAME)

    icons_dir = File.join(PLUGIN_DIR, 'solid_batch', 'icons')

    cmd_combine_pro_union = UI::Command.new('Combine All (Union)') { self.do_combine_all_pro(:union) }
    cmd_combine_pro_union.tooltip = 'Combine All (Union) — native union + subtract'
    cmd_combine_pro_union.small_icon = File.join(icons_dir, 'combine_pro_union_16.png')
    cmd_combine_pro_union.large_icon = File.join(icons_dir, 'combine_pro_union_24.png')
    toolbar.add_item(cmd_combine_pro_union)

    cmd_combine_pro_shell = UI::Command.new('Combine All (Shell)') { self.do_combine_all_pro(:outer_shell) }
    cmd_combine_pro_shell.tooltip = 'Combine All (Shell) — native outer shell + subtract'
    cmd_combine_pro_shell.small_icon = File.join(icons_dir, 'combine_pro_shell_16.png')
    cmd_combine_pro_shell.large_icon = File.join(icons_dir, 'combine_pro_shell_24.png')
    toolbar.add_item(cmd_combine_pro_shell)

    cmd_setcolor = UI::Command.new('Set Subtract Color') { self.do_set_subtract_color }
    cmd_setcolor.tooltip = 'Set Subtract Color — pick color from selection'
    cmd_setcolor.small_icon = File.join(icons_dir, 'setcolor_16.png')
    cmd_setcolor.large_icon = File.join(icons_dir, 'setcolor_24.png')
    toolbar.add_item(cmd_setcolor)

    cmd_repairopts = UI::Command.new('Set Repair Options') { self.do_set_repair_options }
    cmd_repairopts.tooltip = 'Set Repair Options — circle restoration threshold'
    cmd_repairopts.small_icon = File.join(icons_dir, 'repair_circles_16.png')
    cmd_repairopts.large_icon = File.join(icons_dir, 'repair_circles_24.png')
    toolbar.add_item(cmd_repairopts)

    if toolbar.get_last_state == TB_VISIBLE
      toolbar.restore
      toolbar.show
    else
      toolbar.show
    end
    @loaded = true
  end

  # -------------------------------------------------------------------
  # Options management (persisted across sessions)
  # -------------------------------------------------------------------
  DEFAULT_SUBTRACT_COLOR = [255, 0, 0].freeze
  DEFAULT_AUTO_REPAIR_LARGE = 'Yes'.freeze
  DEFAULT_LARGE_THRESHOLD = 10000

  def self.subtract_color
    r = Sketchup.read_default('SolidBatch', 'subtract_color_r', DEFAULT_SUBTRACT_COLOR[0]).to_i
    g = Sketchup.read_default('SolidBatch', 'subtract_color_g', DEFAULT_SUBTRACT_COLOR[1]).to_i
    b = Sketchup.read_default('SolidBatch', 'subtract_color_b', DEFAULT_SUBTRACT_COLOR[2]).to_i
    Sketchup::Color.new(r, g, b)
  end

  def self.save_subtract_color(color)
    Sketchup.write_default('SolidBatch', 'subtract_color_r', color.red)
    Sketchup.write_default('SolidBatch', 'subtract_color_g', color.green)
    Sketchup.write_default('SolidBatch', 'subtract_color_b', color.blue)
  end

  def self.auto_repair_large
    Sketchup.read_default('SolidBatch', 'auto_repair_large', DEFAULT_AUTO_REPAIR_LARGE).to_s
  end

  def self.save_auto_repair_large(value)
    Sketchup.write_default('SolidBatch', 'auto_repair_large', value.to_s)
  end

  def self.large_threshold
    Sketchup.read_default('SolidBatch', 'large_threshold', DEFAULT_LARGE_THRESHOLD).to_i
  end

  def self.save_large_threshold(value)
    Sketchup.write_default('SolidBatch', 'large_threshold', value.to_i)
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

  def self.do_set_repair_options
    prompts = ['Auto-repair circles on large objects', 'Large object threshold (edges)']
    defaults = [auto_repair_large, large_threshold.to_s]
    list = ['Yes|No', '']
    title = 'Solid Batch — Repair Options'

    result = UI.inputbox(prompts, defaults, list, title)
    return unless result

    save_auto_repair_large(result[0])
    threshold_value = result[1].to_i
    threshold_value = DEFAULT_LARGE_THRESHOLD if threshold_value <= 0
    save_large_threshold(threshold_value)

    UI.messagebox(
      "Repair options saved:\n\n" \
      "  Auto-repair circles on large objects: #{result[0]}\n" \
      "  Large object threshold: #{threshold_value} edges\n\n" \
      "When the result of Combine All exceeds this threshold and " \
      "auto-repair is set to No, circle restoration is skipped " \
      "(a message is shown).",
      MB_OK
    )
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
    puts "[Solid Batch] Combine All (#{mode_label}): #{union_solids.length} union, #{subtract_solids.length} subtract"

    if union_solids.empty?
      UI.messagebox(
        "No base objects found (all selected objects have the subtract color).\n" \
        "At least one object must NOT have the subtract color RGB(#{sub_color.red}, #{sub_color.green}, #{sub_color.blue}).",
        MB_OK
      )
      return
    end

    model = Sketchup.active_model
    op_name = "Solid Batch — Combine All (#{mode_label})"
    first_op = true
    total_steps = (union_solids.length > 1 ? union_solids.length - 1 : 0) + subtract_solids.length
    current_step = 0
    begin
      # Phase 1: Union/Shell all non-subtract solids
      result = union_solids[0]
      if union_solids.length >= 2
        puts "[Solid Batch]   Phase 1: #{mode_label} #{union_solids.length} solids..."
        union_solids[1..-1].each_with_index do |other, i|
          current_step += 1
          pct = (current_step * 100.0 / total_steps).round
          Sketchup.status_text = "Solid Batch — #{mode_label} #{current_step}/#{total_steps} (#{pct}%)"
          model.start_operation(op_name, true, false, !first_op)
          first_op = false
          model.selection.clear
          result = result.send(mode, other)
          unless result&.valid?
            model.abort_operation
            UI.messagebox("Combine All failed at #{mode_label} step #{i + 1}.", MB_OK)
            return
          end
          model.commit_operation
        end
      else
        puts "[Solid Batch]   Phase 1: Single base solid, skipping #{mode_label}"
      end

      # Phase 2: Subtract all subtract-colored solids
      # Native subtract: tool.subtract(base) subtracts tool from base,
      # erases tool, returns modified base
      if subtract_solids.any?
        puts "[Solid Batch]   Phase 2: Subtract #{subtract_solids.length} solids..."
        subtract_solids.each_with_index do |tool, i|
          current_step += 1
          pct = (current_step * 100.0 / total_steps).round
          Sketchup.status_text = "Solid Batch — Subtract #{current_step}/#{total_steps} (#{pct}%)"
          model.start_operation(op_name, true, false, !first_op)
          first_op = false
          model.selection.clear
          result = tool.subtract(result)
          unless result&.valid?
            model.abort_operation
            UI.messagebox("Combine All failed at subtract step #{i + 1}.", MB_OK)
            return
          end
          model.commit_operation
        end
      end

      # Phase 3: Circle restoration on the final result
      skip_message = nil
      if result&.valid?
        edge_count = CircleRestore.count_edges(result)
        threshold = large_threshold
        repair_large_enabled = (auto_repair_large == 'Yes')
        should_restore = (edge_count <= threshold) || repair_large_enabled

        if should_restore
          Sketchup.status_text = "Solid Batch — Restoring circles..."
          puts "[Solid Batch]   Phase 3: Restoring circles (#{edge_count} edges)..."
          model.start_operation(op_name, true, false, !first_op)
          first_op = false
          restored = CircleRestore.restore_in_solid(result)
          model.commit_operation
          puts "[Solid Batch]   Phase 3: #{restored} circle(s) restored"
        else
          puts "[Solid Batch]   Phase 3: Skipped (#{edge_count} edges > #{threshold} threshold)"
          skip_message =
            "Circle restoration was skipped.\n\n" \
            "The result contains #{edge_count} edges, which exceeds the " \
            "configured threshold of #{threshold}.\n\n" \
            "To enable repair on large objects, use 'Set Options' and set " \
            "'Auto-repair circles on large objects' to Yes."
        end
      end

      model.selection.clear
      model.selection.add(result) if result&.valid?
      Sketchup.status_text = "Solid Batch — Done (#{total_steps} operations)"
      puts "[Solid Batch] Combine All (#{mode_label}) done."

      UI.messagebox(skip_message, MB_OK) if skip_message
    rescue => e
      model.abort_operation
      puts "[Solid Batch] Combine All error: #{e.message}"
      e.backtrace.first(10).each { |line| puts "  #{line}" }
      UI.messagebox("Combine All error: #{e.message}", MB_OK)
    end
  end
end
