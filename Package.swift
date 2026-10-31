// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoViewer",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "PhotoViewer", targets: ["PhotoViewer"]),
        .executable(name: "PhotoViewerChecks", targets: ["PhotoViewerChecks"])
    ],
    targets: [
        .target(
            name: "PhotoViewerCore",
            path: "Sources/PhotoViewerCore"
        ),
        .executableTarget(
            name: "PhotoViewer",
            dependencies: ["PhotoViewerCore"],
            path: "Sources/PhotoViewer"
        ),
        .executableTarget(
            name: "PhotoViewerChecks",
            dependencies: ["PhotoViewerCore"],
            path: "Tools/PhotoViewerChecks"
        )
    ]
)
