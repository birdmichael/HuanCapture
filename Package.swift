// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HuanCapture",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "HuanCapture",
            targets: ["HuanCapture"]), // 主要的HuanCapture库产品
    ],
    dependencies: [],
    targets: [
        // 1. 定义WebRTC框架的二进制目标
        .binaryTarget(
            name: "WebRTC", // 这是WebRTC框架在SPM中的标识
            path: "Frameworks/WebRTC.xcframework" // 框架文件路径
        ),

        // 2. 定义HuanCapture Swift代码目标
        .target(
            name: "HuanCapture", // HuanCapture代码目标名称
            dependencies: [
                // 3. 声明HuanCapture依赖于上面定义的WebRTC二进制目标
                .target(name: "WebRTC")
            ],
            path: "Sources/HuanCapture" // HuanCapture源代码路径
        )
    ]
)
