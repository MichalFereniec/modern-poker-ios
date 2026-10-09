// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ModernPokerCore",
    platforms: [.macOS(.v15), .iOS("26.4")],
    products: [.library(name: "ModernPokerCore", targets: ["ModernPokerCore"])],
    targets: [
        .target(name: "ModernPokerCore", path: "ModernPoker/Core"),
        .testTarget(name: "ModernPokerCoreTests", dependencies: ["ModernPokerCore"], path: "Tests", exclude: ["Fixtures"])
    ]
)
