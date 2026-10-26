# encoding: UTF-8
#-------------------------------------------------------------------------------
#
#  Solid Batch - automatic tests (development tool, not shipped in the .rbz).
#
#  Fully automatic, from PowerShell (SketchUp closed):
#    tools/tests/run_tests.ps1            (SketchUp 2021, then Make 2017)
#  It deploys the plugin, starts each SketchUp with -RubyStartup on this file,
#  waits for the report and closes that SketchUp.
#
#  By hand, in the Ruby console of SketchUp:
#    load "<project>/tools/tests/run_tests.rb"
#
#  The plugin files installed in SketchUp are reloaded first. The tests run
#  in a new model (the current one is never changed). Message boxes and input
#  boxes are recorded instead of shown; nothing is written in the SketchUp
#  settings of this PC (Sketchup.write_default is recorded too) and the
#  options of the plugin are forced for the tests. Steps are chained with
#  timers, so that the deferred work of SketchUp runs between them.
#
#  Report: Ruby console and results/latest-<SketchUp major version>.txt.
#
#-------------------------------------------------------------------------------

verbose = $VERBOSE
$VERBOSE = nil

module SolidBatch
  module Tests
    path = File.expand_path(__FILE__)
    path.force_encoding('UTF-8') if path.respond_to?(:force_encoding)
    TESTS_DIR = File.dirname(path)
    PROJECT_DIR = File.expand_path('../..', TESTS_DIR)
    RESULTS_DIR = File.join(TESTS_DIR, 'results')
    STEP_DELAY = 0.5
    LOG = '[Solid Batch tests]'.freeze

    # Options of the plugin forced during the tests, whatever the settings of
    # this PC (registry SolidBatch).
    OPTIONS = [:subtract_color, :auto_repair_large, :large_threshold, :min_arc_segments].freeze
    SUBTRACT_RGB = [255, 0, 0].freeze

    # One test: checks, notes and the phases still to run.
    class Case
      attr_reader :name, :checks, :notes, :phases
      attr_accessor :skipped

      def initialize(name)
        @name = name
        @checks = []
        @notes = []
        @phases = []
        @skipped = nil
      end

      # Runs the block after a delay, once the deferred work of SketchUp is
      # done.
      def later(&block)
        @phases << block
      end

      def check(ok, label, detail = nil)
        @checks << [ok ? true : false, label, detail]
        ok
      end

      def note(text)
        @notes << text
      end

      def skip(reason)
        @skipped = reason
      end

      def failed?
        @checks.any? { |c| !c[0] }
      end
    end

    # -------------------------------------------------------------------
    # Runner
    # -------------------------------------------------------------------

    def self.run
      @started = Time.now
      @cases = []
      @messages = []
      @status = []
      @inputs = []
      @prompts = []
      @writes = []
      @tests = []
      define_tests
      reload_plugin
      hook
      force_default_options
      prepare_model(0) { next_test }
    rescue => e
      fatal(e)
    end

    def self.messages
      @messages
    end

    def self.status
      @status
    end

    # Answers of the next UI.inputbox calls (false = Cancel).
    def self.inputs
      @inputs
    end

    # Arguments of the UI.inputbox calls.
    def self.prompts
      @prompts
    end

    # Sketchup.write_default calls: [section, key, value].
    def self.writes
      @writes
    end

    def self.schedule(&block)
      timer = UI.start_timer(STEP_DELAY, false) do
        UI.stop_timer(timer)
        begin
          block.call
        rescue => e
          fatal(e)
        end
      end
    end

    def self.test(name, &block)
      @tests << [name, block]
    end

    def self.next_test
      # Unused definitions that appeared during the previous test.
      if @cases.last
        model = Sketchup.active_model
        now = unused_new_definitions(model)
        fresh = now - (@unused_seen || [])
        @unused_seen = now
        @cases.last.note("unused definition(s) appeared: #{fresh.map(&:name).join(', ')}") unless fresh.empty?
      end
      if @tests.empty?
        finish
        return
      end
      name, block = @tests.shift
      c = Case.new(name)
      @cases << c
      Sketchup.status_text = "#{LOG} #{name}"
      guarded(c) { block.call(c, Sketchup.active_model) }
      schedule { next_phase(c) }
    end

    def self.next_phase(c)
      phase = c.phases.shift
      if phase.nil? || c.skipped
        next_test
        return
      end
      guarded(c) { phase.call }
      schedule { next_phase(c) }
    end

    def self.guarded(c)
      yield
    rescue => e
      c.check(false, "exception: #{e.class}: #{e.message}", e.backtrace.first(4).join(' | '))
      c.phases.clear
    ensure
      # The options forced by a test never leak into the next one.
      force_default_options if @hooked
    end

    def self.fatal(e)
      @fatal = "#{e.class}: #{e.message} | #{e.backtrace.first(6).join(' | ')}"
      finish
    end

    # -------------------------------------------------------------------
    # Setup
    # -------------------------------------------------------------------

    PLUGIN_FILES = %w[
      version circle_restore/detector circle_restore/rebuilder circle_restore/volume
      circle_restore main
    ].freeze

    def self.plugin_dir
      File.join(SolidBatch::PLUGIN_DIR, 'solid_batch')
    end

    def self.reload_plugin
      raise 'Solid Batch is not loaded in this SketchUp' unless defined?(SolidBatch::CircleRestore)
      # Constants are redefined: silence the "already initialized" warnings.
      verbose = $VERBOSE
      $VERBOSE = nil
      PLUGIN_FILES.each { |f| load File.join(plugin_dir, "#{f}.rb") }
    ensure
      $VERBOSE = verbose
    end

    # Message boxes and input boxes recorded instead of shown; status texts
    # and settings writes recorded too.
    def self.hook
      tests = self
      ui = UI.singleton_class
      ui.send(:alias_method, :sb_tests_messagebox, :messagebox) unless ui.method_defined?(:sb_tests_messagebox)
      ui.send(:alias_method, :sb_tests_inputbox, :inputbox) unless ui.method_defined?(:sb_tests_inputbox)
      UI.define_singleton_method(:messagebox) do |*args|
        tests.messages << args.first.to_s
        1
      end
      UI.define_singleton_method(:inputbox) do |*args|
        tests.prompts << args
        tests.inputs.empty? ? false : tests.inputs.shift
      end
      su = Sketchup.singleton_class
      su.send(:alias_method, :sb_tests_status_text=, :status_text=) unless su.method_defined?(:sb_tests_status_text=)
      su.send(:alias_method, :sb_tests_write_default, :write_default) unless su.method_defined?(:sb_tests_write_default)
      Sketchup.define_singleton_method(:status_text=) do |text|
        tests.status << text.to_s
        Sketchup.send(:sb_tests_status_text=, text)
      end
      Sketchup.define_singleton_method(:write_default) do |section, key, value|
        tests.writes << [section, key, value]
        true
      end
      # Plugin methods: aliased again after each reload of the plugin.
      sb = SolidBatch.singleton_class
      OPTIONS.each { |name| sb.send(:alias_method, :"sb_tests_#{name}", name) }
      CircleRestore::Volume.singleton_class.send(:alias_method, :sb_tests_repair_holes, :repair_holes)
      @hooked = true
    end

    def self.unhook
      return unless @hooked
      @hooked = false
      UI.singleton_class.send(:alias_method, :messagebox, :sb_tests_messagebox)
      UI.singleton_class.send(:alias_method, :inputbox, :sb_tests_inputbox)
      Sketchup.singleton_class.send(:alias_method, :status_text=, :sb_tests_status_text=)
      Sketchup.singleton_class.send(:alias_method, :write_default, :sb_tests_write_default)
      restore_options
      restore_repair
    end

    # One option of the plugin answers the block during the tests.
    def self.force_option(name, &value)
      SolidBatch.define_singleton_method(name, &value)
    end

    def self.force_default_options
      force_option(:subtract_color) { Sketchup::Color.new(*SUBTRACT_RGB) }
      force_option(:auto_repair_large) { 'Yes' }
      force_option(:large_threshold) { 10_000 }
      force_option(:min_arc_segments) { 6 }
    end

    def self.restore_options
      sb = SolidBatch.singleton_class
      OPTIONS.each { |name| sb.send(:alias_method, name, :"sb_tests_#{name}") }
    end

    # Volume.repair_holes runs the former method (:scan, repair_holes_scan)
    # or the one of the plugin (:plugin), counting its calls, holes and time.
    def self.force_repair(mode)
      tests = self
      @repair_stats = { calls: 0, holes: 0, time: 0.0 }
      CircleRestore::Volume.define_singleton_method(:repair_holes) do |entities, holes, existing|
        stats = tests.repair_stats
        stats[:calls] += 1
        stats[:holes] += holes.length
        started = Time.now
        begin
          if mode == :scan
            tests.repair_holes_scan(entities, holes, existing)
          else
            CircleRestore::Volume.sb_tests_repair_holes(entities, holes, existing)
          end
        ensure
          stats[:time] += Time.now - started
        end
      end
    end

    def self.restore_repair
      CircleRestore::Volume.singleton_class.send(:alias_method, :repair_holes, :sb_tests_repair_holes)
    end

    def self.repair_stats
      @repair_stats
    end

    # Former Volume.repair_holes (Re-Cercle v2.0.0, Solid Batch 2.3.0),
    # unchanged: every edge is scanned for every hole. Reference of the
    # comparisons of the faster method.
    def self.repair_holes_scan(entities, holes, existing)
      tol = CircleRestore::Detector::BASE_TOL * 10
      near = ->(p, h) { h.any? { |q| p.distance(q) < tol } }
      holes.each do |h|
        edge = entities.grep(Sketchup::Edge).find do |ed|
          near.call(ed.start.position, h) && near.call(ed.end.position, h)
        end
        edge.find_faces if edge
      end
      entities.grep(Sketchup::Face).each do |f|
        next if !f.valid? || existing[f.entityID]
        pts = f.outer_loop.vertices.map(&:position)
        filled = holes.any? do |h|
          h.length == pts.length && pts.all? { |p| near.call(p, h) }
        end
        f.erase! if filled
      end
    end

    # A new model, unsaved and unchanged, emptied of its template content.
    def self.prepare_model(attempt, &after)
      model = Sketchup.active_model
      if model.path.to_s.empty? && !model.modified?
        model.start_operation('Solid Batch tests — setup', true)
        model.entities.erase_entities(model.entities.to_a) unless model.entities.length.zero?
        model.commit_operation
        model.selection.clear
        @definitions_before = model.definitions.to_a
        after.call
      elsif attempt < 3
        Sketchup.file_new
        schedule { prepare_model(attempt + 1, &after) }
      else
        raise 'No new empty model: close the current model and run the tests again'
      end
    end

    # -------------------------------------------------------------------
    # Geometry and queries
    # -------------------------------------------------------------------

    def self.pt(x, y, z)
      Geom::Point3d.new(x, y, z)
    end

    # Test geometry is drawn in its own operation: the undo of a command
    # never removes it.
    def self.setup(model)
      model.start_operation('Solid Batch tests — setup', true)
      result = yield
      model.commit_operation
      result
    end

    def self.box(entities, x, y, z, w, d, h, material = nil)
      g = entities.add_group
      f = g.entities.add_face(pt(x, y, z), pt(x + w, y, z), pt(x + w, y + d, z), pt(x, y + d, z))
      f.reverse! if f.normal.z < 0
      f.pushpull(h)
      g.material = material if material
      g
    end

    def self.cylinder(entities, cx, cy, z, r, h, material = nil, segments = 24)
      g = entities.add_group
      edges = g.entities.add_circle(pt(cx, cy, z), Z_AXIS, r, segments)
      f = g.entities.add_face(edges)
      f.reverse! if f.normal.z < 0
      f.pushpull(h)
      g.material = material if material
      g
    end

    # Area of a regular polygon of n segments inscribed in a circle of radius r.
    def self.prism_area(r, n)
      0.5 * n * r * r * Math.sin(2 * Math::PI / n)
    end

    # A 20 x 20 x 10 plate at y and two through holes of radius 2 (24
    # segments) of the subtract color: [base, tools].
    def self.plate_with_holes(model, y)
      base = box(model.entities, 0, y, 0, 20, 20, 10, base_material(model))
      tools = [[5, 5], [15, 15]].map do |cx, cy|
        cylinder(model.entities, cx, y + cy, -2, 2, 14, subtract_material(model))
      end
      [base, tools]
    end

    def self.plate_volume
      4000 - 2 * prism_area(2, 24) * 10
    end

    def self.material(model, name, rgb)
      m = model.materials[name] || model.materials.add(name)
      m.color = Sketchup::Color.new(*rgb)
      m
    end

    def self.subtract_material(model)
      material(model, 'SB Test Subtract', SUBTRACT_RGB)
    end

    def self.base_material(model)
      material(model, 'SB Test Base', [200, 180, 120])
    end

    def self.select(model, *entities)
      model.selection.clear
      model.selection.add(entities.flatten)
    end

    # Combine All on the solids, messages and status texts cleared first.
    def self.combine(model, mode, solids)
      messages.clear
      status.clear
      select(model, solids)
      SolidBatch.do_combine_all_pro(mode)
    end

    # Groups of the model inside the band y0..y0 + depth (one band per test).
    def self.groups_in(model, y0, depth = 30)
      model.entities.grep(Sketchup::Group).select do |g|
        b = g.bounds
        b.min.y >= y0 - 0.5 && b.max.y <= y0 + depth + 0.5
      end
    end

    def self.arc_edges(entities)
      n = 0
      entities.each do |e|
        if e.is_a?(Sketchup::Edge)
          n += 1 if e.curve.is_a?(Sketchup::ArcCurve)
        elsif e.is_a?(Sketchup::Group)
          n += arc_edges(e.entities)
        elsif e.is_a?(Sketchup::ComponentInstance)
          n += arc_edges(e.definition.entities)
        end
      end
      n
    end

    def self.inner(instance)
      instance.is_a?(Sketchup::Group) ? instance.entities : instance.definition.entities
    end

    def self.pro?
      Sketchup.is_pro?
    end

    # Entities#weld (SketchUp 2020.1+): circle restoration runs at all.
    def self.weld?
      Sketchup::Entities.method_defined?(:weld)
    end

    def self.unused_new_definitions(model)
      (model.definitions.to_a - (@definitions_before || [])).select do |d|
        d.valid? && !d.group? && d.count_instances.zero?
      end
    end

    def self.digest(file)
      require 'digest/md5'
      File.exist?(file) ? Digest::MD5.file(file).hexdigest : nil
    end

    # One group of cylinders along +axis, a base center at each point.
    def self.cylinders(entities, centers, axis, r, h, segments = 24)
      g = entities.add_group
      centers.each { |c| add_cylinder(g.entities, c, axis, r, h, segments) }
      g
    end

    def self.add_cylinder(entities, center, axis, r, h, segments = 24)
      f = entities.add_face(entities.add_circle(center, axis, r, segments))
      f.reverse! if f.normal.dot(axis) < 0
      f.pushpull(h)
    end

    # One group of truncated cones along +z: radius r1 at each point, r2 at h.
    def self.cones(entities, centers, r1, r2, h, segments = 24)
      g = entities.add_group
      centers.each do |c|
        add_cylinder(g.entities, c, Z_AXIS, r1, h, segments)
        top = pt(c.x, c.y, c.z + h)
        ring = g.entities.grep(Sketchup::Edge).select do |e|
          e.vertices.all? { |v| (v.position.z - top.z).abs < 1e-6 && v.position.distance(top) < r1 * 1.01 }
        end
        g.entities.transform_entities(Geom::Transformation.scaling(top, r2 / r1), ring)
      end
      g
    end

    # Geometry of a solid, independent of the order and IDs of its entities.
    def self.shape_signature(solid)
      ents = inner(solid)
      r = ->(v) { v.to_f.round(5) }
      name = ->(x) { x ? x.name : '' }
      faces = ents.grep(Sketchup::Face).map do |f|
        n = f.normal
        pts = f.vertices.map { |v| p = v.position; [r.call(p.x), r.call(p.y), r.call(p.z)] }.sort
        [r.call(f.area), [r.call(n.x), r.call(n.y), r.call(n.z)], name.call(f.material),
         name.call(f.back_material), f.layer.name, f.loops.length, pts]
      end
      edges = ents.grep(Sketchup::Edge)
      curves = edges.map(&:curve).compact.uniq
      {
        faces: faces.sort,
        edges: edges.length,
        soft: edges.count(&:soft?),
        smooth: edges.count(&:smooth?),
        arcs: curves.count { |cv| cv.is_a?(Sketchup::ArcCurve) },
        arc_edges: edges.count { |e| e.curve.is_a?(Sketchup::ArcCurve) },
        volume: solid.volume.round(4),
        manifold: solid.manifold?
      }
    end

    def self.signature_diff(a, b)
      keys = a.keys.select { |k| a[k] != b[k] }
      parts = keys.map do |k|
        next "#{k} #{a[k].inspect} / #{b[k].inspect}" unless k == :faces
        "faces #{a[:faces].length} / #{b[:faces].length}, former only: #{(a[:faces] - b[:faces]).first(2).inspect}, " \
          "plugin only: #{(b[:faces] - a[:faces]).first(2).inspect}"
      end
      parts.join('; ')[0, 800]
    end

    # -------------------------------------------------------------------
    # Tests
    # -------------------------------------------------------------------

    NO_BOOLEANS = 'SketchUp Make: no native booleans (see T10)'.freeze

    def self.define_tests
      tests = self

      test 'T01 Plugin loaded, installed copy = project' do |c, _model|
        c.check(defined?(SolidBatch::VERSION), 'VERSION defined')
        c.note("plugin #{SolidBatch::VERSION}, SketchUp #{Sketchup.version}, Pro=#{Sketchup.is_pro?}, " \
               "Ruby #{RUBY_VERSION}, union defined=#{Sketchup::Group.method_defined?(:union)}, " \
               "weld defined=#{tests.weld?}")
        c.check(SolidBatch.respond_to?(:do_combine_all_pro), 'do_combine_all_pro defined')
        c.check(CircleRestore.respond_to?(:restore_in_solid), 'CircleRestore.restore_in_solid defined')
        project = File.join(tests::PROJECT_DIR, 'solid_batch')
        files = Dir.glob(File.join(project, '**', '*')).select { |f| File.file?(f) }
        names = files.map { |f| f[(project.length + 1)..-1] }
        different = names.reject do |n|
          tests.digest(File.join(project, n)) == tests.digest(File.join(tests.plugin_dir, n))
        end
        loader = 'solid_batch.rb'
        unless tests.digest(File.join(tests::PROJECT_DIR, loader)) == tests.digest(File.join(SolidBatch::PLUGIN_DIR, loader))
          different << loader
        end
        c.check(!files.empty? && different.empty?, "installed plugin identical to the project (#{files.length + 1} files)",
                different.join(', '))
      end

      test 'T02 Combine All (Union): three boxes' do |c, model|
        next c.skip(NO_BOOLEANS) unless tests.pro?
        y = 0
        boxes = tests.setup(model) do
          [0, 5, 10].map { |x| tests.box(model.entities, x, y, 0, 10, 10, 10, tests.base_material(model)) }
        end
        tests.combine(model, :union, boxes)
        c.check(tests.messages.empty?, 'no message', tests.messages.join(' / '))
        found = tests.groups_in(model, y)
        c.check(found.length == 1, 'one solid left of three', "#{found.length} group(s)")
        result = found.first
        next unless result
        c.check(result.manifold?, 'result is a solid')
        c.check((result.volume - 2000).abs < 0.01, "volume 2000 (#{result.volume.round(3)})")
        c.check(model.selection.to_a == [result], 'result selected')
        c.check(tests.status.last.to_s.include?('Done (2 operations)'), 'status bar: done, 2 operations',
                tests.status.last.to_s)
        c.note("faces of the result: #{tests.inner(result).grep(Sketchup::Face).length}")
      end

      test 'T03 Combine All (Shell): three boxes' do |c, model|
        next c.skip(NO_BOOLEANS) unless tests.pro?
        y = 50
        boxes = tests.setup(model) do
          [0, 5, 10].map { |x| tests.box(model.entities, x, y, 0, 10, 10, 10, tests.base_material(model)) }
        end
        tests.combine(model, :outer_shell, boxes)
        c.check(tests.messages.empty?, 'no message', tests.messages.join(' / '))
        found = tests.groups_in(model, y)
        c.check(found.length == 1, 'one solid left of three', "#{found.length} group(s)")
        result = found.first
        next unless result
        c.check(result.manifold?, 'result is a solid')
        c.check((result.volume - 2000).abs < 0.01, "volume 2000 (#{result.volume.round(3)})")
        c.check(model.selection.to_a == [result], 'result selected')
      end

      test 'T04 Combine All: subtract by color, native circles' do |c, model|
        next c.skip(NO_BOOLEANS) unless tests.pro?
        y = 100
        base, tools = tests.setup(model) { tests.plate_with_holes(model, y) }
        tests.combine(model, :union, [base] + tools)
        c.check(tests.messages.empty?, 'no message', tests.messages.join(' / '))
        found = tests.groups_in(model, y)
        c.check(found.length == 1, 'one solid left (tools erased)', "#{found.length} group(s)")
        c.check(tools.none?(&:valid?), 'subtract solids erased')
        result = found.first
        next unless result
        c.check(result.manifold?, 'result is a solid')
        expected = tests.plate_volume
        c.check((result.volume - expected).abs < 0.01, "volume #{expected.round(3)} (#{result.volume.round(3)})")
        c.check(model.selection.to_a == [result], 'result selected')
        arcs = tests.arc_edges(tests.inner(result))
        if tests.weld?
          c.check(arcs == 96, "2 holes with native circles: 96 edges in native circles (#{arcs})")
        else
          c.note("before 2020.1: #{arcs} edge(s) in native circles (no restoration)")
        end
        subtract = SolidBatch.subtract_color
        painted = tests.inner(result).grep(Sketchup::Face).count do |f|
          f.material && SolidBatch.color_match?(f.material.color, subtract)
        end
        c.note("faces of the subtract color on the result: #{painted}")
        c.note("status bar: #{tests.status.last}")
      end

      test 'T05 Combine All: one undo step' do |c, model|
        next c.skip(NO_BOOLEANS) unless tests.pro?
        next c.skip('Sketchup.undo not available') unless Sketchup.respond_to?(:undo)
        y = 150
        solids = tests.setup(model) do
          base, tools = tests.plate_with_holes(model, y)
          [base, tests.box(model.entities, 15, y, 0, 10, 10, 10, tests.base_material(model))] + tools
        end
        volumes = solids.map { |s| s.volume.round(3) }.sort
        tests.combine(model, :union, solids)
        c.check(tests.groups_in(model, y).length == 1, 'Combine All: one solid (union, 2 subtracts, circles)')
        Sketchup.undo
        c.later do
          back = tests.groups_in(model, y)
          c.check(back.length == 4, 'one Ctrl+Z: the 4 solids are back', "#{back.length} group(s)")
          c.check(back.map { |s| s.volume.round(3) }.sort == volumes, 'one Ctrl+Z: same volumes',
                  back.map { |s| s.volume.round(3) }.sort.inspect)
          c.check(back.all?(&:manifold?), 'one Ctrl+Z: all solids')
        end
      end

      test 'T06 Combine All: messages (selection)' do |c, model|
        y = 200
        one = tests.setup(model) { tests.box(model.entities, 0, y, 0, 10, 10, 10, tests.base_material(model)) }
        tests.combine(model, :union, [one])
        c.check(tests.messages.length == 1 && tests.messages.first.include?('Select at least 2'),
                'one solid: "Select at least 2" message', tests.messages.join(' / '))
        pair = tests.setup(model) do
          [0, 5].map { |x| tests.box(model.entities, x + 20, y, 0, 10, 10, 10, tests.subtract_material(model)) }
        end
        tests.combine(model, :union, pair)
        c.check(tests.messages.length == 1 && tests.messages.first.include?('No base objects found'),
                'only subtract solids: "No base objects found" message', tests.messages.join(' / '))
        c.check(pair.all?(&:valid?) && one.valid?, 'nothing changed')
      end

      test 'T07 Circle restoration on a cylinder with broken circles' do |c, model|
        g = tests.setup(model) do
          cyl = tests.cylinder(model.entities, 3, 253, 0, 3, 10)
          cyl.entities.grep(Sketchup::Edge).each { |e| e.explode_curve if e.valid? && e.curve }
          cyl
        end
        c.check(tests.arc_edges(g.entities).zero?, 'test cylinder has no circle left')
        edges = g.entities.grep(Sketchup::Edge).length
        model.start_operation('Solid Batch tests — circles', true)
        res = CircleRestore.restore_in_solid(g, min_arc_segments: 6)
        model.commit_operation
        c.note("restore: #{CircleRestore.summary(res, reasons: true)}")
        if tests.weld?
          c.check(res[:native] >= 2, "native circles rebuilt (#{res[:native]})")
          c.check(tests.arc_edges(g.entities) == 48, "48 edges in native circles (#{tests.arc_edges(g.entities)})")
        else
          c.note("before 2020.1: #{res[:native]} native circle(s), #{tests.arc_edges(g.entities)} edge(s) in native circles")
        end
        c.check(g.manifold? && g.entities.grep(Sketchup::Edge).length == edges, 'still a solid, same edges')
      end

      test 'T08 Combine All: large object threshold' do |c, model|
        next c.skip(NO_BOOLEANS) unless tests.pro?
        y = 300
        base, tools = tests.setup(model) { tests.plate_with_holes(model, y) }
        tests.force_option(:large_threshold) { 10 }
        tests.force_option(:auto_repair_large) { 'No' }
        tests.combine(model, :union, [base] + tools)
        c.check(tests.messages.length == 1 && tests.messages.first.include?('restoration was skipped'),
                'large result, auto-repair No: "skipped" message', tests.messages.join(' / '))
        skipped = tests.groups_in(model, y).first
        c.note("auto-repair No: #{skipped ? tests.arc_edges(tests.inner(skipped)) : 'no result'} edge(s) in native circles")
        y = 350
        base, tools = tests.setup(model) { tests.plate_with_holes(model, y) }
        tests.force_option(:auto_repair_large) { 'Yes' }
        tests.combine(model, :union, [base] + tools)
        c.check(tests.messages.empty?, 'large result, auto-repair Yes: no message', tests.messages.join(' / '))
        repaired = tests.groups_in(model, y).first
        next c.check(false, 'auto-repair Yes: one result') unless repaired
        arcs = tests.arc_edges(tests.inner(repaired))
        if tests.weld?
          c.check(arcs == 96, "auto-repair Yes: 96 edges in native circles (#{arcs})")
        else
          c.note("before 2020.1: #{arcs} edge(s) in native circles")
        end
      end

      test 'T09 Set Repair Options: values saved, invalid values set to defaults' do |c, _model|
        c.note("Set Repair Options in the menu and toolbar: #{Sketchup.version.to_f >= 20.1 ? 'yes' : 'no (before 2020.1)'}")
        tests.messages.clear
        tests.writes.clear
        tests.prompts.clear
        tests.inputs.replace([false])
        SolidBatch.do_set_repair_options
        c.check(tests.writes.empty? && tests.messages.empty?, 'Cancel: nothing saved, no message')
        args = tests.prompts.first || []
        c.check(args[0].is_a?(Array) && args[0].length == 3, 'three fields', args[0].inspect)
        c.check(args[1] == ['Yes', '10000', '6'], 'fields show the current options', args[1].inspect)
        tests.inputs.replace([%w[No 0 2]])
        SolidBatch.do_set_repair_options
        expected = [%w[SolidBatch auto_repair_large No], ['SolidBatch', 'large_threshold', 10_000],
                    ['SolidBatch', 'min_arc_segments', 6]]
        c.check(tests.writes == expected, 'threshold 0 and 2 segments: defaults saved', tests.writes.inspect)
        c.check(tests.messages.length == 1 && tests.messages.first.include?('Repair options saved'),
                'summary message', tests.messages.join(' / '))
        tests.writes.clear
        tests.inputs.replace([%w[Yes 5000 8]])
        SolidBatch.do_set_repair_options
        expected = [%w[SolidBatch auto_repair_large Yes], ['SolidBatch', 'large_threshold', 5000],
                    ['SolidBatch', 'min_arc_segments', 8]]
        c.check(tests.writes == expected, 'values saved', tests.writes.inspect)
      end

      test 'T10 SketchUp Make: Combine All (current behavior, recorded)' do |c, model|
        next c.skip('SketchUp Pro') if tests.pro?
        y = 450
        boxes = tests.setup(model) do
          [0, 5].map { |x| tests.box(model.entities, x, y, 0, 10, 10, 10, tests.base_material(model)) }
        end
        tests.combine(model, :union, boxes)
        left = tests.groups_in(model, y)
        c.note("Union of 2 boxes: messages #{tests.messages.inspect}; #{left.length} solid(s) left, " \
               "volumes #{left.map { |g| g.volume.round(2) }.inspect}")
        y = 500
        base, tools = tests.setup(model) { tests.plate_with_holes(model, y) }
        tests.combine(model, :union, [base] + tools)
        left = tests.groups_in(model, y)
        c.note("Plate and 2 subtract solids: messages #{tests.messages.inspect}; #{left.length} solid(s) left, " \
               "volumes #{left.map { |g| g.volume.round(2) }.inspect}")
      end
    end

    # -------------------------------------------------------------------
    # Report
    # -------------------------------------------------------------------

    def self.finish
      unhook
      lines = report_lines
      puts lines
      Dir.mkdir(RESULTS_DIR) unless File.directory?(RESULTS_DIR)
      major = Sketchup.version.to_i
      File.open(File.join(RESULTS_DIR, "latest-#{major}.txt"), 'w:UTF-8') { |f| f.puts lines }
      File.open(File.join(RESULTS_DIR, "history-#{major}.log"), 'a:UTF-8') { |f| f.puts lines; f.puts }
      Sketchup.status_text = "#{LOG} #{lines.last}"
    rescue => e
      puts "#{LOG} report error: #{e.message}"
    end

    def self.report_lines
      edition = Sketchup.is_pro? ? 'Pro' : 'Make'
      lines = ["Solid Batch tests — SketchUp #{Sketchup.version} #{edition} — Ruby #{RUBY_VERSION} — " \
               "plugin #{SolidBatch::VERSION} — #{@started.strftime('%Y-%m-%d %H:%M:%S')}"]
      passed = failed = skipped = checks = bad = 0
      (@cases || []).each do |c|
        checks += c.checks.length
        bad += c.checks.count { |k| !k[0] }
        if c.skipped
          skipped += 1
          lines << "SKIP  #{c.name} — #{c.skipped}"
        elsif c.failed?
          failed += 1
          lines << "FAIL  #{c.name}"
        else
          passed += 1
          lines << "PASS  #{c.name} (#{c.checks.length} checks)"
        end
        c.checks.each do |ok, label, detail|
          next if ok && !c.failed?
          text = "      #{ok ? 'ok' : 'XX'} #{label}"
          text += " — #{detail}" if !ok && detail && !detail.to_s.empty?
          lines << text
        end
        c.notes.each { |n| lines << "      · #{n}" }
      end
      lines << "FATAL #{@fatal}" if @fatal
      lines << format('DONE  passed=%d failed=%d skipped=%d checks=%d failed_checks=%d time=%.1fs',
                      passed, failed + (@fatal ? 1 : 0), skipped, checks, bad, Time.now - @started)
      lines
    end
  end
end

$VERBOSE = verbose

# Started once SketchUp is idle (also when loaded by -RubyStartup).
unless $sb_tests_no_autorun
  sb_tests_timer = UI.start_timer(1, false) do
    UI.stop_timer(sb_tests_timer)
    SolidBatch::Tests.run
  end
end
