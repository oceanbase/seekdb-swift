// swift-tools-version: 5.9
// Copyright (c) 2025 OceanBase.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import PackageDescription

let engineFramework = "build/SeekDBEngine.xcframework"
let releasedEngine = "https://github.com/oceanbase/seekdb-swift/releases/download/0.1.0/SeekDBEngine.xcframework.zip"
let releasedEngineChecksum = "20eb7bcb6f20912887251b13cd3819e9ac0a6cf043175135c6591060e79a783e"
let engine: Target = FileManager.default.fileExists(atPath: Context.packageDirectory + "/" + engineFramework)
    ? .binaryTarget(name: "SeekDBEngine", path: engineFramework)
    : .binaryTarget(name: "SeekDBEngine", url: releasedEngine, checksum: releasedEngineChecksum)

let package = Package(
    name: "seekdb-bindings",
    platforms: [.macOS(.v13), .iOS("18.0")],
    products: [.library(name: "SeekDB", targets: ["SeekDB"])],
    targets: [
        .systemLibrary(name: "CSeekDB"),
        .target(
            name: "SeekDB",
            dependencies: ["CSeekDB", "SeekDBEngine"],
            swiftSettings: [.enableExperimentalFeature("CheckImplementationOnly")]
        ),
        engine
    ]
)
