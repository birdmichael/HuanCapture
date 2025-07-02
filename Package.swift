// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HuanCapture",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "HuanCapture",
            targets: ["HuanCapture"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hanliang-tech/es-cast-client-ios", from: "0.1.15")
    ],
    targets: [
        .binaryTarget(
            name: "WebRTC",
            path: "Frameworks/WebRTC.xcframework"
        ),

        .target(
            name: "HuanCapture",
            dependencies: [
                .target(name: "WebRTC"),
                .product(name: "es-cast-client-ios", package: "es-cast-client-ios")
            ],
            path: "Sources/HuanCapture"
        )
    ]
)
