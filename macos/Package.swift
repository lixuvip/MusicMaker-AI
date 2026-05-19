// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MusicMaker-AI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MusicMaker-AI", targets: ["MusicMakerAI"])
    ],
    targets: [
        .executableTarget(
            name: "MusicMakerAI",
            path: "Sources/MusicMakerAI",
            resources: [
                .copy("../../Support/VoxCPM")
            ]
        )
    ]
)
