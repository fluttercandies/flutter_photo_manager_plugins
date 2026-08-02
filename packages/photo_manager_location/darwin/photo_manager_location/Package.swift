// swift-tools-version: 5.9

// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import PackageDescription

let packageName = "photo_manager_location"

let package = Package(
  name: packageName,
  platforms: [
    .iOS("9.0"),
    .macOS("10.15")
  ],
  products: [
    .library(name: "photo-manager-location", targets: [packageName])
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
      cSettings: [
        .headerSearchPath("include/\(packageName)")
      ]
    ),
  ]
)
