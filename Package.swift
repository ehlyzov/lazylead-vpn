// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LazyleadVPN",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LazyleadVPN", targets: ["LazyleadVPN"]),
        .executable(name: "LazyleadVPNCoreSelfTest", targets: ["LazyleadVPNCoreSelfTest"]),
        .library(name: "LazyleadVPNCore", targets: ["LazyleadVPNCore"])
    ],
    targets: [
        .target(name: "LazyleadVPNCore"),
        .executableTarget(
            name: "LazyleadVPN",
            dependencies: ["LazyleadVPNCore"]
        ),
        .executableTarget(
            name: "LazyleadVPNCoreSelfTest",
            dependencies: ["LazyleadVPNCore"]
        )
    ]
)
