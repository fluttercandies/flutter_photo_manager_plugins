package_name = 'photo_manager_location'
pubspec = YAML.load_file(File.join('..', 'pubspec.yaml'))
library_version = pubspec['version'].gsub('+', '-')

Pod::Spec.new do |s|
  s.name             = package_name
  s.version          = library_version
  s.summary          = 'Save photos and videos with location coordinates on iOS/macOS for photo_manager.'
  s.description      = <<-DESC
An opt-in Flutter plugin that links CoreLocation so photo_manager consumers
can save assets tagged with geographic coordinates. Use this only when you
need location-tagged saves; the core photo_manager package stays
CoreLocation-free so apps that never save with location are not flagged by
Apple's static scan.
                       DESC
  s.homepage         = 'https://github.com/fluttercandies/flutter_photo_manager_plugins/tree/main/packages/photo_manager_location'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'FlutterCandies' => 'fluttercandies@googlegroups.com' }
  s.source           = { :http => 'https://github.com/fluttercandies/flutter_photo_manager_plugins' }

  s.source_files = "#{package_name}/Sources/#{package_name}/**/*"
  s.public_header_files = "#{package_name}/Sources/#{package_name}/**/**/*.h"

  s.osx.dependency 'FlutterMacOS'
  s.ios.dependency 'Flutter'

  s.ios.frameworks = 'Photos', 'PhotosUI', 'CoreLocation'
  s.osx.frameworks = 'Photos', 'PhotosUI', 'CoreLocation'

  s.ios.deployment_target = '9.0'
  s.osx.deployment_target = '10.15'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
