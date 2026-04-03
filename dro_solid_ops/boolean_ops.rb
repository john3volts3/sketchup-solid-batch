module DRO_SolidOps
  module BooleanOps

    IDENTITY = Geom::Transformation.new unless defined?(IDENTITY)

    # =================================================================
    # Utility methods (ported from Eneroth Solid Tools)
    # =================================================================

    def self.definition(instance)
      if instance.is_a?(Sketchup::ComponentInstance) ||
         (Sketchup.version.to_i >= 15 && instance.is_a?(Sketchup::Group))
        instance.definition
      else
        instance.model.definitions.find { |d| d.instances.include?(instance) }
      end
    end

    def self.instance?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

    def self.solid?(container)
      return false unless instance?(container)
      definition(container).entities.grep(Sketchup::Edge).all? { |e| e.faces.size.even? }
    end

    def self.find_mesh_geometry(entities)
      entities.select { |e| [Sketchup::Face, Sketchup::Edge].include?(e.class) }
    end

    def self.uniq_points(points)
      points.reduce([]) { |a, p| a.any? { |p1| p1 == p } ? a : a << p }
    end

    def self.within_face?(point, face, on_boundary = true)
      pc = face.classify_point(point)
      return on_boundary if [Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex].include?(pc)
      pc == Sketchup::Face::PointInside
    end

    def self.within?(point, container, on_boundary = true, verify_solid = true)
      return false if verify_solid && !solid?(container)

      point = point.transform(container.transformation.inverse)

      vector = Geom::Vector3d.new(234, 1343, 345)
      ray = [point, vector]
      intersections = []

      definition(container).entities.grep(Sketchup::Face) do |face|
        return on_boundary if within_face?(point, face)

        intersection = Geom.intersect_line_plane(ray, face.plane)
        next unless intersection
        next if intersection == point
        next unless (intersection - point).samedirection?(vector)
        next unless within_face?(intersection, face)

        intersections << intersection
      end

      intersections = uniq_points(intersections)
      intersections.size.odd?
    end

    def self.point_at_face(face)
      return nil if face.area.zero?

      index = 1
      begin
        points = face.mesh.polygon_points_at(index)
        return nil unless points
        index += 1
      end while points[0].on_line?(points[1], points[2])

      Geom.linear_combination(
        0.5,
        Geom.linear_combination(0.5, points[0], 0.5, points[1]),
        0.5,
        points[2]
      )
    end

    def self.transpose(transformation)
      a = transformation.to_a
      Geom::Transformation.new([
        a[0], a[4], a[8],  0,
        a[1], a[5], a[9],  0,
        a[2], a[6], a[10], 0,
        0,    0,    0,     a[15]
      ])
    end

    def self.transform_as_normal(normal, transformation)
      tr = transpose(transformation).inverse
      normal.transform(tr).normalize
    end

    # =================================================================
    # Core methods (ported from Eneroth)
    # =================================================================

    def self.merge_into(destination, to_move, keep_original = false)
      tr = destination.transformation.inverse * to_move.transformation
      entities = definition(destination).entities
      temp = entities.add_instance(definition(to_move), tr)
      to_move.erase! unless keep_original
      temp.explode
    end

    def self.interior_hole_hack(edges)
      return if edges.empty?

      entities = edges.first.parent.entities
      old_entities = entities.to_a
      edges.each(&:find_faces)
      new_faces = entities.to_a - old_entities

      entities.erase_entities(
        new_faces.select { |f| !wrapping_face(f) || f.edges.any? { |e| e.faces.size != 2 } }
      )

      nil
    end

    def self.wrapping_face(face)
      (face.edges.map(&:faces).inject(:&) - [face]).first
    end

    def self.add_intersection_edges(container1, container2)
      entities1 = definition(container1).entities
      entities2 = definition(container2).entities

      temp_group = container1.parent.entities.add_group

      entities1.intersect_with(
        false,
        container1.transformation,
        temp_group.entities,
        IDENTITY,
        true,
        find_mesh_geometry(entities2)
      )
      entities2.intersect_with(
        false,
        container1.transformation.inverse,
        temp_group.entities,
        container1.transformation.inverse,
        true,
        find_mesh_geometry(entities1)
      )

      edge_count = temp_group.entities.grep(Sketchup::Edge).length
      puts "[Solid Ops]   intersection: #{edge_count} edges"

      interior_hole_hack(merge_into(container1, temp_group, true).grep(Sketchup::Edge))
      interior_hole_hack(merge_into(container2, temp_group).grep(Sketchup::Edge))

      nil
    end

    def self.find_faces(scope, reference, interior, on_surface)
      definition(scope).entities.select do |f|
        next unless f.is_a?(Sketchup::Face)
        point = point_at_face(f)
        next unless point
        point.transform!(scope.transformation)
        next if interior != within?(point, reference, interior == on_surface, false)
        true
      end
    end

    def self.find_corresponding_faces(container1, container2, orientation)
      faces = [[], []]

      definition(container1).entities.grep(Sketchup::Face) do |face1|
        normal1 = transform_as_normal(face1.normal, container1.transformation)
        points1 = face1.vertices.map { |v| v.position.transform(container1.transformation) }
        definition(container2).entities.grep(Sketchup::Face) do |face2|
          next unless face2.is_a?(Sketchup::Face)
          normal2 = transform_as_normal(face2.normal, container2.transformation)
          next unless normal1.parallel?(normal2)
          points2 = face2.vertices.map { |v| v.position.transform(container2.transformation) }
          next unless points1.all? { |v| points2.include?(v) }
          unless orientation.nil?
            next if normal1.samedirection?(normal2) != orientation
          end
          faces[0] << face1
          faces[1] << face2
        end
      end

      faces
    end

    def self.erase_faces_with_edges(faces)
      return if faces.empty?
      erase = faces + (faces.flat_map(&:edges).select { |e| (e.faces - faces).empty? })
      erase.first.parent.entities.erase_entities(erase)
      nil
    end

    def self.find_coplanar_edges(entities)
      entities.grep(Sketchup::Edge).select do |e|
        next unless e.faces.size == 2
        next unless e.faces[0].normal.parallel?(e.faces[1].normal)
        e.faces[0].vertices.all? do |v|
          e.faces[1].classify_point(v.position) != Sketchup::Face::PointNotOnPlane
        end
      end
    end

    def self.naked_edges(entities)
      entities.grep(Sketchup::Edge).select { |e| e.faces.size == 1 }
    end

    def self.weld_hack(entities)
      return if solid?(entities.parent)

      temp_group = entities.add_group
      naked_edges(entities).each do |e|
        temp_group.entities.add_line(e.start, e.end)
      end
      temp_group.explode

      nil
    end

    # =================================================================
    # Public operations
    # =================================================================

    def self.union(solids, model)
      model.start_operation('Solid Ops — Union', true)
      begin
        puts "[Solid Ops] Union: #{solids.length} solids"

        target = solids[0]
        target.make_unique if target.is_a?(Sketchup::Group)

        solids[1..-1].each_with_index do |modifier, i|
          puts "[Solid Ops]   step #{i + 1}: merging..."

          # Copy modifier into temp group
          temp_group = target.parent.entities.add_group
          merge_into(temp_group, modifier, true)
          mod = temp_group

          target_ents = definition(target).entities

          add_intersection_edges(target, mod)

          puts "[Solid Ops]   target: #{target_ents.grep(Sketchup::Face).length} faces"
          puts "[Solid Ops]   modifier: #{definition(mod).entities.grep(Sketchup::Face).length} faces"

          # Save references for overlapping face cleanup
          overlapping_edges = find_corresponding_faces(target, mod, nil)[0]
                               .flat_map(&:edges).map(&:vertices)

          # Remove interior faces + corresponding faces with opposite orientation
          erase1 = find_faces(target, mod, true, false)
          erase2 = find_faces(mod, target, true, false)
          c_faces1, c_faces2 = find_corresponding_faces(target, mod, false)
          erase1.concat(c_faces1)
          erase2.concat(c_faces2)

          puts "[Solid Ops]   erase from target: #{erase1.length}, from modifier: #{erase2.length}"

          erase_faces_with_edges(erase1)
          erase_faces_with_edges(erase2)

          merge_into(target, mod)

          # Clean up coplanar edges
          overlapping_edges.select! { |vs| vs.all?(&:valid?) }
          overlapping_edges.map! { |vs| vs[0].common_edge(vs[1]) }.compact!
          coplanar = find_coplanar_edges(overlapping_edges)
          target_ents.erase_entities(coplanar) unless coplanar.empty?

          weld_hack(target_ents)

          puts "[Solid Ops]   after merge: #{target_ents.grep(Sketchup::Face).length} faces, solid=#{solid?(target)}"
        end

        # Erase original modifiers
        solids[1..-1].each { |s| s.erase! if s.valid? }

        model.commit_operation
        target
      rescue => e
        model.abort_operation
        puts "[Solid Ops] Union error: #{e.message}"
        e.backtrace.first(10).each { |line| puts "  #{line}" }
        nil
      end
    end

    def self.subtract(base, tool, model)
      model.start_operation('Solid Ops — Subtract', true)
      begin
        puts "[Solid Ops] Subtract"

        target = base
        target.make_unique if target.is_a?(Sketchup::Group)

        # Copy modifier
        temp_group = target.parent.entities.add_group
        merge_into(temp_group, tool, true)
        mod = temp_group

        target_ents = definition(target).entities

        add_intersection_edges(target, mod)

        overlapping_edges = find_corresponding_faces(target, mod, nil)[0]
                             .flat_map(&:edges).map(&:vertices)

        # Trim: remove interior target faces, exterior modifier faces
        erase1 = find_faces(target, mod, true, false)
        erase2 = find_faces(mod, target, false, false)
        c_faces1, c_faces2 = find_corresponding_faces(target, mod, true)
        erase1.concat(c_faces1)
        erase2.concat(c_faces2)

        puts "[Solid Ops]   erase from target: #{erase1.length}, from modifier: #{erase2.length}"

        erase_faces_with_edges(erase1)
        erase_faces_with_edges(erase2)

        # Reverse modifier faces (they become inner walls)
        definition(mod).entities.each { |f| f.reverse! if f.is_a?(Sketchup::Face) }

        merge_into(target, mod)

        overlapping_edges.select! { |vs| vs.all?(&:valid?) }
        overlapping_edges.map! { |vs| vs[0].common_edge(vs[1]) }.compact!
        coplanar = find_coplanar_edges(overlapping_edges)
        target_ents.erase_entities(coplanar) unless coplanar.empty?

        weld_hack(target_ents)

        tool.erase! if tool.valid?

        puts "[Solid Ops]   result: #{target_ents.grep(Sketchup::Face).length} faces, solid=#{solid?(target)}"

        model.commit_operation
        target
      rescue => e
        model.abort_operation
        puts "[Solid Ops] Subtract error: #{e.message}"
        e.backtrace.first(10).each { |line| puts "  #{line}" }
        nil
      end
    end

    def self.split(solid_a, solid_b, model)
      model.start_operation('Solid Ops — Split', true)
      begin
        puts "[Solid Ops] Split"
        results = []

        # A - B
        puts "[Solid Ops]   A - B..."
        copy_a = solid_a.copy
        copy_a.make_unique
        temp = copy_a.parent.entities.add_group
        merge_into(temp, solid_b, true)
        mod_b = temp

        add_intersection_edges(copy_a, mod_b)

        ov = find_corresponding_faces(copy_a, mod_b, nil)[0].flat_map(&:edges).map(&:vertices)
        e1 = find_faces(copy_a, mod_b, true, false)
        e2 = find_faces(mod_b, copy_a, false, false)
        cf1, cf2 = find_corresponding_faces(copy_a, mod_b, true)
        e1.concat(cf1); e2.concat(cf2)
        erase_faces_with_edges(e1); erase_faces_with_edges(e2)
        definition(mod_b).entities.each { |f| f.reverse! if f.is_a?(Sketchup::Face) }
        merge_into(copy_a, mod_b)
        ov.select! { |vs| vs.all?(&:valid?) }
        ov.map! { |vs| vs[0].common_edge(vs[1]) }.compact!
        cp = find_coplanar_edges(ov)
        definition(copy_a).entities.erase_entities(cp) unless cp.empty?
        weld_hack(definition(copy_a).entities)
        results << copy_a if definition(copy_a).entities.grep(Sketchup::Face).any?
        puts "[Solid Ops]     #{definition(copy_a).entities.grep(Sketchup::Face).length} faces"

        # B - A
        puts "[Solid Ops]   B - A..."
        copy_b = solid_b.copy
        copy_b.make_unique
        temp2 = copy_b.parent.entities.add_group
        merge_into(temp2, solid_a, true)
        mod_a = temp2

        add_intersection_edges(copy_b, mod_a)

        ov2 = find_corresponding_faces(copy_b, mod_a, nil)[0].flat_map(&:edges).map(&:vertices)
        e3 = find_faces(copy_b, mod_a, true, false)
        e4 = find_faces(mod_a, copy_b, false, false)
        cf3, cf4 = find_corresponding_faces(copy_b, mod_a, true)
        e3.concat(cf3); e4.concat(cf4)
        erase_faces_with_edges(e3); erase_faces_with_edges(e4)
        definition(mod_a).entities.each { |f| f.reverse! if f.is_a?(Sketchup::Face) }
        merge_into(copy_b, mod_a)
        ov2.select! { |vs| vs.all?(&:valid?) }
        ov2.map! { |vs| vs[0].common_edge(vs[1]) }.compact!
        cp2 = find_coplanar_edges(ov2)
        definition(copy_b).entities.erase_entities(cp2) unless cp2.empty?
        weld_hack(definition(copy_b).entities)
        results << copy_b if definition(copy_b).entities.grep(Sketchup::Face).any?
        puts "[Solid Ops]     #{definition(copy_b).entities.grep(Sketchup::Face).length} faces"

        # A ∩ B
        puts "[Solid Ops]   A ∩ B..."
        copy_a2 = solid_a.copy
        copy_a2.make_unique
        temp3 = copy_a2.parent.entities.add_group
        merge_into(temp3, solid_b, true)
        mod_b2 = temp3

        add_intersection_edges(copy_a2, mod_b2)

        ov3 = find_corresponding_faces(copy_a2, mod_b2, nil)[0].flat_map(&:edges).map(&:vertices)
        e5 = find_faces(copy_a2, mod_b2, false, false)
        e6 = find_faces(mod_b2, copy_a2, false, false)
        cf5, cf6 = find_corresponding_faces(copy_a2, mod_b2, false)
        e5.concat(cf5); e6.concat(cf6)
        erase_faces_with_edges(e5); erase_faces_with_edges(e6)
        merge_into(copy_a2, mod_b2)
        ov3.select! { |vs| vs.all?(&:valid?) }
        ov3.map! { |vs| vs[0].common_edge(vs[1]) }.compact!
        cp3 = find_coplanar_edges(ov3)
        definition(copy_a2).entities.erase_entities(cp3) unless cp3.empty?
        weld_hack(definition(copy_a2).entities)
        results << copy_a2 if definition(copy_a2).entities.grep(Sketchup::Face).any?
        puts "[Solid Ops]     #{definition(copy_a2).entities.grep(Sketchup::Face).length} faces"

        solid_a.erase! if solid_a.valid?
        solid_b.erase! if solid_b.valid?

        if results.empty?
          model.abort_operation
          puts "[Solid Ops] Split: no result"
          return nil
        end

        model.commit_operation
        results
      rescue => e
        model.abort_operation
        puts "[Solid Ops] Split error: #{e.message}"
        e.backtrace.first(10).each { |line| puts "  #{line}" }
        nil
      end
    end

  end
end
