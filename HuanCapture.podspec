Pod::Spec.new do |s|
  s.name             = 'HuanCapture'
  s.version          = '0.1.9'
  s.summary          = 'Screen and audio capture library for iOS.'
  s.homepage         = 'https://github.com/birdmichael/HuanCapture'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'birdmichael' => 'your.email@example.com' }
  s.source           = { :git => 'https://github.com/birdmichael/HuanCapture.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'

  s.source_files = 'Sources/HuanCapture/**/*.swift'

  s.dependency 'es-cast-client-ios', '0.1.15'

  s.vendored_frameworks = 'Frameworks/WebRTC.xcframework'
  s.frameworks = 'UIKit', 'AVFoundation', 'CoreMedia', 'CoreVideo', 'AudioToolbox', 'VideoToolbox', 'OSLog'

end
