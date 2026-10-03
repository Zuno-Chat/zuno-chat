require 'xcodeproj'

target_name, *paths = ARGV
abort('usage: ruby tool/xcode/add_sources.rb <target> ios/<group>/<file>...') if paths.empty?
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
target = project.targets.find { |candidate| candidate.name == target_name }
abort("no target #{target_name}") unless target
paths.each do |path|
  abort("#{path} does not exist") unless File.file?(path)
  abort("#{path} has an empty, . or .. segment") if path.split('/', -1).any? { |segment| ['', '.', '..'].include?(segment) }
  directory, file = File.split(path.delete_prefix('ios/'))
  abort("#{path} is not ios/<group>/<file>") if directory == '.'
  parent = project.main_group
  directory.split('/').each do |name|
    same = parent.groups.find { |candidate| candidate.display_name.to_s == name }
    other = parent.groups.find { |candidate| candidate.display_name.to_s.casecmp?(name) }
    abort("#{path}: #{name} differs only in case from the group #{other.display_name}") if other && !same
    break unless same
    parent = same
  end
  group = project.main_group.find_subpath(directory)
  unless group
    group = project.main_group.find_subpath(directory, true)
    group.path = File.basename(directory)
  end
  existing = group.files.find { |candidate| candidate.path == file }
  lookalike = group.files.find { |candidate| candidate.path.to_s.casecmp?(file) }
  abort("#{path}: #{file} differs only in case from the reference #{lookalike.path}") if lookalike && !existing
  reference = existing || group.new_reference(file)
  resolved = reference.real_path.to_s
  abort("#{path} would resolve to #{resolved.delete_prefix("#{Dir.pwd}/")}") unless resolved == File.expand_path(path)
  next if target.source_build_phase.files_references.include?(reference)
  target.source_build_phase.add_file_reference(reference, true)
end
abort("objectVersion is #{project.object_version}, not 60; nothing saved") unless project.object_version == '60'
project.save
version = File.read('ios/Runner.xcodeproj/project.pbxproj')[/objectVersion = (\d+);/, 1]
abort("objectVersion is #{version}, not 60") unless version == '60'
puts "#{target_name}: #{paths.join(', ')}"
