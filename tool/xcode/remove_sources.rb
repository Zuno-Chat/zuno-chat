require 'xcodeproj'

paths = ARGV
abort('usage: ruby tool/xcode/remove_sources.rb ios/<group>/<file>...') if paths.empty?
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
paths.each do |path|
  abort("#{path} has an empty, . or .. segment") if path.split('/', -1).any? { |segment| ['', '.', '..'].include?(segment) }
  abort("#{path} still exists; delete the file first") if File.exist?(path)
  directory, file = File.split(path.delete_prefix('ios/'))
  abort("#{path} is not ios/<group>/<file>") if directory == '.'
  group = project.main_group.find_subpath(directory, false)
  abort("#{path}: no group #{directory}") unless group
  reference = group.files.find { |candidate| candidate.path == file }
  abort("#{path}: no reference #{file} in #{directory}") unless reference
  resolved = reference.real_path.to_s
  abort("#{path} resolves to #{resolved.delete_prefix("#{Dir.pwd}/")}") unless resolved == File.expand_path(path)
  reference.remove_from_project
end
abort("objectVersion is #{project.object_version}, not 60; nothing saved") unless project.object_version == '60'
project.save
version = File.read('ios/Runner.xcodeproj/project.pbxproj')[/objectVersion = (\d+);/, 1]
abort("objectVersion is #{version}, not 60") unless version == '60'
puts "removed: #{paths.join(', ')}"
