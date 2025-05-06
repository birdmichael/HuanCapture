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
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "WebRTC",
            path: "Frameworks/WebRTC.xcframework"
        ),

        .target(
            name: "HuanCapture",
            dependencies: [
                .target(name: "WebRTC")
            ],
            path: "Sources/HuanCapture"
        )
    ]
)
