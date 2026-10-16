// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentHighlight",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HighlightKit", targets: ["HighlightKit"]),
        .executable(name: "AgentHighlightApp", targets: ["AgentHighlightApp"]),
        .executable(name: "hl", targets: ["hl"]),
    ],
    targets: [
        .target(name: "HighlightKit"),
        .executableTarget(
            name: "AgentHighlightApp",
            dependencies: ["HighlightKit"]
        ),
        .executableTarget(
            name: "hl",
            dependencies: ["HighlightKit"]
        ),
    ]
)
