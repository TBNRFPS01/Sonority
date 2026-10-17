// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SonorityCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SonorityCore", targets: ["SonorityCore"])],
    targets: [
        .target(name: "SonorityCore", path: "Core"),
        .testTarget(name: "SonorityCoreTests", dependencies: ["SonorityCore"], path: "Tests")
    ]
)
