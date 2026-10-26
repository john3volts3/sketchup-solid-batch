# encoding: UTF-8
# Ported from Re-Cercle v2.0.0 (re_cercle/volume.rb), unchanged except the
# namespace: SolidBatch::CircleRestore instead of ReCercle. Solid Batch does
# not depend on Re-Cercle.
#
# Since Solid Batch 2.4.0, repair_holes finds the hole edges through
# grids instead of scanning every edge for every hole (same result, much
# faster on a face with many holes): code of Solid for Maker 1.0.0.
#
# Native rebuild of straight cylinders and truncated cones (holes, pins)
# whose end circle is broken, with the same segment count. Adapted from
# Circle Re-Segment (detector and Push/Pull rebuild), validated there:
#
# Detection: the wall is a surface of faces joined by soft edges, bounded
# by exactly two closed loops of hard edges; each loop is a circle (chain
# detection of Detector: split points accepted), both coaxial with the same
# segment count; no other line attached to the circles; faces touching a
# circle outside the wall lie in its plane; a face at one end at least.
#
# Rebuild:
#   1. Snapshot the faces touching each circle (disc or host face with a
#      hole: normal, materials, tag, one outer edge) and their other inner
#      loops (holes); the wall properties.
#   2. Erase the wall and the circles (host faces close themselves).
#   3. Draw the new circle (add_arc, same phase) on the end that carries a
#      face (host face preferred), find_faces -> disc.
#   4. disc.pushpull up to the plane of the other end (through holes are
#      drilled by SketchUp as with the Push/Pull tool).
#   5. Truncated cone: scale the far circle about its center.
#   6. Restore wall and caps properties; erase new faces that did not
#      exist (disc over a through hole) or that fill a former hole.
# Both end circles are then native ArcCurves.

