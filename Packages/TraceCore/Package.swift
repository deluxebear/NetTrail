// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TraceCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TraceCore", targets: ["TraceCore"]),
        .library(name: "TraceKit", targets: ["TraceKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "TraceCore"),
        .target(name: "TraceKit", dependencies: [
            "TraceCore",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .testTarget(name: "TraceCoreTests", dependencies: ["TraceCore"]),
        .testTarget(name: "TraceKitTests", dependencies: ["TraceKit"]),
    ]
)
