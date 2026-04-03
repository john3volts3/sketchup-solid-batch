module DRO_SolidOps
  module BooleanOps

    # Off-axis direction to reduce edge-on ray ambiguity
    RAY_DIR = Geom::Vector3d.new(1.0, 0.137, 0.049)

    # -----------------------------------------------------------------
    # Utility helpers
    # -----------------------------------------------------------------

    # Reliable test point on a face: centroid of first mesh triangle
    def self.face_test_point(face)
      mesh = face.mesh(0)
      indices = mesh.polygon_at(1)
      pts = indices.map { |i| mesh.point_at(i.abs) }
      Geom::Point3d.new(
        pts.sum { |p| p.x } / pts.length.to_f,
        pts.sum { |p| p.y } / pts.length.to_f,
        pts.sum { |p| p.z } / pts.length.to_f
      )
    end

    # Ray-casting inside/outside test against a solid
    # Counts crossings of a ray with the solid's faces; odd = inside
    def self.point_inside_solid?(point, solid, model)
      dir = RAY_DIR.normalize
      crossings = 0
      current = point.clone
      80.times do
        result = model.raytest([current, dir])
        break unless result
        hit_point, path = result
        crossings += 1 if path.any? { |e| e == solid }
        current = hit_point.offset(dir, 0.005)
      end
      crossings.odd?
    end

    # Test if a face's interior side sits inside another solid.
    # Samples a point slightly behind the face (into the face's own solid).
    def self.face_inside_solid?(face, group_tr, solid, model)
      center = face_test_point(face)
      center_w = center.transform(group_tr)
      normal_w = face.normal.transform(group_tr)
      normal_w.normalize! if normal_w.valid?
      test_pt = center_w.offset(normal_w.reverse, 0.05)
      point_inside_solid?(test_pt, solid, model)
    end

    # Remove stray edges (fewer than 2 adjoining faces)
    def self.cleanup_edges(entities)
      loop do
        strays = entities.grep(Sketchup::Edge).select { |e|
          e.valid? && e.faces.length < 2
        }
        break if strays.empty?
        entities.erase_entities(strays)
      end
    end

    # Add intersection edges to +copy+ by intersecting with +other_solid+
    def self.add_intersections(copy, other_solid)
      copy.entities.intersect_with(
        false, copy.transformation, copy.entities,
        other_solid.transformation, false, other_solid.entities
      )
    end

    # Explode copies and regroup into a single new group
    def self.merge_copies(copies, target_entities)
      all = []
      copies.each do |c|
        next unless c.valid?
        exploded = c.explode
        all.concat(exploded) if exploded
      end
      return nil if all.empty?
      target_entities.add_group(all)
    end

    # -----------------------------------------------------------------
    # UNION — merge N solids, preserving internal voids
    # -----------------------------------------------------------------
    def self.union(solids, model)
      model.start_operation('Solid Ops — Union', true)
      copies = nil
      begin
        entities = model.active_entities
        copies = solids.map { |s| s.copy }

        # Compute intersection edges on each copy
        copies.each_with_index do |copy, i|
          solids.each_with_index do |orig, j|
            next if i == j
            add_intersections(copy, orig)
          end
        end

        # Hide copies so raytest only hits originals
        copies.each { |c| c.hidden = true }

        # Delete faces whose interior is inside another original solid
        copies.each_with_index do |copy, i|
          to_del = copy.entities.grep(Sketchup::Face).select { |face|
            solids.each_with_index.any? { |orig, j|
              j != i && face_inside_solid?(face, copy.transformation, orig, model)
            }
          }
          copy.entities.erase_entities(to_del) unless to_del.empty?
          cleanup_edges(copy.entities)
        end

        copies.each { |c| c.hidden = false }
        result = merge_copies(copies, entities)
        solids.each { |s| s.erase! if s.valid? }

        model.commit_operation
        result
      rescue => e
        model.abort_operation
        copies&.each { |c| c.erase! if c&.valid? }
        UI.messagebox("Union error: #{e.message}\n#{e.backtrace.first(3).join("\n")}", MB_OK)
        nil
      end
    end

    # -----------------------------------------------------------------
    # SUBTRACT — base minus tool
    # -----------------------------------------------------------------
    def self.subtract(base, tool, model)
      model.start_operation('Solid Ops — Subtract', true)
      base_copy = nil
      tool_copy = nil
      begin
        entities = model.active_entities
        base_copy = base.copy
        tool_copy = tool.copy

        add_intersections(base_copy, tool)
        add_intersections(tool_copy, base)

        base_copy.hidden = true
        tool_copy.hidden = true

        # Remove base faces inside tool
        to_del = base_copy.entities.grep(Sketchup::Face).select { |f|
          face_inside_solid?(f, base_copy.transformation, tool, model)
        }
        base_copy.entities.erase_entities(to_del) unless to_del.empty?

        # Remove tool faces outside base (keep inside ones as new walls)
        to_del = tool_copy.entities.grep(Sketchup::Face).select { |f|
          !face_inside_solid?(f, tool_copy.transformation, base, model)
        }
        tool_copy.entities.erase_entities(to_del) unless to_del.empty?

        # Reverse kept tool faces — they now face inward
        tool_copy.entities.grep(Sketchup::Face).each { |f| f.reverse! }

        cleanup_edges(base_copy.entities)
        cleanup_edges(tool_copy.entities)

        base_copy.hidden = false
        tool_copy.hidden = false

        result = merge_copies([base_copy, tool_copy], entities)

        base.erase! if base.valid?
        tool.erase! if tool.valid?

        model.commit_operation
        result
      rescue => e
        model.abort_operation
        [base_copy, tool_copy].each { |c| c.erase! if c&.valid? }
        UI.messagebox("Subtract error: #{e.message}\n#{e.backtrace.first(3).join("\n")}", MB_OK)
        nil
      end
    end

    # -----------------------------------------------------------------
    # SPLIT — divide two solids into up to 3 pieces:
    #   A - B, B - A, A ∩ B
    # -----------------------------------------------------------------
    def self.split(solid_a, solid_b, model)
      model.start_operation('Solid Ops — Split', true)
      begin
        entities = model.active_entities
        results = []

        piece = make_subtraction(solid_a, solid_b, model, entities)
        results << piece if piece

        piece = make_subtraction(solid_b, solid_a, model, entities)
        results << piece if piece

        piece = make_intersection(solid_a, solid_b, model, entities)
        results << piece if piece

        solid_a.erase! if solid_a.valid?
        solid_b.erase! if solid_b.valid?

        if results.empty?
          model.abort_operation
          UI.messagebox("Split produced no results.", MB_OK)
          return nil
        end

        model.commit_operation
        results
      rescue => e
        model.abort_operation
        UI.messagebox("Split error: #{e.message}\n#{e.backtrace.first(3).join("\n")}", MB_OK)
        nil
      end
    end

    # -----------------------------------------------------------------
    # Split helpers (no operation wrapper — called inside split's block)
    # -----------------------------------------------------------------

    # Build base minus tool as a new group (originals untouched)
    def self.make_subtraction(base, tool, model, entities)
      base_copy = base.copy
      tool_copy = tool.copy

      add_intersections(base_copy, tool)
      add_intersections(tool_copy, base)

      base_copy.hidden = true
      tool_copy.hidden = true

      to_del = base_copy.entities.grep(Sketchup::Face).select { |f|
        face_inside_solid?(f, base_copy.transformation, tool, model)
      }
      base_copy.entities.erase_entities(to_del) unless to_del.empty?

      to_del = tool_copy.entities.grep(Sketchup::Face).select { |f|
        !face_inside_solid?(f, tool_copy.transformation, base, model)
      }
      tool_copy.entities.erase_entities(to_del) unless to_del.empty?

      tool_copy.entities.grep(Sketchup::Face).each { |f| f.reverse! }

      cleanup_edges(base_copy.entities)
      cleanup_edges(tool_copy.entities)

      base_copy.hidden = false
      tool_copy.hidden = false

      has_faces = base_copy.entities.grep(Sketchup::Face).any? ||
                  tool_copy.entities.grep(Sketchup::Face).any?
      if has_faces
        merge_copies([base_copy, tool_copy], entities)
      else
        base_copy.erase! if base_copy.valid?
        tool_copy.erase! if tool_copy.valid?
        nil
      end
    end

    # Build intersection (A ∩ B) as a new group (originals untouched)
    def self.make_intersection(solid_a, solid_b, model, entities)
      copy_a = solid_a.copy
      copy_b = solid_b.copy

      add_intersections(copy_a, solid_b)
      add_intersections(copy_b, solid_a)

      copy_a.hidden = true
      copy_b.hidden = true

      # Keep only faces inside the other solid
      to_del = copy_a.entities.grep(Sketchup::Face).select { |f|
        !face_inside_solid?(f, copy_a.transformation, solid_b, model)
      }
      copy_a.entities.erase_entities(to_del) unless to_del.empty?

      to_del = copy_b.entities.grep(Sketchup::Face).select { |f|
        !face_inside_solid?(f, copy_b.transformation, solid_a, model)
      }
      copy_b.entities.erase_entities(to_del) unless to_del.empty?

      cleanup_edges(copy_a.entities)
      cleanup_edges(copy_b.entities)

      copy_a.hidden = false
      copy_b.hidden = false

      has_faces = copy_a.entities.grep(Sketchup::Face).any? ||
                  copy_b.entities.grep(Sketchup::Face).any?
      if has_faces
        merge_copies([copy_a, copy_b], entities)
      else
        copy_a.erase! if copy_a.valid?
        copy_b.erase! if copy_b.valid?
        nil
      end
    end

  end
end
