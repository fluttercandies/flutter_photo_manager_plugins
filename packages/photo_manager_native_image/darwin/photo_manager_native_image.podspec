package_name = 'photo_manager_native_image'
pubspec = YAML.load_file(File.join('..', 'pubspec.yaml'))
library_version = pubspec['version'].gsub('+', '-')

Pod::Spec.new do |s|
  s.name             = package_name
  s.version          = library_version
  s.summary          = 'Native RGBA thumbnails for photo_manager assets.'
  s.description      = <<-DESC
Decodes PhotoKit thumbnails to RGBA on a worker queue and hands Flutter the
pixel buffer, with no JPEG round trip.
                       DESC
  s.homepage         = 'https://github.com/fluttercandies/flutter_photo_manager_plugins/tree/main/packages/photo_manager_native_image'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'FlutterCandies' => 'fluttercandies@googlegroups.com' }
  s.source           = { :http => 'https://github.com/fluttercandies/flutter_photo_manager_plugins' }

  s.source_files = "#{package_name}/Sources/#{package_name}/**/*.{swift,h,m}"

  s.dependency 'Flutter'

  s.frameworks = 'Photos', 'Accelerate'

  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  s.resource_bundles = {
    "#{package_name}_privacy" => [
      "#{package_name}/Sources/#{package_name}/Resources/PrivacyInfo.xcprivacy"
    ]
  }
end
