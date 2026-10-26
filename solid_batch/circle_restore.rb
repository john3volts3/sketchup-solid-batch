# encoding: UTF-8
require_relative 'circle_restore/detector'
require_relative 'circle_restore/rebuilder'
require_relative 'circle_restore/volume'

module SolidBatch
  # CircleRestore — rebuilds the broken circles and arcs of a Combine All
  # result as native circles (Sketchup::ArcCurve: center inference, radius
  # and segments in Entity Info, one click selects them).
  #
  # Ported from Re-Cercle v2.0.0 (re_cercle/main.rb: restore_circles,
  # restore_chain), applied to every edge of the solid instead of the
  # selection. The engine is a copy of Re-Cercle's files under this module
  # (Solid Batch does not depend on Re-Cercle):
  #   circle_restore/detector.rb   chain detection and classification
  #   circle_restore/rebuilder.rb  planar native rebuild, weld fallback
  #   circle_restore/volume.rb     Push/Pull rebuild of cylinders and cones
  #
  # Steps (restore_in_solid):
  #   1. Find the chains among all the edges of the solid (nested groups and
  #      components included): circles of 6+ segments, arcs of
  #      min_arc_segments+ segments.
  #   2. Detect each chain again just before its rebuild (rebuilding a
  #      cylinder also rebuilds its other end), classify it, then:
  #        :planar  rebuilt natively (add_arc, same vertices),
  #        :volume  cylinder or truncated cone rebuilt natively (Push/Pull),
  #        :weld    welded into one Curve (fallback, no center inference),
  #        :native  nothing to do.
  #   3. Check each native rebuild, raise otherwise: the caller aborts the
  #      whole restoration.
  module CircleRestore
    DEFAULT_MIN_ARC_SEGMENTS = 6

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

    # Rebuild the broken circles and arcs inside a Group/ComponentInstance.
    #
    # Returns a hash: { native: N, welded: M, unwelded: K, reasons: {reason => n} }
    #   native   circles/arcs rebuilt as native circles (2 per cylinder);
    #   welded   welded into one Curve (not native), reasons counted;
    #   unwelded could not be welded.
    #
    # min_arc_segments — minimum number of segments of an arc (open chain).
    # Lower = catches shorter arcs but may produce false positives.
    def self.restore_in_solid(solid, min_arc_segments: DEFAULT_MIN_ARC_SEGMENTS)
      result = { native: 0, welded: 0, unwelded: 0, reasons: Hash.new(0) }
      return result unless solid && solid.valid?
      entities = inner_entities(solid)
      return result unless entities
      # Entities#weld (SketchUp 2020.1+) is only needed by the weld fallback
      # (Rebuilder.weld): native rebuilds also run on older versions.

      chains = Detector.find_chains(Detector.all_edges(entities))
      chains.reject! { |chain| short_arc?(chain, min_arc_segments) }
      chains.each_with_index do |found, i|
        Sketchup.status_text = "Solid Batch — Restoring circles and arcs #{i + 1}/#{chains.length}"
        restore_chain(found, result, min_arc_segments)
      end
      result
    end

    # One-line summary of a restore_in_solid result, with the weld reasons
    # when +reasons+ is true.
    def self.summary(result, reasons: false)
      parts = []
      if result[:native] > 0
        parts << "#{result[:native]} circle(s)/arc(s) rebuilt as native circles"
      end
      if result[:welded] > 0
        text = "#{result[:welded]} welded into one curve (not native)"
        if reasons
          text += ': ' + result[:reasons].map { |reason, n| "#{reason} (#{n})" }.join(', ')
        end
        parts << text
      end
      parts << "#{result[:unwelded]} could not be welded" if result[:unwelded] > 0
      parts.empty? ? 'no broken circle or arc found' : parts.join(', ')
    end

    # ------------------------------------------------------------------
    # Internals — restoration (Re-Cercle main.rb)
    # ------------------------------------------------------------------

    # Chains are detected again just before their rebuild: rebuilding a
    # cylinder also rebuilds its other end, and may recreate a shared face.
    def self.restore_chain(found, result, min_arc_segments)
      seed = found.edges.find(&:valid?)
      return unless seed # already rebuilt with its cylinder
      chain = Detector.chain_from(seed)
      return unless chain
      return if short_arc?(chain, min_arc_segments)
      info = Detector.analyse(chain)
      case info[:kind]
      when :planar
        arcs = Rebuilder.planar(chain, info[:pieces])
        check_planar(arcs, info[:pieces])
        result[:native] += 1
      when :volume
        Volume.rebuild(chain.entities, info[:volume])
        check_volume(chain.entities, info[:volume])
        result[:native] += info[:volume].loops.length
      when :weld
        case Rebuilder.weld(chain)
        when :welded
          result[:welded] += 1
          result[:reasons][info[:reason]] += 1
        when :unavailable
          result[:unwelded] += 1
        end
      end
    end

    def self.short_arc?(chain, min_arc_segments)
      !chain.closed && chain.runs.length < min_arc_segments
    end

    # Each rebuilt piece must be one native ArcCurve with its segment count.
    def self.check_planar(arcs, pieces)
      ok = arcs.each_with_index.all? do |edges, i|
        first = edges.first
        curve = (first && first.valid?) ? first.curve : nil
        curve.is_a?(Sketchup::ArcCurve) && edges.length == pieces[i].length &&
          edges.all? { |e| e.valid? && e.curve == curve }
      end
      raise 'a circle or arc could not be rebuilt as a native circle' unless ok
    end

    # Both end circles must be one native ArcCurve with the segment count.
    def self.check_volume(entities, body)
      ok = body.loops.all? do |c|
        ring = Volume.ring_edges(entities, [c.center, nil, c.normal, c.radius])
        curve = ring.empty? ? nil : ring.first.curve
        curve.is_a?(Sketchup::ArcCurve) && ring.length == c.segments &&
          ring.all? { |e| e.curve == curve }
      end
      raise 'a cylinder could not be rebuilt with native circles' unless ok
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
  end
end
