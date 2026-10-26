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
      if @hooked
        force_default_options
        restore_pro
      end
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
      circle_restore solid_operations main
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
      su.send(:alias_method, :sb_tests_is_pro?, :is_pro?) unless su.method_defined?(:sb_tests_is_pro?)
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
      restore_pro
      restore_options
      restore_repair
    end

    # Sketchup.is_pro? answers value (SketchUp Make simulated in SketchUp Pro).
    def self.force_pro(value)
      Sketchup.define_singleton_method(:is_pro?) { value }
    end

    def self.restore_pro
      Sketchup.singleton_class.send(:alias_method, :is_pro?, :sb_tests_is_pro?)
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
    rescue
      model.abort_operation
      raise
    end

    # Native boolean of a test step: the solid that holds the result, or nil.
    def self.boolean(op, acc, tool)
      op == 'union' ? acc.union(tool) : tool.subtract(acc)
    end

    # Booleans of a T12 case: [result, nil], or [last result, failed step].
    def self.run_steps(model, base, steps)
      acc = base
      steps.each_with_index do |(op, tool), k|
        model.selection.clear
        acc = boolean(op, acc, tool)
        return [acc, "#{op} #{k + 1} of #{steps.length}"] unless acc && acc.valid?
      end
      [acc, nil]
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

    # T13: the plate with its 2 holes, a box united to it and a third hole:
    # Union 1 of 1, then Subtract 1, 2 and 3 of 3.
    def self.failing_case(model, y)
      plate, holes = plate_with_holes(model, y)
      extra = cylinder(model.entities, 10, y + 10, -2, 1.5, 14, subtract_material(model))
      [plate, box(model.entities, 15, y, 0, 10, 10, 10, base_material(model))] + holes + [extra]
    end

    # Volumes of the groups in the band of y, sorted.
    def self.band_state(model, y)
      groups_in(model, y).map { |g| g.volume.round(3) }.sort
    end

    # The call number +nth+ of the native +op+ (:union or :subtract) on the
    # solids does the boolean, then fails (:nil: returns nil; :raise: raises).
    # Returns { pid: persistent_id of the solid of the failed step }.
    def self.force_failure(solids, op, nth, how)
      failed = {}
      calls = [0]
      solids.each do |s|
        s.define_singleton_method(op) do |other|
          # Native union: the receiver is the base, the solid of the step is
          # the other one; native subtract: the receiver is the tool. Read
          # before the boolean, which erases it.
          solid = op == :union ? other : self
          pid = solid.respond_to?(:persistent_id) ? solid.persistent_id : nil
          res = super(other)
          calls[0] += 1
          next res unless calls[0] == nth
          failed[:pid] = pid
          raise 'test failure' if how == :raise
          nil
        end
      end
      failed
    end

    def self.remove_failure(solids, op)
      solids.each do |s|
        s.singleton_class.send(:remove_method, op) if s.singleton_methods.include?(op)
      end
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

    # Circles of +acc+ rebuilt by the former repair_holes, then by the one of
    # the plugin, each in an aborted operation: same result expected. +first+:
    # the plate with 20 holes, at least twice faster.
    def self.compare_repair(c, model, acc, first)
      c.check(acc.manifold?, 'boolean result is a solid')
      broken = arc_edges(inner(acc))
      sig = {}
      counts = {}
      stats = {}
      times = {}
      [:scan, :plugin].each do |mode|
        force_repair(mode)
        model.start_operation('Solid Batch tests — repair_holes', true)
        begin
          started = Time.now
          res = CircleRestore.restore_in_solid(acc, min_arc_segments: SolidBatch.min_arc_segments)
          times[mode] = Time.now - started
          sig[mode] = shape_signature(acc)
          counts[mode] = [res[:native], res[:welded], res[:unwelded], res[:reasons].to_a.sort]
          stats[mode] = repair_stats.dup
          c.note("restore: #{CircleRestore.summary(res, reasons: true)}") if mode == :plugin
        ensure
          model.abort_operation
          restore_repair
        end
      end
      c.check(stats[:scan][:holes] > 0,
              "repair_holes used (#{stats[:scan][:calls]} calls, #{stats[:scan][:holes]} holes)")
      c.check(sig[:scan] == sig[:plugin], 'same faces, edges and circles as the former method',
              signature_diff(sig[:scan], sig[:plugin]))
      c.check(counts[:scan] == counts[:plugin], 'same restore counts',
              "#{counts[:scan].inspect} / #{counts[:plugin].inspect}")
      c.check(stats[:scan].values_at(:calls, :holes) == stats[:plugin].values_at(:calls, :holes),
              'same repair_holes calls')
      c.check(counts[:plugin][0] > 0 && sig[:plugin][:manifold], 'native circles rebuilt, still a solid',
              counts[:plugin].inspect)
      c.note(format('arc edges before %d, after %d; restore: former %.2fs (repair_holes %.2fs), ' \
                    'plugin %.2fs (repair_holes %.2fs)', broken, sig[:plugin][:arc_edges],
                    times[:scan], stats[:scan][:time], times[:plugin], stats[:plugin][:time]))
      return unless first && CircleRestore::Volume.respond_to?(:near_items)
      c.check(stats[:plugin][:time] < stats[:scan][:time] / 2, 'plugin repair_holes at least twice faster')
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
        c.check(defined?(SolidBatch::SolidOperations) && SolidOperations.respond_to?(:outer_shell),
                'SolidOperations loaded (solid_operations.rb)')
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
        c.check(arcs == 96, "2 holes with native circles: 96 edges in native circles (#{arcs})")
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
        next c.skip('SketchUp Make: PRO Only first (see T10)') unless tests.pro?
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
        c.check(res[:native] >= 2, "native circles rebuilt (#{res[:native]})")
        c.check(tests.arc_edges(g.entities) == 48, "48 edges in native circles (#{tests.arc_edges(g.entities)})")
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
        c.check(arcs == 96, "auto-repair Yes: 96 edges in native circles (#{arcs})")
      end

      test 'T09 Set Repair Options: values saved, invalid values set to defaults' do |c, _model|
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

      # In SketchUp Pro, SketchUp Make is simulated (Sketchup.is_pro? false).
      test 'T10 Combine All without SketchUp Pro: PRO Only message' do |c, model|
        c.note('SketchUp Pro: SketchUp Make simulated') if tests.pro?
        y = 450
        base, tools = tests.setup(model) { tests.plate_with_holes(model, y) }
        solids = [base] + tools
        tests.force_pro(false)
        [:union, :outer_shell].each do |mode|
          tests.combine(model, mode, solids)
          c.check(tests.messages.length == 1 && tests.messages.first.start_with?('PRO Only'),
                  "#{mode}: PRO Only message", tests.messages.join(' / '))
        end
        tests.restore_pro
        c.check(solids.all?(&:valid?) && tests.groups_in(model, y).length == 3, 'nothing changed')
        c.check((base.volume - 4000).abs < 0.01, 'base unchanged', base.volume.round(3).to_s)
      end

      # T11: grid search of Volume.repair_holes against a full scan
      # (OPTIMISATION_REPAIR_HOLES.md, § 6).
      test 'T11 Grids of repair_holes = full scan' do |c, _model|
        vol = CircleRestore::Volume
        next c.skip('grid search not in the plugin yet') unless vol.respond_to?(:near_items)
        tol = CircleRestore::Detector::BASE_TOL * 10
        srand(1234)
        rnd = -> { (rand - 0.5) * 0.1 }
        # Dense points (many neighbors), negative coordinates, cell borders.
        points = Array.new(500) { tests.pt(rnd.call, rnd.call, rnd.call) }
        points += Array.new(50) { |k| tests.pt(tol * (k - 25), -tol * 3, tol * 2) }
        queries = Array.new(2000) { tests.pt(rnd.call, rnd.call, rnd.call) }
        queries += Array.new(200) { |k| tests.pt(tol * (k % 50 - 25) + rnd.call * 0.1, -tol * 3, tol * 2) }
        holder = Struct.new(:position)
        vertices = points.map { |p| holder.new(p) }
        grid = vol.point_grid(points, tol)
        vertex_grid = {}
        vertices.each { |v| (vertex_grid[vol.cell_of(v.position, tol)] ||= []) << v }
        bad = 0
        pairs = 0
        queries.each do |q|
          want = points.select { |p| q.distance(p) < tol }
          pairs += want.length
          got = vol.near_items(q, grid, tol)
          got_v = vol.near_items(q, vertex_grid, tol) { |v| v.position }.map(&:position)
          bad += 1 unless [got, got_v].all? { |list| list.map(&:object_id).sort == want.map(&:object_id).sort }
          bad += 1 unless vol.near_grid?(q, grid, tol) == !want.empty?
        end
        c.note("#{queries.length} queries, #{pairs} pairs closer than the tolerance")
        c.check(pairs > 1000, 'enough close pairs to test')
        c.check(bad.zero?, "same neighbors as the full scan (#{bad} difference(s))")
      end

      # T12: Volume.repair_holes of the plugin against the former method
      # (repair_holes_scan) on the same broken circles: same faces, edges and
      # circles expected (OPTIMISATION_REPAIR_HOLES.md, § 7). Cases of Solid
      # Procedural 1.1.1 (T15).
      repair_cases = [
        ['plate with 20 holes', lambda do |m, x, y|
          centers = (0...5).flat_map { |i| (0...4).map { |j| tests.pt(x + 4 + 8 * i, y + 4 + 8 * j, -1) } }
          [tests.box(m.entities, x, y, 0, 40, 32, 2),
           [['subtract', tests.cylinders(m.entities, centers, Z_AXIS, 0.8, 4)]]]
        end],
        ['holes near an edge', lambda do |m, x, y|
          centers = [[1.15, 5], [5, 1.2], [10, 5], [15, 5]].map { |a, b| tests.pt(x + a, y + b, -1) }
          [tests.box(m.entities, x, y, 0, 20, 10, 2),
           [['subtract', tests.cylinders(m.entities, centers, Z_AXIS, 1, 4)]]]
        end],
        ['colored faces (front / back)', lambda do |m, x, y|
          base = tests.box(m.entities, x, y, 0, 20, 20, 2)
          base.entities.grep(Sketchup::Face).each do |f|
            if f.normal.z > 0.9
              f.material = tests.material(m, 'SB Test Top', [220, 60, 60])
              f.back_material = tests.material(m, 'SB Test Top back', [60, 60, 220])
            elsif f.normal.z < -0.9
              f.material = tests.material(m, 'SB Test Bottom', [60, 200, 60])
            elsif f.normal.x < -0.9
              f.material = tests.material(m, 'SB Test Side', [200, 200, 60])
            end
          end
          centers = [[5, 5], [15, 5], [5, 15], [15, 15]].map { |a, b| tests.pt(x + a, y + b, -1) }
          [base, [['subtract', tests.cylinders(m.entities, centers, Z_AXIS, 1, 4)]]]
        end],
        ['holes across two coplanar faces', lambda do |m, x, y|
          base = tests.box(m.entities, x, y, 0, 20, 10, 2)
          base.entities.add_line(tests.pt(x + 10, y, 2), tests.pt(x + 10, y + 10, 2))
          base.entities.add_line(tests.pt(x + 10, y, 0), tests.pt(x + 10, y + 10, 0))
          centers = [[10, 3], [10, 7], [4, 5], [4, 8], [16, 5], [16, 2]].map { |a, b| tests.pt(x + a, y + b, -1) }
          [base, [['subtract', tests.cylinders(m.entities, centers, Z_AXIS, 1, 4)]]]
        end],
        ['very small holes (1 mm)', lambda do |m, x, y|
          centers = [[1, 1], [2, 1], [3, 1], [1, 3], [2, 3], [3, 3]].map { |a, b| tests.pt(x + a, y + b, -0.2) }
          [tests.box(m.entities, x, y, 0, 4, 4, 0.4),
           [['subtract', tests.cylinders(m.entities, centers, Z_AXIS, 0.02, 0.8)]]]
        end],
        ['very large holes', lambda do |m, x, y|
          centers = [[50, 50], [150, 50], [50, 150], [150, 150]].map { |a, b| tests.pt(x + a, y + b, -1) }
          [tests.box(m.entities, x, y, 0, 200, 200, 4),
           [['subtract', tests.cylinders(m.entities, centers, Z_AXIS, 40, 6)]]]
        end],
        # The counterbore floor holds the hole circle.
        ['counterbores', lambda do |m, x, y|
          holes = [5, 12, 19].map { |a| tests.pt(x + a, y + 5, -1) }
          bores = holes.map { |p| tests.pt(p.x, p.y, 2) }
          [tests.box(m.entities, x, y, 0, 24, 10, 3),
           [['subtract', tests.cylinders(m.entities, bores, Z_AXIS, 2, 2)],
            ['subtract', tests.cylinders(m.entities, holes, Z_AXIS, 1, 5)]]]
        end],
        # Cone of radius 1.2 at z = 2 (a step around the hole), 2.7 at the top.
        ['countersinks with a step', lambda do |m, x, y|
          holes = [5, 12, 19].map { |a| tests.pt(x + a, y + 5, -1) }
          sinks = holes.map { |p| tests.pt(p.x, p.y, 2) }
          [tests.box(m.entities, x, y, 0, 24, 10, 3),
           [['subtract', tests.cones(m.entities, sinks, 1.2, 2.7, 1.5)],
            ['subtract', tests.cylinders(m.entities, holes, Z_AXIS, 1, 5)]]]
        end],
        # Hole first: the counterbore cuts the top face around the hole.
        ['counterbores after the holes', lambda do |m, x, y|
          holes = [5, 12, 19].map { |a| tests.pt(x + a, y + 5, -1) }
          bores = holes.map { |p| tests.pt(p.x, p.y, 2) }
          [tests.box(m.entities, x, y, 0, 24, 10, 3),
           [['subtract', tests.cylinders(m.entities, holes, Z_AXIS, 1, 5)],
            ['subtract', tests.cylinders(m.entities, bores, Z_AXIS, 2, 2)]]]
        end],
        ['holes on the top and on a side', lambda do |m, x, y|
          top = [[5, 5], [15, 5], [5, 15], [15, 15]].map { |a, b| tests.pt(x + a, y + b, -1) }
          side = [3, 7].map { |h| tests.pt(x - 1, y + 10, h) }
          [tests.box(m.entities, x, y, 0, 20, 20, 10),
           [['subtract', tests.cylinders(m.entities, top, Z_AXIS, 1, 12)],
            ['subtract', tests.cylinders(m.entities, side, X_AXIS, 1, 22)]]]
        end],
        ['truncated cones', lambda do |m, x, y|
          cones = [[5, 5], [15, 5], [5, 15]].map { |a, b| tests.pt(x + a, y + b, -1) }
          [tests.box(m.entities, x, y, 0, 20, 20, 3),
           [['subtract', tests.cones(m.entities, cones, 1.5, 0.7, 5)],
            ['subtract', tests.cylinders(m.entities, [tests.pt(x + 15, y + 15, -1)], Z_AXIS, 1, 5)]]]
        end],
        ['pins added by union (one end broken)', lambda do |m, x, y|
          centers = [[5, 5], [15, 5], [5, 15], [15, 15]].map { |a, b| tests.pt(x + a, y + b, 1) }
          [tests.box(m.entities, x, y, 0, 20, 20, 2),
           [['union', tests.cylinders(m.entities, centers, Z_AXIS, 1, 4)]]]
        end],
        ['blind holes', lambda do |m, x, y|
          centers = [[5, 5], [15, 5], [5, 15], [15, 15]].map { |a, b| tests.pt(x + a, y + b, 2) }
          [tests.box(m.entities, x, y, 0, 20, 20, 4),
           [['subtract', tests.cylinders(m.entities, centers, Z_AXIS, 1, 3)]]]
        end]
      ]
      repair_cases.each_with_index do |(name, build), i|
        test "T12 repair_holes: #{name}" do |c, model|
          next c.skip(NO_BOOLEANS) unless tests.pro?
          definitions = model.definitions.to_a
          acc, failed = tests.setup(model) do
            base, steps = build.call(model, i * 250, 1000)
            tests.run_steps(model, base, steps)
          end
          # Native booleans with a tool of several solids leave unused
          # definitions (TempInstance#n): removed here when the API allows it.
          temp = (model.definitions.to_a - definitions).select { |d| !d.group? && d.count_instances.zero? }
          unless temp.empty?
            removable = model.definitions.respond_to?(:remove)
            c.note("the boolean left #{temp.length} unused definition(s) #{temp.first.name}..." \
                   "#{removable ? ' (removed by the test)' : ''}")
            temp.each { |d| model.definitions.remove(d) } if removable
          end
          next c.check(false, "boolean #{failed} failed") if failed
          tests.compare_repair(c, model, acc, i.zero?)
        end
      end
      # Also used by the local tests.
      @repair_cases = repair_cases

      # T14: SketchUp itself: aborting an operation chained (transparent) to
      # committed ones, as in Combine All, undoes the whole chain, and only it
      # (combine_failed relies on it).
      test 'T14 SketchUp: abort of a chained (transparent) operation undoes the chain' do |c, model|
        y = 2400
        marker = tests.setup(model) { tests.box(model.entities, 0, y, 0, 5, 5, 5) }
        boxes = []
        3.times do |k|
          model.start_operation('Solid Batch tests — chain', true, false, k > 0)
          boxes << tests.box(model.entities, 10 * (k + 1), y, 0, 5, 5, 5)
          model.commit_operation
        end
        model.start_operation('Solid Batch tests — chain', true, false, true)
        aborted = tests.box(model.entities, 40, y, 0, 5, 5, 5)
        model.abort_operation
        state = "marker #{marker.valid?}, committed boxes #{boxes.map(&:valid?).inspect}, " \
                "aborted box #{aborted.valid?}, groups in the band #{tests.groups_in(model, y).length}"
        c.check(boxes.none?(&:valid?) && !aborted.valid?, 'the 3 committed operations of the chain are undone', state)
        c.check(marker.valid? && tests.groups_in(model, y).length == 1, 'the operation before the chain stays', state)
        c.later do
          c.check(marker.valid? && tests.groups_in(model, y).length == 1, 'still so a while later')
        end
      end

      # T13: one step of Combine All fails (forced on the solids of the test):
      # the steps already done are undone too, the message names the step and
      # the solid of that step is selected; the action done before Combine
      # All stays. Steps: Union 1 of 1, then Subtract 1, 2 and 3 of 3.
      failures = [
        [1, :union, 'Union 1 of 1', :nil],
        [3, :subtract, 'Subtract 2 of 3', :nil],
        [4, :subtract, 'Subtract 3 of 3', :nil],
        [3, :subtract, 'Subtract 2 of 3', :raise]
      ]
      failures.each_with_index do |(failing, op, action, how), k|
        test "T13 Combine All fails at step #{failing} of 4 (#{action}, #{how}): nothing changed" do |c, model|
          next c.skip(NO_BOOLEANS) unless tests.pro?
          y = 2100 + 60 * k
          solids = tests.setup(model) { tests.failing_case(model, y) }
          marker = tests.setup(model) { tests.box(model.entities, 60, y, 0, 5, 5, 5) }
          before = tests.band_state(model, y)
          failed = tests.force_failure(solids, op, op == :union ? 1 : failing - 1, how)
          begin
            tests.combine(model, :union, solids)
          ensure
            tests.remove_failure(solids, op)
          end
          message = tests.messages.first.to_s
          c.check(tests.messages.length == 1 && message.include?("failed at step #{failing} of 4: #{action},"),
                  "message names the step: #{action}", message)
          c.check(message.include?('Nothing was changed'), 'message: nothing was changed')
          c.check(how != :raise || message.include?('Error: test failure'), 'message gives the error')
          c.check(tests.band_state(model, y) == before, 'the solids are as before (count, volumes)',
                  "#{before.inspect} / #{tests.band_state(model, y).inspect}")
          c.check(marker.valid?, 'the action before Combine All is not undone')
          sel = model.selection.to_a
          c.check(sel.length == 1 && failed[:pid] && sel.first.persistent_id == failed[:pid],
                  'the solid of the failed step is selected', sel.map { |e| e.class.name }.join(', '))
          c.later do
            c.check(tests.band_state(model, y) == before && marker.valid?, 'still as before after a while')
          end
        end
      end

      # Extra tests kept on this PC only (optional file, not in the repository).
      local = File.join(TESTS_DIR, 'local', 'local_tests.rb')
      if File.exist?(local)
        load local
        define_local_tests
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
