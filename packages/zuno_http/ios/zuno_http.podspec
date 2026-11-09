Pod::Spec.new do |s|
  s.name             = 'zuno_http'
  s.version          = '0.0.1'
  s.summary          = 'Zuno HTTP and WebSocket clients on URLSession.'
  s.description      = 'Zuno HTTP and WebSocket clients on URLSession.'
  s.homepage         = 'https://zuno.chat'
  s.license          = { :file => '../LICENSE', :type => 'AGPL-3.0' }
  s.author           = 'Zuno'
  s.source           = { :path => '.' }
  s.source_files     = 'zuno_http/Sources/zuno_http/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
end
