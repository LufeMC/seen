// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RewindButFast",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "RewindButFast", targets: ["RewindButFast"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "RewindCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "RewindButFast", dependencies: ["RewindCore"]),
        .testTarget(name: "RewindCoreTests", dependencies: ["RewindCore"]),
        .testTarget(name: "RewindAppTests", dependencies: ["RewindButFast", "RewindCore"])
    ],
    swiftLanguageModes: [.v5]
)
