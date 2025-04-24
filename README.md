# HuanCapture

HuanCapture是一个为macOS/iOS设计的Swift视频捕获和WebRTC集成库，特别适合与SwiftUI搭配使用。它提供了简单的API来捕获和流式传输高质量视频，并内置了WebRTC信令服务器。

## 演示截图

<div align="center">
  <img src="demo1.PNG" width="45%" alt="Demo 1">
  <img src="demo2.PNG" width="45%" alt="Demo 2">
  <br><br>
  <img src="demo3.PNG" width="45%" alt="Demo 3">
  <img src="demo4.png" width="45%" alt="Demo 4">
</div>

## 功能特点

- 简单易用的视频捕获和WebRTC集成
- 完全支持SwiftUI架构
- 提供前后摄像头切换功能
- **支持后置摄像头类型切换**（广角、长焦、超广角）
- 实时视频预览
- WebRTC信令状态监控
- 支持自定义配置
- 针对iOS和macOS平台优化

## 安装要求

- iOS 14.0+ / macOS 11.0+
- Swift 5.3+
- Xcode 13.0+

## 快速开始

### 1. 初始化HuanCaptureManager

```swift
import SwiftUI
import HuanCapture

class YourViewModel: ObservableObject {
    let captureManager = HuanCaptureManager()
    
    // 其他代码...
}
```

### 2. 在SwiftUI中使用预览视图

```swift
struct ContentView: View {
    @StateObject private var viewModel = YourViewModel()
    
    var body: some View {
        VStack {
            // 使用HuanCaptureManager的预览视图
            UIViewRepresentable(viewModel.captureManager.previewView)
                .aspectRatio(contentMode: .fill)
                .frame(height: 300)
                .cornerRadius(12)
                .clipped()
            
            // 控制按钮
            HStack {
                Button("开始") {
                    viewModel.captureManager.startStreaming()
                }
                
                Button("停止") {
                    viewModel.captureManager.stopStreaming()
                }
                
                Button("切换摄像头") {
                    viewModel.captureManager.switchCamera()
                }
            }
        }
        .padding()
    }
}

// 用于将UIView包装为SwiftUI视图的Helper
struct UIViewRepresentable: UIViewRepresentable {
    let uiView: UIView
    
    init(_ uiView: UIView) {
        self.uiView = uiView
    }
    
    func makeUIView(context: Context) -> UIView {
        return uiView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // 更新UI视图（如果需要）
    }
}
```

### 3. 监听状态变化

HuanCaptureManager实现了ObservableObject，提供了多个@Published属性用于监控状态：

```swift
struct ContentView: View {
    @StateObject private var viewModel = YourViewModel()
    
    var body: some View {
        VStack {
            // 预览视图
            
            // 显示连接状态
            Text("连接状态: \(viewModel.captureManager.connectionState.description)")
                .padding()
            
            // 显示错误信息（如果有）
            if let error = viewModel.captureManager.captureError {
                Text("错误: \(error.localizedDescription)")
                    .foregroundColor(.red)
                    .padding()
            }
            
            // 显示当前使用的摄像头
            Text("当前摄像头: \(viewModel.captureManager.currentCameraPosition == .back ? "后置" : "前置")")
                .padding()
        }
    }
}
```

### 4. 后置摄像头类型切换

对于支持多摄像头的iOS设备，HuanCapture提供两种方式在后置摄像头模式下切换不同类型的摄像头：

#### 循环切换到下一个摄像头类型

```swift
// 检查当前摄像头位置
// 循环切换到下一个后置摄像头类型 (广角 -> 长焦 -> 超广角 -> 广角)
if let nextType = captureManager.switchBackCameraType() {
    print("成功切换到下一个摄像头类型: \(nextType.localizedName)")
}
```

#### 直接切换到指定摄像头类型

```swift
// 查看可用的后置摄像头类型
let availableTypes = captureManager.availableBackCameraTypes

// 切换到指定类型的摄像头
if let resultType = captureManager.switchToBackCameraType(.telephoto) {
    print("成功切换到: \(resultType.localizedName)")
} else {
    print("切换失败，该类型可能不可用")
}

// 尝试切换到超广角摄像头
_ = captureManager.switchToBackCameraType(.ultraWide)
```

#### 获取当前摄像头类型

```swift
// 获取当前摄像头类型
let cameraType = captureManager.currentCameraType
switch cameraType {
case .wideAngle:
    print("当前使用广角摄像头")
case .telephoto:
    print("当前使用长焦摄像头")
case .ultraWide:
    print("当前使用超广角摄像头")
}
```

> 注意：系统在初始化时会自动检测当前设备支持的摄像头类型，并将其存储在`availableBackCameraTypes`数组中。如果尝试切换到不可用的摄像头类型，方法会返回`nil`。

### 5. WebRTC集成

为了完成WebRTC通信，您需要处理会话描述协议(SDP)交换和ICE候选者：

