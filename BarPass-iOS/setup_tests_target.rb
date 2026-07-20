#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'BarPass app.xcodeproj'
project = Xcodeproj::Project.open(project_path)

app_target = project.targets.find { |t| t.name == 'BarPass app' }
raise "app target not found" unless app_target

if project.targets.any? { |t| t.name == 'BarPassTests' }
  puts "BarPassTests target already exists, skipping creation"
  exit 0
end

test_target = project.new_target(:unit_test_bundle, 'BarPassTests', :ios, '17.0')
test_target.add_dependency(app_target)

# Group for the test files (folder already exists on disk with 3 pre-written
# test files that were never wired into a target).
tests_group = project.main_group.find_subpath('BarPassTests', true)
tests_group.set_source_tree('SOURCE_ROOT')

test_files = Dir.glob('BarPassTests/*.swift').sort
test_files.each do |path|
  file_ref = tests_group.files.find { |f| f.path == File.basename(path) }
  file_ref ||= tests_group.new_reference(path)
  file_ref.set_source_tree('<group>') if file_ref.source_tree != '<group>'
  unless test_target.source_build_phase.files_references.include?(file_ref)
    test_target.add_file_references([file_ref])
  end
end

test_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.sebastian.barpass.tests'
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/BarPass app.app/BarPass app'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'YES'
end

project.save
puts "Created BarPassTests target with #{test_files.length} test files: #{test_files.map { |f| File.basename(f) }.join(', ')}"
