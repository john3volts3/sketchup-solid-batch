# encoding: UTF-8
# Ported from Re-Cercle v2.0.0 (re_cercle/rebuilder.rb), unchanged except the
# namespace: SolidBatch::CircleRestore instead of ReCercle. Solid Batch does
# not depend on Re-Cercle.
#
# Rebuild of planar chains as native arcs/circles, and weld fallback.
#
# Planar rebuild (every face touching the chain lies in its plane):
#   1. Snapshot the faces touching the edges to erase: normal, materials,
#      tag, a probe point inside the face next to the chain, inner loops
#      (other holes).
#   2. Erase the chain edges (a host face around the circle closes itself),
#      then add_arc for each piece: same center, normal, radius, segment
#      count and phase, so every vertex comes back at the same place.
#      An arc whose ends touch existing edges stays native (tested).
#   3. find_faces on each new arc and on each former hole.
#   4. New faces containing a probe point get the former properties; the
#      others fill a former void (hole, empty circle) and are erased.
# The result is one native ArcCurve per piece: center inference, Entity
# Info.
#
# Weld fallback: Entities#weld (SketchUp 2020.1+) makes one plain Curve
# (one click selects it, but no center inference).

module SolidBatch
  module CircleRestore
    module Rebuilder
      # Rebuilds +pieces+ (arrays of Detector::Run) of +chain+. Returns the
      # new arcs (arrays of edges).
      def self.planar(chain, pieces)
        ents = chain.entities
        erase = pieces.flatten.flat_map(&:edges)
        erase_set = {}
        erase.each { |e| erase_set[e] = true }
        faces = erase.flat_map(&:faces).uniq
        snaps = faces.map { |f| snapshot_face(f, erase_set) }
        holes = snaps.flat_map { |s| s[:holes] }
        existing = {}
        (faces + holes.flatten.flat_map(&:faces)).each { |f| existing[f.entityID] = true }
        ref = erase.first
        props = [ref.layer, ref.soft?, ref.smooth?, ref.hidden?, ref.material]
        plans = pieces.map do |runs|
          full = chain.closed && runs.length == chain.runs.length
          sweep = full ? 2 * Math::PI : Detector.sweep_of(chain, runs)
          [runs.first.a.position.clone, sweep, runs.length]
        end

        ents.erase_entities(erase)
        arcs = plans.map do |start, sweep, n|
          xaxis = chain.center.vector_to(start)
          xaxis -= Detector.scale(chain.normal, xaxis.dot(chain.normal)) # exactly in the plane
          xaxis.normalize!
          ents.add_arc(chain.center, xaxis, chain.normal, chain.radius, 0, sweep, n)
        end
        new_edges = arcs.flatten
        new_edges.each do |e|
          next unless e.valid?
          e.layer, e.soft, e.smooth, e.hidden, e.material = props
        end
        arcs.each do |edges|
          e = edges.find(&:valid?)
          e.find_faces if e
        end
        # A face rebuilt over a former hole may cover its edges without being
        # split: find_faces on one hole edge splits it (as in Circle
        # Re-Segment). Skipped when a face has no probe point: the face
        # filling the hole could not be erased.
        blind = snaps.any? { |s| s[:probe].nil? }
        (blind ? [] : holes).each do |edges|
          e = edges.find(&:valid?)
          e.find_faces if e
        end
        candidates = (new_edges + holes.flatten).select(&:valid?).flat_map(&:faces).uniq
        repair_faces(candidates, snaps, existing)
        arcs
      end

      # Welds the chain into one Curve. Returns :welded, :unchanged (already
      # one curve) or :unavailable (SketchUp older than 2020.1).
      def self.weld(chain)
        edges = chain.edges.select(&:valid?)
        return :unchanged if edges.empty?
        curve = edges.first.curve
        if curve && curve.count_edges == edges.length && edges.all? { |e| e.curve == curve }
          return :unchanged
        end
        return :unavailable unless chain.entities.respond_to?(:weld)
        chain.entities.weld(edges)
        :welded
      end

      def self.snapshot_face(face, erase_set)
        holes = face.loops.reject(&:outer?).reject { |lp| lp.edges.any? { |e| erase_set[e] } }
        {
          normal: face.normal.clone, material: face.material,
          back_material: face.back_material, layer: face.layer,
          probe: probe_point(face, erase_set),
          holes: holes.map(&:edges)
        }
      end

      # Point inside +face+, close to one of the erased edges (the rebuilt arc
      # has the same chords, so the point stays on the same side).
      def self.probe_point(face, erase_set)
        face.edges.select { |e| erase_set[e] }.each do |e|
          p1 = e.start.position
          p2 = e.end.position
          side = face.normal.cross(p1.vector_to(p2))
          next if side.length.to_f < 1e-12
          side.normalize!
          mid = Geom.linear_combination(0.5, p1, 0.5, p2)
          len = p1.distance(p2).to_f
          [0.05, 0.01, 0.002].each do |k|
            d = [len * k, Detector::BASE_TOL * 2].max
            [1, -1].each do |s|
              pt = mid + Detector.scale(side, d * s)
              return pt if face.classify_point(pt) == Sketchup::Face::PointInside
            end
          end
        end
        nil
      end

      # New faces containing a probe point get the former face properties; the
      # others are erased, unless a face had no probe point (nothing erased).
      def self.repair_faces(candidates, snaps, existing)
        blind = snaps.any? { |s| s[:probe].nil? }
        candidates.each do |f|
          next if !f.valid? || existing[f.entityID]
          snap = snaps.find do |s|
            s[:probe] && f.classify_point(s[:probe]) == Sketchup::Face::PointInside
          end
          if snap
            f.reverse! if f.normal.dot(snap[:normal]) < 0
            f.material = snap[:material]
            f.back_material = snap[:back_material]
            f.layer = snap[:layer]
          elsif !blind
            f.erase!
          end
        end
      end
    end
  end
end
