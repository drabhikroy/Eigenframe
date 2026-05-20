// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Eigenframe",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Eigenframe",
            path: "Eigenframe",
            exclude: [
                "Info.plist"
            ],
            resources: [
                .copy("Help.html")
            ]
        ),
        .testTarget(
            name: "EigenframeTests",
            dependencies: [],
            path: "Tests/EigenframeTests"
        )
    ]
)
