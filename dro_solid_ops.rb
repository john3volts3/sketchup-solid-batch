require 'sketchup.rb'
require 'extensions.rb'

module DRO_SolidOps
  PLUGIN_DIR = File.dirname(__FILE__)
  PLUGIN_NAME = 'Solid Ops'.freeze

  ext = SketchupExtension.new(PLUGIN_NAME, File.join('dro_solid_ops', 'main'))
  ext.description = 'Boolean operations on solids: Union, Subtract, Split'
  ext.version = '1.0.0'
  ext.creator = 'DRO'
  ext.copyright = '2026'

  Sketchup.register_extension(ext, true)
end