```swift
class YourViewModel: ObservableObject {
    let captureManager = HuanCaptureManager()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // 订阅localSDP变化
        captureManager.$localSDP
            .compactMap { $0 }
            .sink { [weak self] sdp in
                // 将本地SDP发送到您的信令服务器
                self?.sendSDPToSignalingServer(sdp)
            }
            .store(in: &cancellables)
        
        // 订阅ICE候选者
        captureManager.iceCandidateSubject
            .sink { [weak self] candidate in
                // 将ICE候选者发送到您的信令服务器
                self?.sendICECandidateToSignalingServer(candidate)
            }
            .store(in: &cancellables)
    }
    
    // 从信令服务器接收远程SDP
    func didReceiveRemoteSDP(_ sdp: RTCSessionDescription) {
        captureManager.setRemoteDescription(sdp)
    }
    
    // 从信令服务器接收ICE候选者
    func didReceiveICECandidate(_ candidate: RTCIceCandidate) {
        captureManager.addICECandidate(candidate)
    }
    
    // 示例方法 - 需要实现与您的信令服务器通信
    private func sendSDPToSignalingServer(_ sdp: RTCSessionDescription) {
        // 实现与您的信令服务器的通信
    }
    
    private func sendICECandidateToSignalingServer(_ candidate: RTCIceCandidate) {
        // 实现与您的信令服务器的通信
    }
}
```

## 高级用法

### 设置预览镜像

对于前置摄像头，通常需要镜像预览：

```swift
// 当切换到前置摄像头时设置镜像
if viewModel.captureManager.currentCameraPosition == .front {
    viewModel.captureManager.setPreviewMirrored(true)
} else {
    viewModel.captureManager.setPreviewMirrored(false)
}
```

### 设备方向处理

为了正确处理视频旋转，需要更新设备方向：

```swift
// 在视图控制器中监听设备方向变化
NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
    guard let self = self else { return }
    let deviceOrientation = UIDevice.current.orientation
    if deviceOrientation.isPortrait || deviceOrientation.isLandscape {
        self.viewModel.captureManager.deviceOrientation = deviceOrientation
    }
}
```

### 自定义日志

您可以控制内部日志输出：

```swift
// 禁用内部日志
captureManager.isLoggingEnabled = false
```

### 监听连接状态变化

```swift
captureManager.$connectionState
    .sink { state in
        switch state {
        case .connected, .completed:
            print("WebRTC连接已建立")
        case .disconnected:
            print("WebRTC连接已断开")
        case .failed:
            print("WebRTC连接失败")
        case .closed:
            print("WebRTC连接已关闭")
        default:
            print("WebRTC连接状态: \(state.description)")
        }
    }
    .store(in: &cancellables)
```

## 错误处理

HuanCaptureManager提供了`captureError`属性，您可以监控该属性以处理任何可能出现的错误：

```swift
captureManager.$captureError
    .compactMap { $0 }
    .sink { error in
        print("捕获错误: \(error.localizedDescription)")
        // 显示错误给用户或尝试恢复
    }
    .store(in: &cancellables)
```

## 示例应用

在Demo目录中提供了一个完整的示例应用，展示了如何在SwiftUI应用中使用HuanCapture库。查看`Demo/ContentView.swift`以获取更多灵感。

## HuanCapture WebRTC Viewer 部署指南

HuanCapture 内置了 WebSocket 信令服务器，但您需要一个 Web 客户端来接收和显示视频流。以下是部署 HuanCapture WebRTC Viewer 的步骤：

### 1. 准备 Web 客户端文件

在 `Play` 目录中已经包含了一个完整的 WebRTC Viewer 实现，包括以下文件：

- `index.html` - 网页界面
- `main.js` - WebRTC 客户端逻辑
- `styles.css` - 样式表
- `server.js` - 简单的 Web 服务器

### 2. 安装依赖

确保您已安装 Node.js，然后在 `Play` 目录中运行：

```bash
npm install
```

这将安装所需的依赖项（express、cors 等）。

### 3. 启动 Web 服务器

在 `Play` 目录中运行：

```bash
npm start
```

或者直接运行：

```bash
node server.js
```

服务器将在 http://localhost:3000 上启动。

### 4. 配置 iOS/macOS 应用

在您的 iOS 或 macOS 应用中，确保 HuanCaptureManager 配置了正确的 WebSocket 端口：

```swift
let config = HuanCaptureConfig(
    enableWebSocketSignaling: true,
    webSocketPort: 8080,  // 默认端口，确保与 Web 客户端匹配
    isLoggingEnabled: true
)

let captureManager = HuanCaptureManager(config: config)
```

### 5. 连接 Web 客户端

1. 在浏览器中打开 http://localhost:3000
2. 在 WebSocket 地址输入框中输入：`ws://[您的设备IP地址]:8080`
3. 点击"连接"按钮

如果一切配置正确，Web 客户端将连接到您的 iOS/macOS 应用，并开始接收视频流。

### 6. 网络注意事项

- 确保您的 iOS/macOS 设备和运行 Web 客户端的计算机在同一网络中
- 如果使用防火墙，确保允许 WebSocket 端口（默认 8080）的通信
- 对于公共网络或互联网访问，您可能需要配置 NAT 穿透或使用 TURN 服务器

### 7. 自定义 Web 客户端

您可以根据需要自定义 Web 客户端的外观和功能：

- 修改 `styles.css` 更改界面样式
- 编辑 `index.html` 调整布局
- 在 `main.js` 中添加更多功能，如录制、截图等

## 注意事项

1. 确保在Info.plist中添加相机使用权限：
   - 对于iOS：`NSCameraUsageDescription`和`NSMicrophoneUsageDescription`
   - 对于macOS：`NSCameraUsageDescription`和`NSMicrophoneUsageDescription`

2. WebRTC依赖于网络连接，建议在良好的网络环境中使用。

3. 默认配置适用于局域网环境。对于公共网络或互联网访问，您需要配置 STUN/TURN 服务器。

4. 在生产环境中，建议使用 HTTPS 和 WSS（WebSocket Secure）以确保通信安全。

## 许可证

[此处添加您的许可证信息]
