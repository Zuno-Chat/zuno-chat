require 'xcodeproj'

name = 'NotificationService'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
abort("#{name} already exists") if project.targets.any? { |target| target.name == name }
runner = project.targets.find { |target| target.name == 'Runner' } || abort('no Runner target')
shared = project.main_group.find_subpath('NotifyShared', false) || abort('no NotifyShared group')
runner_group = project.main_group.find_subpath('Runner', false) || abort('no Runner group')

def reference(group, file)
  abort("#{group.path}/#{file} does not exist") unless File.file?(File.join('ios', group.path, file))
  group.files.find { |candidate| candidate.path == file } || group.new_reference(file)
end

group = project.main_group.find_subpath(name, true)
group.path ||= name
service = reference(group, 'NotificationService.swift')
xcconfig = reference(group, "#{name}.xcconfig")
%W[Info.plist #{name}.entitlements #{name}-Bridging-Header.h].each { |file| reference(group, file) }
privacy = reference(group, 'PrivacyInfo.xcprivacy')
reference(shared, 'ZunoMegolmABI.h')
ring = reference(runner_group, 'fallback_ring.caf')

target = project.new_target(:app_extension, name, :ios, '15.0', nil, :swift)
target.frameworks_build_phase.files.to_a.each do |build_file|
  framework = build_file.file_ref
  build_file.remove_from_project
  next unless framework && framework.build_files.empty?
  holder = framework.parent
  framework.remove_from_project
  holder.remove_from_project if holder.is_a?(Xcodeproj::Project::Object::PBXGroup) && holder.children.empty? && holder != project.frameworks_group
end
target.build_configurations.each do |config|
  config.base_configuration_reference = xcconfig
  config.build_settings = {
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'CLANG_ENABLE_MODULES' => 'YES',
    'CODE_SIGN_ENTITLEMENTS' => "#{name}/#{name}.entitlements",
    'DEVELOPMENT_TEAM' => '5V9UP3J9CK',
    'INFOPLIST_FILE' => "#{name}/Info.plist",
    'IPHONEOS_DEPLOYMENT_TARGET' => '15.0',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
    'PRODUCT_BUNDLE_IDENTIFIER' => 'im.zuno.chat.NotificationService',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'SDKROOT' => 'iphoneos',
    'SKIP_INSTALL' => 'YES',
    'SWIFT_OBJC_BRIDGING_HEADER' => "#{name}/#{name}-Bridging-Header.h",
    'SWIFT_VERSION' => '6.0',
    'VERSIONING_SYSTEM' => 'apple-generic',
  }
  config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if config.name == 'Debug'
end
if target.build_configurations.none? { |config| config.name == 'Profile' }
  release = target.build_configurations.find { |config| config.name == 'Release' }
  profile = target.add_build_configuration('Profile', :release)
  profile.base_configuration_reference = xcconfig
  profile.build_settings = release.build_settings.dup
end
target.source_build_phase.add_file_reference(service, true)
target.resources_build_phase.add_file_reference(privacy, true)
runner.resources_build_phase.add_file_reference(ring, true) unless runner.resources_build_phase.files_references.include?(ring)

embed = runner.copy_files_build_phases.find { |phase| phase.name == 'Embed Foundation Extensions' } || abort('no Embed Foundation Extensions phase')
embed.add_file_reference(target.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
runner.add_dependency(target)

project.root_object.build_configuration_list.build_configurations.each do |config|
  config.build_settings['ZUNO_NOTIFY_GROUP'] ||= 'group.im.zuno.chat.notify.$(DEVELOPMENT_TEAM)'
end

phases = runner.build_phases.map(&:display_name)
abort('Embed Foundation Extensions must stay above Run Script') unless phases.index('Embed Foundation Extensions') < phases.index('Run Script')
project.save
version = File.read('ios/Runner.xcodeproj/project.pbxproj')[/objectVersion = (\d+);/, 1]
abort("objectVersion is #{version}, not 60") unless version == '60'
puts "#{name}: target, #{target.build_configurations.map(&:name).sort.join('/')}, embedded in Runner"
