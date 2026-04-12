module SolidBatch
  # CircleRestore — restoration of broken circles AND arcs after boolean operations.
  #
  # Circle detection adapted from the Re-Cercle plugin (Claude Code, 2026).
  # Arc detection added in v2.2.0 — same circumcircle math, but matches open
  # chains (2 endpoints of degree 1) instead of closed loops.
  #
  # The algorithm detects shapes purely from current geometry (no inventory
  # phase needed) and welds matching edges back into a Curve so that a single
  # click selects the whole circle/arc again.
  module CircleRestore
    TOLERANCE = 0.1
    MIN_SEGMENTS = 8           # circles + stage 2 fragmented curves
    DEFAULT_MIN_ARC_SEGMENTS = 8

    # ------------------------------------------------------------------
    # Public entry points
    # ------------------------------------------------------------------

    # Count all edges contained in a Group/ComponentInstance, recursively
    # entering nested groups and components.
    def self.count_edges(solid)
      return 0 unless solid && solid.valid?
      entities = inner_entities(solid)
      return 0 unless entities
      count_edges_in_entities(entities)
    end

    # Restore broken circles and arcs inside a Group/ComponentInstance.
    #
    # Returns a hash: { circles: N, arcs: M, total: N+M }
    #
    # min_arc_segments — minimum number of edges in a chain to be considered
    # an arc. Lower = more aggressive (catches short arcs but may produce
    # false positives on coincidental L-shapes). Higher = safer.
    def self.restore_in_solid(solid, min_arc_segments: DEFAULT_MIN_ARC_SEGMENTS)
      result = { circles: 0, arcs: 0, total: 0 }
      return result unless solid && solid.valid?
      entities = inner_entities(solid)
      return result unless entities
      # Entities#weld requires SketchUp 2020.1+ — skip silently on older versions
      return result unless entities.respond_to?(:weld)

      all_edges = collect_edges_from_entities(entities)
      return result if all_edges.empty?

      circles_found = 0
      arcs_found = 0

      # Stage 1a — Circles: free edges forming closed chains on a circumcircle
      loose_edges = all_edges.select { |e| e.valid? && e.curve.nil? }
      circles_from_loose = find_circles_by_geometry(loose_edges)
      circles_from_loose.each do |circle_edges|
        ctx = find_entities_context(circle_edges.first)
        if ctx
          ctx.weld(circle_edges)
          circles_found += 1
        end
      end

      # Stage 1b — Arcs: free edges forming OPEN chains on a circumcircle.
      # Re-collect entities to ensure stale references from welded circles
      # don't pollute the loose-edges set.
      all_edges = collect_edges_from_entities(entities)
      loose_edges = all_edges.select { |e| e.valid? && e.curve.nil? }
      arcs_from_loose = find_arcs_by_geometry(loose_edges, min_arc_segments)
      arcs_from_loose.each do |arc_edges|
        ctx = find_entities_context(arc_edges.first)
        if ctx
          ctx.weld(arc_edges)
          arcs_found += 1
        end
      end

      # Stage 2 — fragmented Curves (edges already in a Curve, but split).
      # Handles both circles and arcs uniformly via group_by_circle_geometry.
      all_edges = collect_edges_from_entities(entities)
      curved_edges = all_edges.select { |e| e.valid? && e.curve }
      curve_groups = group_by_circle_geometry(curved_edges)
      curve_groups.each do |group|
        curves = group.map { |e| e.curve }.compact.uniq
        next if curves.length <= 1
        next if group.length < MIN_SEGMENTS
        next unless edges_form_circle?(group)
        ctx = find_entities_context(group.first)
        if ctx
          ctx.weld(group)
          circles_found += 1
        end
      end

      result[:circles] = circles_found
      result[:arcs] = arcs_found
      result[:total] = circles_found + arcs_found
      result
    end

    # ------------------------------------------------------------------
    # Internals — entities walking
    # ------------------------------------------------------------------

    def self.inner_entities(solid)
      if solid.is_a?(Sketchup::Group)
        solid.entities
      elsif solid.is_a?(Sketchup::ComponentInstance)
        solid.definition.entities
      end
    end

    def self.count_edges_in_entities(entities)
      n = 0
      entities.each do |e|
        case e
        when Sketchup::Edge
          n += 1
        when Sketchup::Group
          n += count_edges_in_entities(e.entities)
        when Sketchup::ComponentInstance
          n += count_edges_in_entities(e.definition.entities)
        end
      end
      n
    end

    def self.collect_edges_from_entities(entities)
      edges = []
      entities.grep(Sketchup::Edge) { |e| edges << e }
      entities.grep(Sketchup::Group) { |g| edges.concat(collect_edges_from_entities(g.entities)) }
      entities.grep(Sketchup::ComponentInstance) { |c| edges.concat(collect_edges_from_entities(c.definition.entities)) }
      edges
    end

    def self.find_entities_context(edge)
      return nil unless edge && edge.valid?
      edge.parent.entities
    end

    # ------------------------------------------------------------------
    # Stage 1 — circle detection from free edges via circumcircle
    # ------------------------------------------------------------------

    def self.find_circles_by_geometry(edges)
      return [] if edges.empty?

      # Build vertex -> edges adjacency (only among given edges)
      adj = {}
      edges.each do |e|
        [e.start, e.end].each do |v|
          vid = v.entityID
          adj[vid] ||= []
          adj[vid] << e
        end
      end

      processed = {}
      circles = []

      edges.each do |edge|
        next if processed[edge.entityID]

        all_neighbors = []
        [edge.start, edge.end].each do |vertex|
          (adj[vertex.entityID] || []).each do |e|
            next if e == edge || processed[e.entityID]
            all_neighbors << { adj_edge: e, shared_vertex: vertex }
          end
        end
        next if all_neighbors.empty?

        found = false
        all_neighbors.each do |neighbor_info|
          next if found
          adj_edge = neighbor_info[:adj_edge]
          shared_v = neighbor_info[:shared_vertex]

          p2 = shared_v.position
          p1 = (edge.start == shared_v) ? edge.end.position : edge.start.position
          p3 = (adj_edge.start == shared_v) ? adj_edge.end.position : adj_edge.start.position

          circle_info = compute_circumcircle(p1, p2, p3)
          next unless circle_info

          center = circle_info[:center]
          radius = circle_info[:radius]
          normal = circle_info[:normal]

          dist_tol = [TOLERANCE, radius * 0.005].max

          matching = edges.select do |e|
            next false if processed[e.entityID]
            next false unless e.valid?
            d1 = (e.start.position.distance(center) - radius).abs
            d2 = (e.end.position.distance(center) - radius).abs
            next false unless d1 < dist_tol && d2 < dist_tol
            v1 = center.vector_to(e.start.position)
            v2 = center.vector_to(e.end.position)
            next false if v1.length < 0.001 || v2.length < 0.001
            v1.normalize!
            v2.normalize!
            next false unless v1.dot(normal).abs < 0.01 && v2.dot(normal).abs < 0.01
            true
          end

          next if matching.length < MIN_SEGMENTS
          next unless closed_chain?(matching)

          matching.each { |e| processed[e.entityID] = true }
          circles << matching
          found = true
        end
      end

      circles
    end

    def self.compute_circumcircle(p1, p2, p3)
      v1 = Geom::Vector3d.new(p2.x - p1.x, p2.y - p1.y, p2.z - p1.z)
      v2 = Geom::Vector3d.new(p3.x - p1.x, p3.y - p1.y, p3.z - p1.z)

      normal = v1.cross(v2)
      return nil if normal.length < 0.001
      normal.normalize!

      m1 = Geom::Point3d.new((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0, (p1.z + p2.z) / 2.0)
      m2 = Geom::Point3d.new((p1.x + p3.x) / 2.0, (p1.y + p3.y) / 2.0, (p1.z + p3.z) / 2.0)

      d1 = v1.cross(normal)
      d2 = v2.cross(normal)

      delta = Geom::Vector3d.new(m2.x - m1.x, m2.y - m1.y, m2.z - m1.z)
      d1_cross_d2 = d1.cross(d2)
      denom = d1_cross_d2.dot(d1_cross_d2)
      return nil if denom < 1e-10

      t = delta.cross(d2).dot(d1_cross_d2) / denom

      center = Geom::Point3d.new(m1.x + t * d1.x, m1.y + t * d1.y, m1.z + t * d1.z)
      radius = center.distance(p1)

      return nil if radius < 0.01

      { center: center, radius: radius, normal: normal }
    end

    def self.closed_chain?(chain)
      vertex_count = {}
      chain.each do |edge|
        [edge.start.entityID, edge.end.entityID].each do |vid|
          vertex_count[vid] = (vertex_count[vid] || 0) + 1
        end
      end
      vertex_count.values.all? { |c| c == 2 }
    end

    # ------------------------------------------------------------------
    # Stage 1b — arc detection from free edges via circumcircle
    # ------------------------------------------------------------------

    # Find arcs (open chains lying on a common circumcircle) among free edges.
    # Mirrors find_circles_by_geometry but matches OPEN chains instead of closed.
    def self.find_arcs_by_geometry(edges, min_segments)
      return [] if edges.empty?
      return [] if min_segments < 3

      # Build vertex -> edges adjacency (only among given edges)
      adj = {}
      edges.each do |e|
        [e.start, e.end].each do |v|
          vid = v.entityID
          adj[vid] ||= []
          adj[vid] << e
        end
      end

      processed = {}
      arcs = []

      edges.each do |edge|
        next if processed[edge.entityID]

        all_neighbors = []
        [edge.start, edge.end].each do |vertex|
          (adj[vertex.entityID] || []).each do |e|
            next if e == edge || processed[e.entityID]
            all_neighbors << { adj_edge: e, shared_vertex: vertex }
          end
        end
        next if all_neighbors.empty?

        found = false
        all_neighbors.each do |neighbor_info|
          next if found
          adj_edge = neighbor_info[:adj_edge]
          shared_v = neighbor_info[:shared_vertex]

          p2 = shared_v.position
          p1 = (edge.start == shared_v) ? edge.end.position : edge.start.position
          p3 = (adj_edge.start == shared_v) ? adj_edge.end.position : adj_edge.start.position

          circle_info = compute_circumcircle(p1, p2, p3)
          next unless circle_info

          center = circle_info[:center]
          radius = circle_info[:radius]
          normal = circle_info[:normal]

          dist_tol = [TOLERANCE, radius * 0.005].max

          matching = edges.select do |e|
            next false if processed[e.entityID]
            next false unless e.valid?
            d1 = (e.start.position.distance(center) - radius).abs
            d2 = (e.end.position.distance(center) - radius).abs
            next false unless d1 < dist_tol && d2 < dist_tol
            v1 = center.vector_to(e.start.position)
            v2 = center.vector_to(e.end.position)
            next false if v1.length < 0.001 || v2.length < 0.001
            v1.normalize!
            v2.normalize!
            next false unless v1.dot(normal).abs < 0.01 && v2.dot(normal).abs < 0.01
            true
          end

          next if matching.length < min_segments
          # KEY DIFFERENCE: must be an OPEN chain (arc), not closed (circle).
          # Closed chains should already have been caught by find_circles_by_geometry.
          next unless open_chain?(matching)

          matching.each { |e| processed[e.entityID] = true }
          arcs << matching
          found = true
        end
      end

      arcs
    end

    # Open chain test for arcs: exactly 2 vertices have degree 1 (endpoints),
    # and all other vertices have degree 2 (intermediate). Also rejects
    # branched chains (any vertex with degree > 2).
    def self.open_chain?(edges)
      vertex_count = {}
      edges.each do |edge|
        [edge.start.entityID, edge.end.entityID].each do |vid|
          vertex_count[vid] = (vertex_count[vid] || 0) + 1
        end
      end

      degree_1 = 0
      vertex_count.each_value do |count|
        case count
        when 1 then degree_1 += 1
        when 2 then next
        else return false  # branch — not a simple chain
        end
      end

      degree_1 == 2
    end

    # ------------------------------------------------------------------
    # Stage 2 — regroup fragmented Curves
    # ------------------------------------------------------------------

    def self.group_by_circle_geometry(edges)
      return [] if edges.empty?

      by_curve = {}
      edges.each do |e|
        next unless e.valid? && e.curve
        cid = e.curve.entityID
        by_curve[cid] ||= { edges: [], center: nil, radius: nil, normal: nil }
        by_curve[cid][:edges] << e
      end

      by_curve.each_value do |info|
        points = collect_unique_points(info[:edges])
        next if points.length < 3
        n = points.length.to_f
        cx = points.inject(0.0) { |s, p| s + p.x.to_f } / n
        cy = points.inject(0.0) { |s, p| s + p.y.to_f } / n
        cz = points.inject(0.0) { |s, p| s + p.z.to_f } / n
        info[:center] = Geom::Point3d.new(cx, cy, cz)

        dists = points.map { |p| p.distance(info[:center]).to_f }
        info[:radius] = dists.inject(0.0, :+) / dists.length

        v1 = info[:center].vector_to(points[0])
        quarter = [points.length / 4, 1].max
        v2 = info[:center].vector_to(points[quarter])
        normal = v1.cross(v2)
        info[:normal] = normal.length > 0.001 ? normal.normalize! : nil
      end

      groups = []
      curve_infos = by_curve.values.select { |info| info[:center] && info[:normal] }
      used = {}

      curve_infos.each_with_index do |info_a, i|
        next if used[i]
        group = info_a[:edges].dup
        used[i] = true

        curve_infos.each_with_index do |info_b, j|
          next if used[j]
          next unless info_a[:center].distance(info_b[:center]) < TOLERANCE
          next unless (info_a[:radius] - info_b[:radius]).abs < TOLERANCE
          dot = info_a[:normal].dot(info_b[:normal]).abs
          next unless dot > 0.99
          group.concat(info_b[:edges])
          used[j] = true
        end

        groups << group if group.length >= MIN_SEGMENTS
      end

      groups
    end

    def self.edges_form_circle?(edges)
      points = collect_unique_points(edges)
      return false if points.length < MIN_SEGMENTS

      n = points.length.to_f
      cx = points.inject(0.0) { |s, p| s + p.x.to_f } / n
      cy = points.inject(0.0) { |s, p| s + p.y.to_f } / n
      cz = points.inject(0.0) { |s, p| s + p.z.to_f } / n
      center = Geom::Point3d.new(cx, cy, cz)

      dists = points.map { |p| p.distance(center).to_f }
      avg_r = dists.inject(0.0, :+) / dists.length
      return false if avg_r < 0.01

      max_dev = dists.map { |d| (d - avg_r).abs }.max
      dist_tol = [TOLERANCE, avg_r * 0.005].max
      return false unless max_dev < dist_tol

      points_coplanar?(points, center)
    end

    def self.points_coplanar?(points, center)
      return true if points.length < 4

      v1 = center.vector_to(points[0])
      quarter = points.length / 4
      v2 = center.vector_to(points[quarter])

      normal = v1.cross(v2)
      return false if normal.length < 0.001
      normal.normalize!

      points.all? do |p|
        vec = center.vector_to(p)
        len = vec.length
        next true if len < 0.001
        (vec.dot(normal) / len).abs < 0.01
      end
    end

    def self.collect_unique_points(edges)
      seen = {}
      points = []
      edges.each do |edge|
        [edge.start, edge.end].each do |vertex|
          vid = vertex.entityID
          unless seen[vid]
            seen[vid] = true
            points << vertex.position
          end
        end
      end
      points
    end
  end
end
