# HuanCapture

HuanCapture是一个为macOS/iOS设计的Swift视频捕获和WebRTC集成库，特别适合与SwiftUI搭配使用。

## 演示截图

<div align="center">
  <img src="demo1.PNG" width="70%" alt="Demo 1">
  <br><br>
  <img src="demo2.PNG" width="70%" alt="Demo 2">
</div>

## 功能特点

- 简单易用的视频捕获和WebRTC集成
- 完全支持SwiftUI架构
- 提供前后摄像头切换功能
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

### 4. WebRTC集成

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

## 注意事项

1. 确保在Info.plist中添加相机使用权限：
   - 对于iOS：`NSCameraUsageDescription`和`NSMicrophoneUsageDescription`
   - 对于macOS：`NSCameraUsageDescription`和`NSMicrophoneUsageDescription`

2. WebRTC依赖于网络连接，建议在良好的网络环境中使用。

3. 对于生产环境，您需要实现一个可靠的信令服务器来处理WebRTC的信令交换。

## 许可证

[此处添加您的许可证信息]
