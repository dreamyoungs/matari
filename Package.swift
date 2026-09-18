// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Matari",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MatariCore", targets: ["MatariCore"]),
        .executable(name: "matari-smoke", targets: ["MatariSmoke"])
    ],
    targets: [
        .target(
            name: "MatariCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "MatariCoreTests",
            dependencies: ["MatariCore"]
        ),
        .executableTarget(
            name: "MatariSmoke",
            dependencies: ["MatariCore"]
        )
    ]
)
