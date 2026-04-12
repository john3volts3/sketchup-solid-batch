require 'sketchup.rb'
require 'extensions.rb'

module SolidBatch
  PLUGIN_DIR = File.dirname(__FILE__)
  PLUGIN_NAME = 'Solid Batch'.freeze

  ext = SketchupExtension.new(PLUGIN_NAME, File.join('solid_batch', 'main'))
  ext.description = 'Batch solid operations using native SketchUp Pro boolean tools'
  ext.version = '2.2.1'
  ext.creator = 'DRO'
  ext.copyright = '2026'

  Sketchup.register_extension(ext, true)
end
