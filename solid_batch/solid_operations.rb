#-------------------------------------------------------------------------------
#
#  Solid Batch - Ruby boolean engine: copy of solid_operations.rb of Solid for
#  Maker 1.0.1 (commit 2b2a596), module SolidForMaker renamed to SolidBatch; no
#  other change. Solid Batch does not depend on Solid for Maker.
#
#  Solid for Maker ported it from Eneroth Solid Tools 3.0.0
#  (src/ene_solids/solid_operations.rb).
#  Copyright (c) 2017 Julia Christina Eneroth, (c) 2026 DRO, MIT License
#  (see LICENSE-solid-operations.txt).
#
#  Changes from Eneroth Solid Tools (made in Solid for Maker):
#  - Module Eneroth::SolidTools renamed to SolidForMaker.
#  - find_coplanar_edges: both plane tests are required (the result of the
#    first one was discarded).
#  - point_at_face: mesh computed once; centroid of the largest triangle that
#    is strictly inside the face (classify_point); nil instead of a crash when
#    all triangles are degenerate.
#  - Small parts: union, trim and intersect (and subtract through trim) run
#    with the definitions' geometry scaled up 1000 times, unless the
#    containers together exceed 10 m (with_scale, scale_up, scale_down);
#    Eneroth's code moved unchanged to union_at_scale, trim_at_scale and
#    intersect_at_scale.
#  - within?: a ray hitting an edge or a vertex (it may graze the mesh
#    without crossing it) is cast again in another direction (ray_parity,
#    RAY_DIRECTIONS); Eneroth's count is kept as the last resort.
#  - erase_faces_with_edges: faces looked up in a hash built once, each edge
#    checked once (same entities erased, about 60 % of the time of a
#    subtract with many holes before).
#  - find_corresponding_faces: normals and points of the second container's
#    faces computed once. find_faces: the reference container's inverse
#    transformation, faces and planes prepared once (probe, within_probe?)
#    instead of again for each tested point; within? keeps its interface.
#  - New: outer_shell (union, then remove_cavities: shells lying inside
#    another shell of the container are erased).
#  - wrapping_face: only the edges of the outer loop are looked at. A new
#    face cut around an existing hole (counterbore or countersink after the
#    hole) was erased by interior_hole_hack, which left the solid open.
#
#-------------------------------------------------------------------------------

module SolidBatch