module SolidBatch
  module CircleRestore
    module Volume
      MIN_FACES = 3

      # One end circle. vertices: ordered, with split points; corners:
      # polygon corners only.
      Loop = Struct.new(:edges, :vertices, :corners, :center, :normal, :radius, :segments)

      Body = Struct.new(:faces, :loops)

      def self.tolerance(radius)
        Detector.tolerance(radius)
      end

      # --- Detection -------------------------------------------------------------

      # [body, nil] when +chain+ is an end circle of a straight cylinder or
      # truncated cone whose wall contains one of +faces+, else [nil, reason].
      def self.detect(chain, faces)
        chain_set = {}
        chain.edges.each { |e| chain_set[e] = true }
        seen = {}
        reason = nil
        faces.each do |f|
          next if seen[f]
          surface = surface_of(f)
          surface.each { |s| seen[s] = true }
          body, why = build(surface)
          if body && body.loops.any? { |l| l.edges.any? { |e| chain_set[e] } }
            return [body, nil]
          end
          reason ||= why || 'circle shared with another surface'
        end
        [nil, reason || 'not a cylinder or cone end']
      end

      # Faces reachable from +face+ through soft edges.
      def self.surface_of(face)
        result = [face]
        seen = { face => true }
        queue = [face]
        until queue.empty?
          f = queue.shift
          f.edges.each do |e|
            next unless e.soft?
            e.faces.each do |other|
              next if seen[other]
              seen[other] = true
              result << other
              queue << other
            end
          end
        end
        result
      end

      # Returns [body, nil] or [nil, reason].
      def self.build(faces)
        return [nil, 'not a cylinder or cone (curved surface)'] if faces.length < MIN_FACES
        face_set = {}
        faces.each { |f| face_set[f] = true }
        boundary = faces.flat_map(&:edges).uniq.select do |e|
          !e.soft? && e.faces.count { |f| face_set[f] } == 1
        end
        loops = build_loops(boundary)
        return [nil, 'curved surface with an open or branching boundary'] unless loops
        return [nil, 'curved surface that is not a cylinder or cone'] unless loops.length == 2
        circles = loops.map { |edges, vertices| fit_loop(edges, vertices) }
        return [nil, 'curved surface with a non circular end'] if circles.include?(nil)
        return [nil, 'cylinder ends with different segment counts'] if circles[0].segments != circles[1].segments
        return [nil, 'oblique cylinder or cone'] unless coaxial?(*circles)

        allowed = {}
        circles.each { |c| c.vertices.each { |v| allowed[v] = true } }
        unless faces.all? { |f| f.vertices.all? { |v| allowed[v] } }
          return [nil, 'curved surface that is not a cylinder or cone']
        end
        wall_edge = ->(e) { !e.faces.empty? && e.faces.all? { |f| face_set[f] } }
        circles.each do |c|
          loop_set = {}
          c.edges.each { |e| loop_set[e] = true }
          c.vertices.each do |v|
            next if v.edges.all? { |e| loop_set[e] || wall_edge.call(e) }
            return [nil, 'cylinder end with a line attached']
          end
          tol = tolerance(c.radius)
          c.edges.flat_map(&:faces).uniq.each do |f|
            next if face_set[f]
            on_plane = f.normal.parallel?(c.normal) &&
                       c.center.vector_to(f.vertices.first.position).dot(c.normal).abs < tol
            return [nil, 'circle shared with another surface'] unless on_plane
          end
        end
        body = Body.new(faces, circles)
        return [nil, 'cylinder without a face at either end'] unless start_loop(snapshot_caps(body))
        [body, nil]
      end

      # Chains edges into closed loops. Returns [[edges, ordered_vertices], ...]
      # or nil if a vertex does not have exactly two boundary edges.
      def self.build_loops(edges)
        return nil if edges.empty?
        adjacency = Hash.new { |h, k| h[k] = [] }
        edges.each { |e| e.vertices.each { |v| adjacency[v] << e } }
        return nil unless adjacency.values.all? { |list| list.length == 2 }
        loops = []
        used = {}
        edges.each do |start|
          next if used[start]
          loop_edges = []
          vertices = []
          edge = start
          vertex = start.start
          until used[edge]
            used[edge] = true
            loop_edges << edge
            vertices << vertex
            vertex = edge.other_vertex(vertex)
            edge = (adjacency[vertex] - [edge]).first
          end
          loops << [loop_edges, vertices]
        end
        loops
      end

      # Loop when the boundary loop is exactly one circle chain, else nil.
      def self.fit_loop(edges, vertices)
        chain = Detector.chain_from(edges.first)
        return nil unless chain && chain.closed && chain.edges.length == edges.length
        loop_set = {}
        edges.each { |e| loop_set[e] = true }
        return nil unless chain.edges.all? { |e| loop_set[e] }
        Loop.new(edges, vertices, chain.corners, chain.center, chain.normal,
                 chain.radius, chain.runs.length)
      end

      # Parallel circles whose centers lie on their common axis.
      def self.coaxial?(a, b)
        tol = tolerance([a.radius, b.radius].max)
        return false unless a.normal.parallel?(b.normal)
        axis = a.center.vector_to(b.center)
        axis.length.to_f > tol && axis.parallel?(a.normal)
      end

      # --- Rebuild ---------------------------------------------------------------

      # Rebuilds +body+ in +entities+ with native end circles.
      def self.rebuild(entities, body)
        snap = snapshot(entities, body)
        s = start_loop(snap[:caps])
        raise 'no face at either end of the cylinder' unless s
        pushpull_rebuild(entities, body, snap, s)
      end

      def self.snapshot(entities, body)
        line = axis_line(body)
        wall = body.faces.first
        # Same phase for both circles: x axis through the first corner of
        # loop 0, so that the new vertices come back at the same place.
        a = body.loops[0]
        xa = a.center.vector_to(a.corners.first.position)
        frames = body.loops.map do |c|
          nk = c.normal.dot(a.normal) < 0 ? c.normal.reverse : c.normal.clone
          xk = Geom::Vector3d.linear_combination(1.0, xa, -xa.dot(nk), nk)
          xk.normalize!
          [c.center.clone, xk, nk, c.radius]
        end
        existing = {}
        entities.grep(Sketchup::Face).each { |f| existing[f.entityID] = true }
        {
          line: line,
          wall: {
            material: wall.material, back_material: wall.back_material,
            layer: wall.layer, outward: outward?(wall, line)
          },
          caps: snapshot_caps(body),
          holes: snapshot_holes(body),
          edge_layers: body.loops.map { |c| c.edges.first.layer },
          segments: a.segments,
          frames: frames,
          existing: existing
        }
      end

      def self.snapshot_caps(body)
        face_set = {}
        body.faces.each { |f| face_set[f] = true }
        body.loops.map do |c|
          loop_set = {}
          c.edges.each { |e| loop_set[e] = true }
          c.edges.flat_map(&:faces).uniq.reject { |f| face_set[f] }.map do |f|
            disc = f.outer_loop.edges.all? { |e| loop_set[e] }
            {
              disc: disc,
              normal: f.normal,
              material: f.material,
              back_material: f.back_material,
              layer: f.layer
            }
          end
        end
      end

      # Inner loops (holes) of the faces touching the circles, except the
      # circles themselves: vertex positions of each hole.
      def self.snapshot_holes(body)
        face_set = {}
        body.faces.each { |f| face_set[f] = true }
        holes = []
        body.loops.each do |c|
          loop_set = {}
          c.edges.each { |e| loop_set[e] = true }
          c.edges.flat_map(&:faces).uniq.reject { |f| face_set[f] }.each do |f|
            f.loops.each do |lp|
              next if lp.outer?
              next if lp.edges.any? { |e| loop_set[e] }
              holes << lp.vertices.map { |v| v.position.clone }
            end
          end
        end
        holes
      end

      # Index of the circle to start the Push/Pull from (host face preferred),
      # or nil when no end carries a face.
      def self.start_loop(caps)
        [0, 1].find { |k| caps[k].any? { |c| !c[:disc] } } ||
          [0, 1].find { |k| !caps[k].empty? }
      end

      def self.pushpull_rebuild(entities, body, snap, s)
        e = 1 - s
        fs = snap[:frames][s]
        fe = snap[:frames][e]
        n = snap[:segments]

        entities.erase_entities(body.faces + body.faces.flat_map(&:edges).uniq)

        arc = entities.add_arc(fs[0], fs[1], fs[2], fs[3], 0, 2 * Math::PI, n)
        arc.each { |ed| ed.layer = snap[:edge_layers][s] }
        arc.first.find_faces
        disc = arc.first.faces.find do |f|
          f.outer_loop.edges.all? { |ed| ring_edge?(ed, fs) }
        end
        raise 'no face could be created on the new circle' unless disc
        disc.pushpull(fs[0].vector_to(fe[0]).dot(disc.normal))

        # Truncated cone: the far circle has the start radius until scaled.
        tol = tolerance([fs[3], fe[3]].max)
        if (fe[3] - fs[3]).abs > tol
          far = ring_edges(entities, [fe[0], fe[1], fe[2], fs[3]])
          unless far.empty?
            entities.transform_entities(
              Geom::Transformation.scaling(fe[0], fe[3] / fs[3]), far)
          end
        end
        ring_edges(entities, fe).each { |ed| ed.layer = snap[:edge_layers][e] }

        wall_set = {}
        ring_edges(entities, fs).flat_map(&:faces).uniq.each do |f|
          next if f.normal.parallel?(fs[2])
          wall_set[f] = true
          apply_wall(f, snap, fs, fe)
        end
        repair_caps(entities, snap[:frames], snap[:caps], snap[:existing], wall_set)
        repair_holes(entities, snap[:holes], snap[:existing])
      end

      def self.axis_line(body)
        a = body.loops[0]
        [a.center, a.center.vector_to(body.loops[1].center)]
      end

      # True when the face normal points away from the axis.
      def self.outward?(face, line)
        c = face.bounds.center
        radial = c.project_to_line(line).vector_to(c)
        face.normal.dot(radial) > 0
      end

      # Wall face: orientation, materials, tag of the former wall; lateral
      # edges (not on a circle) softened.
      def self.apply_wall(face, snap, *frames)
        props = snap[:wall]
        face.reverse! if outward?(face, snap[:line]) != props[:outward]
        face.material = props[:material]
        face.back_material = props[:back_material]
        face.layer = props[:layer]
        face.edges.each do |ed|
          next if frames.any? { |fr| ring_edge?(ed, fr) }
          ed.soft = true
          ed.smooth = true
        end
      end

      def self.on_circle?(pt, frame)
        center, _xaxis, normal, radius = frame
        tol = tolerance(radius)
        v = center.vector_to(pt)
        v.dot(normal).abs < tol && (v.length.to_f - radius).abs < tol
      end

      def self.ring_edge?(edge, frame)
        on_circle?(edge.start.position, frame) && on_circle?(edge.end.position, frame)
      end

      def self.ring_edges(entities, frame)
        entities.grep(Sketchup::Edge).select { |ed| ring_edge?(ed, frame) }
      end

      # New faces touching a circle: keep those that existed before (disc or
      # host face) with their properties, erase the others. Faces are matched
      # geometrically, not by edge identity.
      def self.repair_caps(entities, frames, caps, existing, wall_set)
        new_faces = entities.grep(Sketchup::Face).reject do |f|
          existing[f.entityID] || wall_set[f]
        end
        handled = {}
        frames.each_with_index do |frame, k|
          new_faces.each do |f|
            next if handled[f] || !f.valid?
            next unless f.edges.any? { |ed| ring_edge?(ed, frame) }
            handled[f] = true
            disc = f.outer_loop.edges.all? { |ed| ring_edge?(ed, frame) }
            rec = caps[k].find { |c| c[:disc] == disc }
            if rec
              f.reverse! if f.normal.dot(rec[:normal]) < 0
              f.material = rec[:material]
              f.back_material = rec[:back_material]
              f.layer = rec[:layer]
            else
              f.erase!
            end
          end
        end
      end

      # A face rebuilt on the plane of a former hole may lie over its edges
      # without being split: find_faces on one hole edge splits it (no edge is
      # erased, so the hole circle stays native), then new faces filling a
      # former hole are erased.
      #
      # Hole points and vertices are indexed once in grids of tolerance-sized
      # cells (Solid for Maker): scanning every edge for every hole made a
      # plate with many holes take about 1 s per rebuilt cylinder.
      def self.repair_holes(entities, holes, existing)
        tol = Detector::BASE_TOL * 10
        hole_grids = holes.map { |h| point_grid(h, tol) }
        vertex_grid = {}
        entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq.each do |v|
          (vertex_grid[cell_of(v.position, tol)] ||= []) << v
        end
        holes.each_with_index do |h, i|
          edge = hole_edge(h, hole_grids[i], vertex_grid, tol)
          edge.find_faces if edge
        end
        entities.grep(Sketchup::Face).each do |f|
          next if !f.valid? || existing[f.entityID]
          pts = f.outer_loop.vertices.map(&:position)
          filled = holes.each_with_index.any? do |h, i|
            h.length == pts.length && pts.all? { |p| near_grid?(p, hole_grids[i], tol) }
          end
          f.erase! if filled
        end
      end

      # An edge whose both ends lie on the hole points (any of them suits
      # find_faces), found through the vertices near the hole points.
      def self.hole_edge(points, grid, vertex_grid, tol)
        points.each do |q|
          near_items(q, vertex_grid, tol) { |v| v.position }.each do |v|
            v.edges.each do |ed|
              return ed if near_grid?(ed.other_vertex(v).position, grid, tol)
            end
          end
        end
        nil
      end

      # Grid of points: cell => points of that cell.
      def self.point_grid(points, tol)
        grid = {}
        points.each { |p| (grid[cell_of(p, tol)] ||= []) << p }
        grid
      end

      def self.cell_of(p, tol)
        [(p.x.to_f / tol).floor, (p.y.to_f / tol).floor, (p.z.to_f / tol).floor]
      end

      # Items of the grid closer than tol to p: with tol-sized cells they lie
      # in the 27 cells around p's cell.
      def self.near_items(p, grid, tol)
        cx, cy, cz = cell_of(p, tol)
        found = []
        (-1..1).each do |dx|
          (-1..1).each do |dy|
            (-1..1).each do |dz|
              items = grid[[cx + dx, cy + dy, cz + dz]]
              next unless items
              items.each do |item|
                position = block_given? ? yield(item) : item
                found << item if p.distance(position) < tol
              end
            end
          end
        end
        found
      end

      def self.near_grid?(p, grid, tol)
        !near_items(p, grid, tol).empty?
      end
    end
  end
end
