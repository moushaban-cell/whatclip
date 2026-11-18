// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhatClip",
    platforms: [.macOS(.v14)],
    products: [.library(name: "WhatClipCore", targets: ["WhatClipCore"])],
    targets: [
        .executableTarget(name: "WhatClip", dependencies: ["WhatClipCore"]),
        .target(name: "WhatClipCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "WhatClipCoreTests", dependencies: ["WhatClipCore"]),
    ]
)
