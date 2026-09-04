// swift-tools-version: 5.9
import PackageDescription

// The Xcode project does NOT consume this package (RightKitShared is compiled as a
// plain static framework target in project.yml). This manifest exists so the domain
// layer can be built and tested from the CLI without Xcode:
//     cd Packages/RightKitShared && swift test
let package = Package(
    name: "RightKitShared",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "RightKitShared", targets: ["RightKitShared"])
    ],
    targets: [
        .target(name: "RightKitShared", path: "Sources/RightKitShared"),
        .testTarget(
            name: "RightKitSharedTests",
            dependencies: ["RightKitShared"],
            path: "Tests/RightKitSharedTests"
        )
    ]
)
