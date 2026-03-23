// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VisionOS-UI-Framework",
    platforms: [
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "VisionUI",
            targets: ["VisionUI"]
        ),
        .library(
            name: "VisionUISpatial",
            targets: ["VisionUISpatial"]
        ),
        .library(
            name: "VisionUIGestures",
            targets: ["VisionUIGestures"]
        ),
        .library(
            name: "VisionUIAccessibility",
            targets: ["VisionUIAccessibility"]
        )
    ],
    targets: [
        .target(
            name: "VisionUI",
            dependencies: [
                "VisionUISpatial",
                "VisionUIGestures",
                "VisionUIAccessibility"
            ],
            path: "Sources/VisionUI"
        ),
        .target(
            name: "VisionUISpatial",
            path: "Sources/VisionUISpatial"
        ),
        .target(
            name: "VisionUIGestures",
            dependencies: [
                "VisionUISpatial"
            ],
            path: "Sources/VisionUIGestures"
        ),
        .target(
            name: "VisionUIAccessibility",
            dependencies: [
                "VisionUISpatial"
            ],
            path: "Sources/VisionUIAccessibility"
        )
    ]
)
