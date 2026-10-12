// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PortalKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "PortalKit", targets: ["PortalKit"])
    ],
    targets: [
        .target(
            name: "PortalKit",
            resources: [.copy("Resources/Fixtures")]
        ),
        .testTarget(
            name: "PortalKitTests",
            dependencies: ["PortalKit"]
        )
    ]
)
