require_relative 'version'
require_relative 'circle_restore'
require_relative 'solid_operations'

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
  DEFAULT_MIN_ARC_SEGMENTS = 6

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

  def self.min_arc_segments
    Sketchup.read_default('SolidBatch', 'min_arc_segments', DEFAULT_MIN_ARC_SEGMENTS).to_i
  end

  def self.save_min_arc_segments(value)
    Sketchup.write_default('SolidBatch', 'min_arc_segments', value.to_i)
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
    prompts = [
      'Auto-repair circles on large objects',
      'Large object threshold (edges)',
      'Min segments for arc detection',
    ]
    defaults = [
      auto_repair_large,
      large_threshold.to_s,
      min_arc_segments.to_s,
    ]
    list = ['Yes|No', '', '']
    title = 'Solid Batch — Repair Options'

    result = UI.inputbox(prompts, defaults, list, title)
    return unless result

    save_auto_repair_large(result[0])

    threshold_value = result[1].to_i
    threshold_value = DEFAULT_LARGE_THRESHOLD if threshold_value <= 0
    save_large_threshold(threshold_value)

    arc_segments = result[2].to_i
    arc_segments = DEFAULT_MIN_ARC_SEGMENTS if arc_segments < 3
    save_min_arc_segments(arc_segments)

    UI.messagebox(
      "Repair options saved:\n\n" \
      "  Auto-repair circles on large objects: #{result[0]}\n" \
      "  Large object threshold: #{threshold_value} edges\n" \
      "  Min segments for arc detection: #{arc_segments}\n\n" \
      "Lower 'Min segments for arc detection' = catches shorter arcs " \
      "but may produce false positives. Higher = safer.\n\n" \
      "When the result of Combine All exceeds the large threshold and " \
      "auto-repair is set to No, restoration is skipped (a message is shown).",
      MB_OK
    )
  end

  # Combine All without SketchUp Pro.
  def self.pro_only(line)
    UI.messagebox("PRO Only vs. #{File.basename(__FILE__)}:#{line}", MB_OK)
  end

  # Ruby engine (solid_operations.rb): the base is modified in place and the
  # other solid erased. Returns the base, or nil on failure.
  def self.ruby_boolean(op, base, other)
    # A component shared with other instances is made unique first: those
    # instances stay as they are, as with the native booleans.
    if base.is_a?(Sketchup::ComponentInstance) && base.definition.count_instances > 1
      base.make_unique
    end
    SolidOperations.send(op, base, other) ? base : nil
  end

  def self.do_combine_all_pro(mode)
    ruby = !Sketchup.is_pro?
    return pro_only(__LINE__) if ruby
    solids = get_solids(2)
    return unless solids

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
    # Step in progress (for the message of a failure), operation open,
    # operations committed (undone together if a later step fails).
    step = nil
    open_op = false
    committed = 0
    begin
      # Phase 1: Union/Shell all non-subtract solids
      result = union_solids[0]
      if union_solids.length >= 2
        puts "[Solid Batch]   Phase 1: #{mode_label} #{union_solids.length} solids..."
        union_solids[1..-1].each_with_index do |other, i|
          current_step += 1
          pct = (current_step * 100.0 / total_steps).round
          Sketchup.status_text = "Solid Batch — #{mode_label} #{current_step}/#{total_steps} (#{pct}%)"
          step = step_info(current_step, total_steps, "#{mode_label} #{i + 1} of #{union_solids.length - 1}", other)
          model.start_operation(op_name, true, false, !first_op)
          first_op = false
          open_op = true
          model.selection.clear
          result = ruby ? ruby_boolean(mode, result, other) : result.send(mode, other)
          unless result && result.valid?
            combine_failed(model, open_op, committed, step, 'The result was not a valid solid.')
            return
          end
          model.commit_operation
          open_op = false
          committed += 1
        end
      else
        puts "[Solid Batch]   Phase 1: Single base solid, skipping #{mode_label}"
      end

      # Phase 2: Subtract all subtract-colored solids
      # Native subtract: tool.subtract(base) subtracts tool from base,
      # erases tool, returns modified base. Ruby engine: base first.
      if subtract_solids.any?
        puts "[Solid Batch]   Phase 2: Subtract #{subtract_solids.length} solids..."
        subtract_solids.each_with_index do |tool, i|
          current_step += 1
          pct = (current_step * 100.0 / total_steps).round
          Sketchup.status_text = "Solid Batch — Subtract #{current_step}/#{total_steps} (#{pct}%)"
          step = step_info(current_step, total_steps, "Subtract #{i + 1} of #{subtract_solids.length}", tool)
          model.start_operation(op_name, true, false, !first_op)
          first_op = false
          open_op = true
          model.selection.clear
          result = ruby ? ruby_boolean(:subtract, result, tool) : tool.subtract(result)
          unless result && result.valid?
            combine_failed(model, open_op, committed, step, 'The result was not a valid solid.')
            return
          end
          model.commit_operation
          open_op = false
          committed += 1
        end
      end
      step = nil

      # Phase 3: Circle and arc restoration on the final result
      skip_message = nil
      repair_note = nil
      if result && result.valid?
        edge_count = CircleRestore.count_edges(result)
        threshold = large_threshold
        repair_large_enabled = (auto_repair_large == 'Yes')
        should_restore = (edge_count <= threshold) || repair_large_enabled

        if should_restore
          Sketchup.status_text = "Solid Batch — Restoring circles and arcs..."
          puts "[Solid Batch]   Phase 3: Restoring circles and arcs (#{edge_count} edges)..."
          model.start_operation(op_name, true, false, !first_op)
          first_op = false
          begin
            restored = CircleRestore.restore_in_solid(result, min_arc_segments: min_arc_segments)
            model.commit_operation
            repair_note = CircleRestore.summary(restored)
            puts "[Solid Batch]   Phase 3: #{CircleRestore.summary(restored, reasons: true)}"
          rescue => e
            # Only the restoration is undone: the boolean result is kept.
            model.abort_operation
            puts "[Solid Batch]   Phase 3 error: #{e.message}"
            e.backtrace.first(10).each { |line| puts "  #{line}" }
            skip_message =
              "Circle and arc restoration failed: #{e.message}\n\n" \
              "The Combine All result is kept; its circles and arcs were left as they were."
          end
        else
          puts "[Solid Batch]   Phase 3: Skipped (#{edge_count} edges > #{threshold} threshold)"
          skip_message =
            "Circle and arc restoration was skipped.\n\n" \
            "The result contains #{edge_count} edges, which exceeds the " \
            "configured threshold of #{threshold}.\n\n" \
            "To enable repair on large objects, use 'Set Repair Options' and set " \
            "'Auto-repair circles on large objects' to Yes."
        end
      end

      model.selection.clear
      model.selection.add(result) if result && result.valid?
      done_text = "Solid Batch — Done (#{total_steps} operations)"
      done_text += " — #{repair_note}" if repair_note
      Sketchup.status_text = done_text
      puts "[Solid Batch] Combine All (#{mode_label}) done."

      UI.messagebox(skip_message, MB_OK) if skip_message
    rescue => e
      puts "[Solid Batch] Combine All error: #{e.message}"
      e.backtrace.first(10).each { |line| puts "  #{line}" }
      if step
        combine_failed(model, open_op, committed, step, "Error: #{e.message}")
      else
        model.abort_operation if open_op
        UI.messagebox("Combine All error: #{e.message}", MB_OK)
      end
    end
  end

  # One step of Combine All, for the message of a failure.
  def self.step_info(number, total, action, solid)
    pid = solid.respond_to?(:persistent_id) ? solid.persistent_id : nil
    { number: number, total: total, action: action, solid: solid, pid: pid, label: solid_label(solid) }
  end

  # group "Name" at (x; y; z): center of its bounds, in model units
  # (semicolons: the decimal separator may be a comma).
  def self.solid_label(solid)
    kind = solid.is_a?(Sketchup::Group) ? 'group' : 'component'
    name = solid.name.to_s
    name = solid.definition.name.to_s if name.empty? && solid.is_a?(Sketchup::ComponentInstance)
    c = solid.bounds.center
    where = "at (#{c.x.to_l}; #{c.y.to_l}; #{c.z.to_l})"
    name.empty? ? "#{kind} #{where}" : "#{kind} \"#{name}\" #{where}"
  end

  # A step of Combine All failed: the steps already done are undone too, so
  # that the model is back as it was before Combine All. Aborting an operation
  # chained (transparent) to committed ones undoes the whole chain (checked by
  # the tests, T14); without an open operation, the committed steps are the
  # last undo step. The message names the step; its solid is selected.
  def self.combine_failed(model, open_op, committed, step, reason)
    undone = open_op || committed.zero?
    if open_op
      model.abort_operation
    elsif committed > 0 && Sketchup.respond_to?(:undo)
      Sketchup.undo
      undone = true
    end
    solid = step[:solid].valid? ? step[:solid] : find_by_persistent_id(model, step[:pid])
    model.selection.clear
    model.selection.add(solid) if solid
    text = "Combine All failed at step #{step[:number]} of #{step[:total]}: " \
           "#{step[:action]}, #{step[:label]}.\n#{reason}\n\n"
    text += if undone
              'Nothing was changed: the model is as it was before Combine All.'
            else
              "The #{committed} step(s) before it were applied: press Ctrl+Z to undo them."
            end
    if solid
      text += "\n\nThis solid is now selected: check that it is a solid (Entity Info) " \
              'and that its faces are not flush with the faces of the other solids.'
    end
    puts "[Solid Batch] #{text.tr("\n", ' ').squeeze(' ')}"
    Sketchup.status_text = "Solid Batch — Failed at step #{step[:number]}/#{step[:total]}"
    UI.messagebox(text, MB_OK)
  end

  def self.find_by_persistent_id(model, pid)
    return nil unless pid
    model.active_entities.find { |e| e.respond_to?(:persistent_id) && e.persistent_id == pid }
  end
end