# Solid Operations.
#
# For differences to native Solid Operations, see README.
module SolidOperations

  # Test if Group or Component is solid.
  #
  # If every edge in container binds an even number of faces the container is
  # considered solid. Nested containers are ignored.
  #
  # @param container [Sketchup::Group, Sketchup::ComponentInstance]
  #
  # @return [Boolean]
  def self.solid?(container)
    return false unless instance?(container)

    definition(container).entities.grep(Sketchup::Edge).all? { |e| e.faces.size.even? }
  end

  # Test if point is inside of container.
  #
  # @param point [Geom::Point3d] Point in the same coordinate system as the
  #   container, not its internal coordinate system.
  # @param container [Sketchup::Group, Sketchup::ComponentInstance]
  # @param on_boundary [Boolean] Value to return if point is on the boundary
  #   (surface) itself.
  # @param verify_solid [Boolean] Test whether container is a solid, and return
  #   false if it isn't. This test can be omitted if the container is known to
  #   be a solid.
  #
  # @return [Boolean]
  def self.within?(point, container, on_boundary = true, verify_solid = true)
    return false if verify_solid && !solid?(container)

    within_probe?(point, probe(container), on_boundary)
  end

  # Data within_probe? needs about a container, prepared once for many points:
  # inverse transformation, and faces with their planes.
  #
  # @param container [Sketchup::Group, Sketchup::ComponentInstance]
  #
  # @return [Array]
  def self.probe(container)
    faces = definition(container).entities.grep(Sketchup::Face).map { |face| [face, face.plane] }

    [container.transformation.inverse, faces]
  end
  private_class_method :probe

  # Test if point is inside of the container described by probe (see within?).
  #
  # @param point [Geom::Point3d] In the container's parent coordinates.
  # @param probe [Array] From probe.
  # @param on_boundary [Boolean]
  #
  # @return [Boolean]
  def self.within_probe?(point, probe, on_boundary)
    inverse, faces = probe
    point = point.transform(inverse)
    faces.each { |face, _plane| return on_boundary if within_face?(point, face) }

    # Cast ray from point and count how many times it intersect mesh to
    # determine what side it is on. A ray hitting an edge or a vertex can
    # graze the mesh without crossing it, so another direction is tried.
    RAY_DIRECTIONS.each do |vector|
      inside = ray_parity(point, vector, faces)
      return inside unless inside.nil?
    end

    ray_parity(point, RAY_DIRECTIONS.first, faces, true)
  end
  private_class_method :within_probe?

  # Directions tried in turn by within?, the first one being Eneroth's.
  RAY_DIRECTIONS = [
    Geom::Vector3d.new(234, 1343, 345),
    Geom::Vector3d.new(1021, -327, 761),
    Geom::Vector3d.new(-563, 419, 1187),
    Geom::Vector3d.new(877, 1103, -211),
    Geom::Vector3d.new(-149, -991, 653)
  ].freeze

  # Count the faces crossed by a ray to tell whether its start is inside.
  #
  # @param point [Geom::Point3d] In the faces' coordinate system.
  # @param vector [Geom::Vector3d]
  # @param faces [Array(Sketchup::Face, Array)] Faces with their planes.
  # @param accept_edges [Boolean] Count hits on edges and vertices (once per
  #   point) instead of giving up, as Eneroth's original test did.
  #
  # @return [Boolean, nil] nil when the ray hits an edge or a vertex and
  #   accept_edges is false.
  def self.ray_parity(point, vector, faces, accept_edges = false)
    ray = [point, vector]
    intersections = []

    faces.each do |face, plane|
      intersection = Geom.intersect_line_plane(ray, plane)
      next unless intersection
      next if intersection == point

      # Check that intersection is on ray, and not in the other direction along
      # the line.
      next unless (intersection - point).samedirection?(vector)

      pc = face.classify_point(intersection)
      if [Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex].include?(pc)
        return nil unless accept_edges
      elsif pc != Sketchup::Face::PointInside
        next
      end

      intersections << intersection
    end

    # Ray may have hit right on an edge, intersecting two adjacent faces, or
    # even a vertex and intersected many more.
    # Remove duplicated points.
    intersections = uniq_points(intersections)

    intersections.size.odd?
  end
  private_class_method :ray_parity

  # Unite one container with another.
  #
  # @param target [Sketchup::Group, Sketchup::ComponentInstance]
  # @param modifier [Sketchup::Group, Sketchup::ComponentInstance]
  #
  # @return [Boolean, nil] `nil` denotes failure in algorithm. `false` denotes one
  #   of the containers wasn't a solid.
  def self.union_at_scale(target, modifier)
    return false unless solid?(target) && solid?(modifier)
    target.make_unique if target.is_a?(Sketchup::Group)

    # Use a temporary copy of modifier instead of altering original.
    temp_group = target.parent.entities.add_group
    merge_into(temp_group, modifier)
    modifier = temp_group

    target_ents = definition(target).entities
    modifier_ents = definition(modifier).entities

    add_intersection_edges(target, modifier)

    # Keep references to edges binding overlapping faces so they can later be
    # removed and the faces merged. Use vertices as references as the edges are
    # deleted and replaced in merge_into.
    overlapping_edges = find_corresponding_faces(target, modifier, nil)[0].flat_map(&:edges).map(&:vertices)

    # Remove faces in both containers that are inside the other one's solid.
    # Remove faces that exists in both containers and have opposite orientation.
    erase1 = find_faces(target, modifier, true, false)
    erase2 = find_faces(modifier, target, true, false)
    c_faces1, c_faces2 = find_corresponding_faces(target, modifier, false)
    erase1.concat(c_faces1)
    erase2.concat(c_faces2)
    erase_faces_with_edges(erase1)
    erase_faces_with_edges(erase2)

    merge_into(target, modifier)

    # Merge faces between target and modifier by removing co-planar edges around
    # their overlapping faces.
    overlapping_edges.select! { |vs| vs.all?(&:valid?) }
    overlapping_edges.map! { |vs| vs[0].common_edge(vs[1]) }.compact!
    target_ents.erase_entities(find_coplanar_edges(overlapping_edges))

    weld_hack(target_ents)

    solid?(target) ? true : nil
  end

  # Subtract one container from another.
  #
  # @param target [Sketchup::Group, Sketchup::ComponentInstance]
  # @param modifier [Sketchup::Group, Sketchup::ComponentInstance]
  #
  # @return [Boolean, nil] `nil` denotes failure in algorithm. `false` denotes one
  #   of the containers wasn't a solid.
  def self.subtract(target, modifier)
    status = trim(target, modifier)
    return status unless status
    modifier.erase!

    true
  end

  # Trim one container from another.
  #
  # @param target [Sketchup::Group, Sketchup::ComponentInstance]
  # @param modifier [Sketchup::Group, Sketchup::ComponentInstance]
  #
  # @return [Boolean, nil] `nil` denotes failure in algorithm. `false` denotes one
  #   of the containers wasn't a solid.
  def self.trim_at_scale(target, modifier)
    return false unless solid?(target) && solid?(modifier)
    target.make_unique if target.is_a?(Sketchup::Group)

    # Use a temporary copy of modifier instead of altering original.
    temp_group = target.parent.entities.add_group
    merge_into(temp_group, modifier, true)
    modifier = temp_group

    target_ents = definition(target).entities
    modifier_ents = definition(modifier).entities

    add_intersection_edges(target, modifier)

    # Keep references to edges binding overlapping faces so they can later be
    # removed and the faces merged. Use vertices as references as the edges are
    # deleted and replaced in merge_into.
    overlapping_edges = find_corresponding_faces(target, modifier, nil)[0].flat_map(&:edges).map(&:vertices)

    # Remove faces in target that are inside the modifier and faces in
    # modifier that are outside target.
    # Remove faces that exists in both containers and have opposite orientation.
    erase1 = find_faces(target, modifier, true, false)
    erase2 = find_faces(modifier, target, false, false)
    c_faces1, c_faces2 = find_corresponding_faces(target, modifier, true)
    erase1.concat(c_faces1)
    erase2.concat(c_faces2)
    erase_faces_with_edges(erase1)
    erase_faces_with_edges(erase2)

    modifier_ents.each { |f| f.reverse! if f.is_a? Sketchup::Face }
    merge_into(target, modifier)

    # Merge faces between target and modifier by removing co-planar edges around
    # their overlapping faces.
    overlapping_edges.select! { |vs| vs.all?(&:valid?) }
    overlapping_edges.map! { |vs| vs[0].common_edge(vs[1]) }.compact!
    target_ents.erase_entities(find_coplanar_edges(overlapping_edges))

    weld_hack(target_ents)

    solid?(target) ? true : nil
  end

  # Intersect one container with another.
  #
  # @param target [Sketchup::Group, Sketchup::ComponentInstance]
  # @param modifier [Sketchup::Group, Sketchup::ComponentInstance]
  #
  # @return [Boolean, nil] `nil` denotes failure in algorithm. `false` denotes one
  #   of the containers wasn't a solid.
  def self.intersect_at_scale(target, modifier)
    return false unless solid?(target) && solid?(modifier)
    target.make_unique if target.is_a?(Sketchup::Group)

    # Use a temporary copy of modifier instead of altering original.
    temp_group = target.parent.entities.add_group
    merge_into(temp_group, modifier)
    modifier = temp_group

    target_ents = definition(target).entities
    modifier_ents = definition(modifier).entities

    add_intersection_edges(target, modifier)

    # Keep references to edges binding overlapping faces so they can later be
    # removed and the faces merged. Use vertices as references as the edges are
    # deleted and replaced in merge_into.
    overlapping_edges = find_corresponding_faces(target, modifier, nil)[0].flat_map(&:edges).map(&:vertices)

    # Remove faces in both containers that are outside the other one's solid.
    # Remove faces that exists in both containers and have opposite orientation.
    erase1 = find_faces(target, modifier, false, false)
    erase2 = find_faces(modifier, target, false, false)
    c_faces1, c_faces2 = find_corresponding_faces(target, modifier, false)
    erase1.concat(c_faces1)
    erase2.concat(c_faces2)
    erase_faces_with_edges(erase1)
    erase_faces_with_edges(erase2)

    merge_into(target, modifier)

    # Merge faces between target and modifier by removing co-planar edges around
    # their overlapping faces.
    overlapping_edges.select! { |vs| vs.all?(&:valid?) }
    overlapping_edges.map! { |vs| vs[0].common_edge(vs[1]) }.compact!
    target_ents.erase_entities(find_coplanar_edges(overlapping_edges))

    weld_hack(target_ents)

    solid?(target) ? true : nil
  end

  private_class_method :union_at_scale, :trim_at_scale, :intersect_at_scale

  # Factor the geometry is scaled up by during an operation (small parts).
  SCALE_FACTOR = 1000

  # Containers larger than this, together, are not scaled up.
  SCALE_LIMIT = 10.m

  # Unite one container with another.
  #
  # @param target [Sketchup::Group, Sketchup::ComponentInstance]
  # @param modifier [Sketchup::Group, Sketchup::ComponentInstance]
  #
  # @return [Boolean, nil] `nil` denotes failure in algorithm. `false` denotes one
  #   of the containers wasn't a solid.
  def self.union(target, modifier)
    with_scale(target, modifier) { union_at_scale(target, modifier) }
  end

  # Trim one container from another.
  #
  # @param target [Sketchup::Group, Sketchup::ComponentInstance]
  # @param modifier [Sketchup::Group, Sketchup::ComponentInstance]
  #
  # @return [Boolean, nil] `nil` denotes failure in algorithm. `false` denotes one
  #   of the containers wasn't a solid.
  def self.trim(target, modifier)
    with_scale(target, modifier) { trim_at_scale(target, modifier) }
  end

  # Intersect one container with another.
  #
  # @param target [Sketchup::Group, Sketchup::ComponentInstance]
  # @param modifier [Sketchup::Group, Sketchup::ComponentInstance]
  #
  # @return [Boolean, nil] `nil` denotes failure in algorithm. `false` denotes one
  #   of the containers wasn't a solid.
  def self.intersect(target, modifier)
    with_scale(target, modifier) { intersect_at_scale(target, modifier) }
  end

  # Unite one container with another and keep only the outer shell.
  #
  # @param target [Sketchup::Group, Sketchup::ComponentInstance]
  # @param modifier [Sketchup::Group, Sketchup::ComponentInstance]
  #
  # @return [Boolean, nil] `nil` denotes failure in algorithm. `false` denotes one
  #   of the containers wasn't a solid.
  def self.outer_shell(target, modifier)
    status = union(target, modifier)
    return status unless status
    remove_cavities(target)

    solid?(target) ? true : nil
  end

  # Remove the shells of a container that lie inside another of its shells:
  # closed cavities, and solids enclosed in the volume (e.g. floating in a
  # cavity). Separate pieces, none inside another, are all kept.
  #
  # A shell is a set of faces connected by their edges. Whether a shell is
  # inside another is tested on the original shells, independently of the
  # faces' orientation, then the inner shells are erased at once.
  #
  # @param container [Sketchup::Group, Sketchup::ComponentInstance]
  #
  # @return [Integer, false] Number of shells removed, `false` if the container
  #   isn't a solid.
  def self.remove_cavities(container)
    return false unless solid?(container)

    all = shells(definition(container).entities)
    return 0 if all.size < 2

    identity = Geom::Transformation.new
    probes = all.map { |shell| [identity, shell.map { |face| [face, face.plane] }] }
    inner = all.each_with_index.select do |shell, i|
      point = nil
      shell.each { |face| break if (point = point_at_face(face)) }
      next false unless point
      probes.each_with_index.any? { |probe, j| j != i && within_probe?(point, probe, false) }
    end
    erase_faces_with_edges(inner.flat_map(&:first))

    inner.size
  end

  # Split the faces of entities into shells: sets of faces connected by their
  # edges.
  #
  # @param entities [Sketchup::Entities]
  #
  # @return [Array<Array<Sketchup::Face>>]
  def self.shells(entities)
    remaining = {}
    entities.grep(Sketchup::Face).each { |face| remaining[face] = true }
    shells = []
    until remaining.empty?
      start = remaining.keys.first
      remaining.delete(start)
      shell = [start]
      queue = [start]
      until queue.empty?
        queue.pop.edges.each do |edge|
          edge.faces.each do |face|
            next unless remaining.delete(face)
            shell << face
            queue << face
          end
        end
      end
      shells << shell
    end

    shells
  end
  private_class_method :shells

  #-----------------------------------------------------------------------------

  # Run an operation with the geometry scaled up by SCALE_FACTOR, unless the
  # containers together are larger than SCALE_LIMIT.
  #
  # SketchUp merges points closer than 0.001", which makes details under about
  # 1 mm fail. The engine works in the definitions' coordinates, so the geometry
  # inside the definitions is scaled, not only the instances.
  #
  # @param target [Sketchup::Group, Sketchup::ComponentInstance]
  # @param modifier [Sketchup::Group, Sketchup::ComponentInstance]
  #
  # @yieldreturn [Boolean, nil] Status of the operation.
  #
  # @return [Boolean, nil] `nil` also when the target is no longer a solid
  #   once scaled back down.
  def self.with_scale(target, modifier)
    return false unless solid?(target) && solid?(modifier)

    bounds = Geom::BoundingBox.new
    bounds.add(target.bounds)
    bounds.add(modifier.bounds)
    return yield if [bounds.width, bounds.height, bounds.depth].max > SCALE_LIMIT

    scaling = scale_up([target, modifier], bounds.center, SCALE_FACTOR)
    status = yield
    scale_down(scaling, target, modifier)
    return status unless status

    solid?(target) ? true : nil
  end
  private_class_method :with_scale

  # Scale the geometry of the instances' definitions about their origin and
  # compensate the instances' transformations, so that the instances are scaled
  # about center (relative placement kept).
  #
  # Other instances of these definitions are scaled too until scale_down.
  #
  # @param instances [Array<Sketchup::Group, Sketchup::ComponentInstance>]
  # @param center [Geom::Point3d]
  # @param factor [Numeric]
  #
  # @return [Hash] What scale_down needs.
  def self.scale_up(instances, center, factor)
    world = Geom::Transformation.scaling(center, factor)
    local = Geom::Transformation.scaling(ORIGIN, factor)

    definitions = instances.map { |i| definition(i) }.uniq
    definitions.each { |d| d.entities.transform_entities(local, d.entities.to_a) }
    instances.each { |i| i.transformation = world * i.transformation * local.inverse }

    { :world => world, :local => local, :definitions => definitions }
  end
  private_class_method :scale_up

  # Undo scale_up: scale back down every scaled definition that still exists
  # (the modifier may be erased while other instances of its definition remain)
  # and the target's current definition (a new one when a group is made
  # unique), each once, and restore the transformations of the instances that
  # remain.
  #
  # @param scaling [Hash] From scale_up.
  # @param target [Sketchup::Group, Sketchup::ComponentInstance]
  # @param modifier [Sketchup::Group, Sketchup::ComponentInstance]
  #
  # @return [Void]
  def self.scale_down(scaling, target, modifier)
    definitions = scaling[:definitions].select(&:valid?)
    if target.valid?
      current = definition(target)
      definitions << current unless definitions.include?(current)
    end
    local_inverse = scaling[:local].inverse
    definitions.each { |d| d.entities.transform_entities(local_inverse, d.entities.to_a) }

    [target, modifier].each do |instance|
      next unless instance.valid?
      instance.transformation = scaling[:world].inverse * instance.transformation * scaling[:local]
    end

    nil
  end
  private_class_method :scale_down

  # Get definition used by instance.
  # For Versions before SU 2015 there was no Group#definition method.
  #
  # @param instance [Sketchup::ComponentInstance, Sketchup::Group, Sketchup::Image]
  #
  # @return [Sketchup::ComponentDefinition]
  def self.definition(instance)
    if instance.is_a?(Sketchup::ComponentInstance) ||
       (Sketchup.version.to_i >= 15 && instance.is_a?(Sketchup::Group))
      instance.definition
    else
      instance.model.definitions.find { |d| d.instances.include?(instance) }
    end
  end
  private_class_method :definition

  # Test if entity is either group or component instance.
  #
  # Since a group is a special type of component groups and component instances
  # can often be treated the same.
  #
  # @example
  #   # Show Information of the Selected Instance
  #   entity = Sketchup.active_model.selection.first
  #   if !entity
  #     puts "Selection is empty."
  #   elsif SkippyLib::LEntity.instance?(entity)
  #     puts "Instance's transformation is: #{entity.transformation}."
  #     puts "Instance's definition is: #{entity.definition}."
  #   else
  #     puts "Entity is not a group or component instance."
  #   end
  #
  # @param entity [Sketchup::Entity]
  #
  # @return [Boolean]
  def self.instance?(entity)
    entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
  end
  private_class_method :instance?

  # Remove duplicate points from array.
  #
  # Ruby's own `Array#uniq` don't remove duplicated points as they are regarded
  # separate objects, based on #eql? and #hash. Without modifying the SketchUp
  # API classes this method can remove duplicated points based on == comparison.
  #
  # @param points [Array<Geom::Point3d>]
  #
  # @return [Array<Geom::Point3d>]
  def self.uniq_points(points)
    points.reduce([]) { |a, p| a.any? { |p1| p1 == p } ? a : a << p }
  end
  private_class_method :uniq_points

  # Test if point is inside of a face.
  #
  # @param point [Geom::Point3d]
  # @param face [Sketchup::Face]
  # @param on_boundary [Boolean] Value to return if point is on the boundary
  #   (edge/vertex) of face.
  #
  # @return [Boolean]
  def self.within_face?(point, face, on_boundary = true)
    pc = face.classify_point(point)
    return on_boundary if [Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex].include?(pc)

    pc == Sketchup::Face::PointInside
  end
  private_class_method :within_face?

  # Intersect containers and place intersection edges in both containers.
  #
  # @param container1 [Sketchup::Group, Sketchup::ComponentInstance]
  # @param container2 [Sketchup::Group, Sketchup::ComponentInstance]
  #
  # @return [Void]
  def self.add_intersection_edges(container1, container2)
    entities1 = definition(container1).entities
    entities2 = definition(container2).entities

    # Intersect twice as the intersect method sometimes fails in getting edges
    # where faces overlap.
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

    interior_hole_hack(merge_into(container1, temp_group, true).grep(Sketchup::Edge))
    interior_hole_hack(merge_into(container2, temp_group).grep(Sketchup::Edge))

    nil
  end
  private_class_method :add_intersection_edges

  # Find a point well inside a face.
  #
  # The centroids of the face's mesh triangles are tried from the largest
  # triangle to the smallest, and the first one strictly inside the face is
  # returned. Sliver triangles, common after intersecting, would otherwise give
  # a point almost on the face boundary.
  #
  # @param face [Sketchup::Face]
  #
  # @return [Geom::Point3d, nil] nil is returned for zero area faces, or when
  #   no point strictly inside the face is found.
  def self.point_at_face(face)
    # Sometimes invalid faces gets created when intersecting.
    # These are removed when validity check run.
    return if face.area.zero?

    # PolygonMesh.polygon_points in rare situations return points on a line,
    # which would lead to a point on the edge boundary being returned rather
    # than one within face.
    mesh = face.mesh
    triangles = (1..mesh.count_polygons).map { |i| mesh.polygon_points_at(i) }
    triangles.reject! { |points| points.size < 3 || points[0].on_line?(points[1], points[2]) }
    triangles = triangles.sort_by { |points| -triangle_area(points) }

    triangles.each do |points|
      point = Geom::Point3d.new(
        (points[0].x + points[1].x + points[2].x) / 3.0,
        (points[0].y + points[1].y + points[2].y) / 3.0,
        (points[0].z + points[1].z + points[2].z) / 3.0
      )
      return point if face.classify_point(point) == Sketchup::Face::PointInside
    end

    nil
  end
  private_class_method :point_at_face

  # Area of the triangle formed by the first three points.
  #
  # @param points [Array<Geom::Point3d>]
  #
  # @return [Float]
  def self.triangle_area(points)
    (points[1] - points[0]).cross(points[2] - points[0]).length.to_f / 2
  end
  private_class_method :triangle_area

  # Find faces based on them being interior or exterior to reference container.
  #
  # @param scope [Sketchup::Group, Sketchup::ComponentInstance]
  # @param reference [Sketchup::Group, Sketchup::ComponentInstance]
  # @param interior [Boolean] Whether faces interior to reference or faces exterior
  #   to reference should be selected.
  # @param on_surface [Boolean] I can't remember what this does, besides giving
  #   me a headache.
  #
  # @return [Array<Sketchup::Face>]
  def self.find_faces(scope, reference, interior, on_surface)
    # Reference data prepared once for all the faces.
    reference_probe = probe(reference)
    definition(scope).entities.select do |f|
      next unless f.is_a?(Sketchup::Face)
      point = point_at_face(f)
      next unless point
      point.transform!(scope.transformation)
      next if interior != within_probe?(point, reference_probe, interior == on_surface)

      true
    end
  end
  private_class_method :find_faces

  # Find pairs of faces duplicated between containers.
  #
  # @param container1 [Sketchup::Group, Sketchup::ComponentInstance]
  # @param container2 [Sketchup::Group, Sketchup::ComponentInstance]
  # @param orientation [Boolean, nil] True only returns faces with same
  #   orientation, false only returns faces with opposite orientation and nil
  #   skips orientation check.
  #
  # @return [Array(Array<Sketchup::Face>, Array<Sketchup::Face>)] First array is
  #   from container1, second one is from container2.
  def self.find_corresponding_faces(container1, container2, orientation)
    faces = [[], []]

    # Normals and points of container2's faces computed once, not again for
    # each face of container1.
    transformation1 = container1.transformation
    transformation2 = container2.transformation
    faces2 = definition(container2).entities.grep(Sketchup::Face).map do |face2|
      [
        face2,
        transform_as_normal(face2.normal, transformation2),
        face2.vertices.map { |v| v.position.transform(transformation2) }
      ]
    end

    definition(container1).entities.grep(Sketchup::Face) do |face1|
      normal1 = transform_as_normal(face1.normal, transformation1)
      points1 = face1.vertices.map { |v| v.position.transform(transformation1) }
      faces2.each do |face2, normal2, points2|
        next unless normal1.parallel?(normal2)
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
  private_class_method :find_corresponding_faces

  # Remove all edges binding less than 2 edges.
  #
  # @param entities [Sketchup::Entities]
  #
  # @return [Void]
  def self.purge_edges(entities)
    # REVIEW: Why 2 faces? Why not purge free standing edges only?
    # Are there cases where edges are left binding a single face?

    to_purge = entities.grep(Sketchup::Edge).select { |e| e.faces.size < 2 }
    entities.erase_entities(to_purge)

    nil
  end
  private_class_method :purge_edges

  # Move content of one container into another.
  #
  # Attributes of the to_move container, such as material and layer are not
  # carried over with its content.
  # Requires containers to be in the same drawing context.
  #
  # @param destination [Sketchup::Group, Sketchup::ComponentInstance]
  # @param to_move [Sketchup::Group, Sketchup::ComponentInstance]
  # @param keep_original [Boolean]
  #
  # @return [Array<Entity>]
  def self.merge_into(destination, to_move, keep_original = false)
    tr = destination.transformation.inverse * to_move.transformation
    entities = definition(destination).entities
    temp = entities.add_instance(definition(to_move), tr)
    to_move.erase! unless keep_original

    temp.explode
  end
  private_class_method :merge_into

  # Find coplanar edges with same material and layers on both sides.
  #
  # Stray edges included.
  #
  # @param entities [Sketchup::Entities]
  #
  # @return [Array<Sketchup::Edge>]
  def self.find_coplanar_edges(entities)
    entities.grep(Sketchup::Edge).select do |e|
      next unless e.faces.size == 2
      next unless e.faces[0].material == e.faces[1].material
      next unless e.faces[0].layer == e.faces[1].layer

      # This check gives false positive on very small angles.
      next unless e.faces[0].normal.parallel?(e.faces[1].normal)

      # This check gives false positive if one face is very narrow, and all its
      # points are almost on the plane of the other face, despite a small angle
      # in between.
      # Compare points of both faces to the other face's plane to reduce risk of
      # false positive. Both tests must pass.
      first_on_second = e.faces[0].vertices.all? do |v|
        e.faces[1].classify_point(v.position) != Sketchup::Face::PointNotOnPlane
      end
      second_on_first = e.faces[1].vertices.all? do |v|
        e.faces[0].classify_point(v.position) != Sketchup::Face::PointNotOnPlane
      end
      first_on_second && second_on_first
    end
  end
  private_class_method :find_coplanar_edges

  # Weld overlapping edges.
  #
  # Sometimes SketchUp fails to weld these.
  #
  # @param entities [Sketchup::Entities]
  #
  # @return [Void]
  def self.weld_hack(entities)
    return if solid?(entities.parent)

    temp_group = entities.add_group
    naked_edges(entities).each do |e|
      temp_group.entities.add_line(e.start, e.end)
    end
    temp_group.explode

    nil
  end
  private_class_method :weld_hack

  # Find edges only binding one face.
  #
  # @param entities [Sketchup::Entities]
  #
  # @return [Array<Sketchup::Edge>]
  def self.naked_edges(entities)
    entities.grep(Sketchup::Edge).select { |e| e.faces.size == 1 }
  end
  private_class_method :naked_edges

  # Erase faces along with their binding edges that doesn't bind any other
  # faces.
  #
  # @param faces [Array<Face>]
  #
  # @return [Void]
  def self.erase_faces_with_edges(faces)
    return if faces.empty?
    # Look faces up in a hash built once: Array#- rebuilt it for every edge.
    erased = {}
    faces.each { |f| erased[f] = true }
    edges = faces.flat_map(&:edges).uniq.select { |e| e.faces.all? { |f| erased[f] } }
    erase = faces + edges
    erase.first.parent.entities.erase_entities(erase)

    nil
  end

  # Find mesh geometry (edges and faces) in Entities collection.
  #
  # @param entities [Sketchup::Entities, Array<Entity>]
  #
  # @return [Array<Sketchup::Face, Sketchup::Edge>]
  def self.find_mesh_geometry(entities)
    entities.select { |e| [Sketchup::Face, Sketchup::Edge].include?(e.class) }
  end
  private_class_method :find_mesh_geometry

  # Return new vector transformed as a normal.
  #
  # Transforming a normal vector as a ordinary vector can give it a faulty
  # direction if the transformation is non-uniformly scaled or sheared. This
  # method assures the vector stays perpendicular to its perpendicular plane
  # when a transformation is applied.
  #
  # @param normal [Geom::Vector3d]
  # @param transformation [Geom::Transformation]
  #
  # @example
  #   # transform_as_normal VS native #transform
  #   skewed_tr = SkippyLib::LGeom::LTransformation.create_from_axes(
  #     ORIGIN,
  #     Geom::Vector3d.new(1, 0.3, 0),
  #     Geom::Vector3d.new(0, 1, 0),
  #     Geom::Vector3d.new(0, 0, 1)
  #   )
  #   normal = Y_AXIS
  #   puts "Transformed as vector: #{normal.transform(skewed_tr)}"
  #   puts "Transformed as normal: #{SkippyLib::LGeom::LVector3d.transform_as_normal(normal, skewed_tr)}"
  #
  # @return [Geom::Vector3d]
  def self.transform_as_normal(normal, transformation)
    tr = transpose(transformation).inverse

    normal.transform(tr).normalize
  end
  private_class_method :transform_as_normal

  # Transpose of 3X3 matrix (drop translation).
  #
  # @param transformation [Geom::Transformation]
  #
  # @return [Geom::Transformation]
  def self.transpose(transformation)
    a = transformation.to_a

    Geom::Transformation.new([
      a[0], a[4], a[8],  0,
      a[1], a[5], a[9],  0,
      a[2], a[6], a[10], 0,
      0,    0,    0,     a[15]
    ])
  end
  private_class_method :transpose

  # Form interior holes in faces from edges if possible.
  #
  # @param edges [Array<Edge>]
  #
  # @return [Void]
  def self.interior_hole_hack(edges)
    return if edges.empty?

    entities = edges.first.parent.entities
    old_entities = entities.to_a
    edges.each(&:find_faces)
    new_faces = entities.to_a - old_entities

    # Newly formed faces forming holes inside of other faces need to be kept for
    # the solid volume to be remained defined.
    # Some newly formed faces however are located where there was no face before,
    # and must thus be removed for the original volume to remain.
    # Even some new faces formed inside of other faces may be needed to be
    # removed, if there are already faces around the hole defining a
    # recess/bump.
    entities.erase_entities(new_faces.select { |f| !wrapping_face(f) || f.edges.any? { |e| e.faces.size != 2 } })

    nil
  end
  private_class_method :interior_hole_hack

  # Find the exterior face that a face forms a hole within, or nil if face isn't
  # inside another face.
  #
  # @param face [SketchUp::Face]
  #
  # @example
  #   ents = Sketchup.active_model.active_entities
  #   ents.add_face(
  #     Geom::Point3d.new(0,   0,   0),
  #     Geom::Point3d.new(0,   1.m, 0),
  #     Geom::Point3d.new(1.m, 1.m, 0),
  #     Geom::Point3d.new(1.m, 0,   0)
  #   )
  #   inner_face = ents.add_face(
  #     Geom::Point3d.new(0.25.m, 0.25.m, 0),
  #     Geom::Point3d.new(0.25.m, 0.75.m, 0),
  #     Geom::Point3d.new(0.75.m, 0.75.m, 0),
  #     Geom::Point3d.new(0.75.m, 0.25.m, 0)
  #   )
  #   outer_face = SkippyLib::LFace.wrapping_face(inner_face)
  #
  # Only the edges of the outer loop are looked at: a face cut around a hole
  # that already exists (a counterbore after the hole) has that hole as an
  # inner loop, whose edges are bound to the walls of the hole.
  #
  # @return [Sketchup::Face, nil]
  def self.wrapping_face(face)
    (face.outer_loop.edges.map(&:faces).inject(:&) - [face]).first
  end
  private_class_method :wrapping_face

end
end
