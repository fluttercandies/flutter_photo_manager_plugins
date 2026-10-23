// swift-tools-version: 5.9

import PackageDescription

let packageName = "photo_manager_native_image"

let package = Package(
  name: packageName,
  platforms: [
    .iOS("13.0")
  ],
  products: [
    .library(name: "photo-manager-native-image", targets: [packageName])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: packageName,
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ],
      resources: [
        .process("Resources")
      ]
    ),
  ]
)
