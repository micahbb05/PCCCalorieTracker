#!/usr/bin/env ruby
require 'xcodeproj'
require 'xcodeproj/scheme'

project_path = File.expand_path('../Calorie Tracker.xcodeproj', __dir__)
proj = Xcodeproj::Project.open(project_path)

watch_target_name = 'Calorie Tracker Watch'
existing = proj.targets.find { |t| t.name == watch_target_name }
if existing
  puts "Target #{watch_target_name} already exists"
  exit 0
end

ios_target = proj.targets.find { |t| t.name == 'Calorie Tracker' }
raise 'iOS target not found' unless ios_target

team = ios_target.build_configurations.first.build_settings['DEVELOPMENT_TEAM']

# Create watchOS app target (single-target SwiftUI watch app)
watch_target = proj.new_target(:application, watch_target_name, :watchos, '10.0')
watch_target.product_name = watch_target_name

watch_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'Micah.Calorie-Tracker.watch'
  config.build_settings['INFOPLIST_FILE'] = 'Calorie Tracker Watch/Info.plist'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '4'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  config.build_settings['WATCHOS_DEPLOYMENT_TARGET'] = '10.0'
  config.build_settings['MARKETING_VERSION'] = '1.1'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '19'
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['DEVELOPMENT_TEAM'] = team if team
end

# Group and files
root = proj.main_group
watch_group = root.find_subpath('Calorie Tracker Watch', true)
watch_group.set_source_tree('SOURCE_ROOT')

files = [
  'Calorie Tracker Watch/CalorieTrackerWatchMVPApp.swift',
  'Calorie Tracker Watch/DashboardView.swift',
  'Calorie Tracker Watch/WatchCalorieStore.swift',
  'Calorie Tracker Watch/WatchSyncService.swift',
  'Calorie Tracker Watch/Info.plist'
]

files.each do |path|
  ref = watch_group.files.find { |f| f.path == File.basename(path) } || watch_group.new_file(path)
  next if path.end_with?('Info.plist')
  watch_target.source_build_phase.add_file_reference(ref, true)
end

assets_ref = watch_group.files.find { |f| f.path == 'Assets.xcassets' } || watch_group.new_file('Calorie Tracker Watch/Assets.xcassets')
watch_target.resources_build_phase.add_file_reference(assets_ref, true)

# Shared scheme
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(watch_target, nil)
scheme.launch_action.build_configuration = 'Debug'
scheme.archive_action.build_configuration = 'Release'
scheme.save_as(project_path, watch_target_name, true)

proj.save
puts "Added target #{watch_target_name}"
