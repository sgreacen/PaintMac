// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PaintMac",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PaintMac", targets: ["PaintMac"])],
    targets: [
        .target(name: "PaintCore", path: "scripts/Sources/PaintCore"),
        .executableTarget(
            name: "PaintMac",
            dependencies: ["PaintCore"],
            path: "scripts/Sources/PaintMac",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "PaintCoreChecks",
            dependencies: ["PaintCore"],
            path: "scripts/Sources/PaintCoreChecks"
        )
    ]
)
