// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexUsageAnalyzer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexUsageAnalyzer", targets: ["CodexUsageAnalyzer"])
    ],
    targets: [
        .executableTarget(
            name: "CodexUsageAnalyzer",
            path: "Sources/CodexUsageAnalyzer",
            linkerSettings: [.linkedFramework("WebKit")]
        ),
        .testTarget(
            name: "CodexUsageAnalyzerTests",
            dependencies: ["CodexUsageAnalyzer"],
            path: "Tests/CodexUsageAnalyzerTests",
            resources: [.process("Fixtures")]
        )
    ]
)
