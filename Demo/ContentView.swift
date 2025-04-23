//
//  ContentView.swift
//  Demo
//
//  Created by BM on 2025/4/23.
//

import SwiftUI
import WebRTC
// **重新添加 import HuanCapture**
import HuanCapture
// **不再需要显式导入 HuanCapture，因为它通过 @StateObject 访问**
// import HuanCapture
import OSLog
import Combine // **导入 Combine**

// **移除 LocalVideoView struct**
/*
struct LocalVideoView: UIViewRepresentable {
    // 从 HuanCapture 获取的视频轨道
    // **修改：现在直接传入 track**
    let videoTrack: RTCVideoTrack
    // 是否镜像显示
    var isMirrored: Bool = false

    // 创建 UIView (RTCMTLVideoView)
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill // 填充视图，可能会裁剪
        // view.videoContentMode = .scaleAspectFit // 适应视图，可能会有黑边
        // **直接添加 track**
        videoTrack.add(view)
        print("LocalVideoView: Added track to RTCMTLVideoView")
        return view
    }

    // 更新 UIView
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        // 应用镜像效果
        uiView.transform = isMirrored ? CGAffineTransform(scaleX: -1.0, y: 1.0) : .identity
        print("LocalVideoView: Updating view, isMirrored: \(isMirrored)")
        // **如果需要，可以检查 track 是否变化并重新添加，但此处简化**
    }
}
*/

// **新增：简单的 UIViewRepresentable 来包装 HuanCapture 提供的 UIView**
struct CapturePreviewRepresentable: UIViewRepresentable {
    let captureView: UIView

    func makeUIView(context: Context) -> UIView {
        return captureView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // 通常不需要操作，因为视图由 HuanCapture 管理
        // 如果 captureView 实例可能改变（在此例中不会，因为是 let），则需要更新
    }
}

struct ContentView: View {
    // 使用 @StateObject 来管理 HuanCapture 实例的生命周期
    // **HuanCapture 现在是 ObservableObject，这可以编译通过**
    // **使用重命名后的类**
    @StateObject private var huanCapture = HuanCaptureManager()

    // UI 状态变量
    @State private var isStreaming = false
    // **重新添加 isMirrored state**
    @State private var isMirrored = false // 初始设为 false (后置摄像头)
    @State private var statusText = "准备就绪"
    @State private var localSDPString = "" // 用于显示 SDP
    @State private var iceCandidatesString = "" // 用于显示 ICE Candidates
    // **新增：用于保存收到的 ICE Candidates 列表**
    @State private var receivedCandidates: [RTCIceCandidate] = []

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ContentView")

    var body: some View {
        VStack(spacing: 15) {
            Text("HuanCapture Demo")
                .font(.largeTitle)
                .padding(.top)

            // 视频预览区域
            ZStack {
                // **使用 CapturePreviewRepresentable 并传入 huanCapture.previewView**
                CapturePreviewRepresentable(captureView: huanCapture.previewView)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3/4, contentMode: .fit)
                    .background(Color.gray.opacity(0.5))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                           .stroke(Color.blue, lineWidth: isStreaming ? 3 : 0)
                    )
                    .animation(.easeInOut, value: isStreaming)
                    .onAppear { print("ContentView: CapturePreviewRepresentable appeared") }

                 // 状态文本叠加在视频上方
                VStack {
                     Spacer()
                     Text(statusText)
                         .font(.caption)
                         .padding(5)
                         .background(Color.black.opacity(0.6))
                         .foregroundColor(.white)
                         .cornerRadius(5)
                         .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal)

            // 控制按钮区域
            HStack(spacing: 20) {
                // 开始/停止按钮
                Button {
                    toggleStreaming()
                } label: {
                    Label(isStreaming ? "停止推流" : "开始推流", systemImage: isStreaming ? "stop.circle.fill" : "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(isStreaming ? .red : .green)
                 // **移除 disabled modifier (或根据需要调整)**
                 // .disabled(getVideoTrack() == nil)

                // 切换摄像头按钮
                Button {
                    huanCapture.switchCamera()
                } label: {
                    Label("切换镜头", systemImage: "arrow.triangle.2.circlepath.camera.fill")
                }
                .buttonStyle(.bordered)
                 // **移除 disabled modifier (或根据需要调整)**
                 // .disabled(getVideoTrack() == nil)

                // **重新添加镜像 Toggle 按钮**
                Toggle(isOn: $isMirrored) {
                    Label("镜像", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                // **根据状态设置 Tint**
                .tint(isMirrored ? .indigo : .gray)
            }
            .padding(.horizontal)

            // 显示 SDP 和 ICE Candidate 的区域
            GroupBox("信令信息 (仅供调试)") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !localSDPString.isEmpty {
                            Text("本地 Offer SDP:")
                                .font(.headline)
                             // **使用 localSDPString**
                            Text(localSDPString)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(5)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(5)
                        }
                        if !iceCandidatesString.isEmpty {
                             Divider()
                            Text("本地 ICE Candidates:")
                                .font(.headline)
                             // **使用 iceCandidatesString**
                            Text(iceCandidatesString)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(5)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(5)
                        }
                    }
                }
                .frame(height: 150) // 限制高度，使其可滚动
            }
            .padding(.horizontal)

            Spacer() // 将所有内容推到顶部
        }
        // **移除 delegate 设置**
        /*
        .onAppear {
            huanCapture.huanDelegate = self
            logger.info("ContentView appeared, delegate set.")
        }
        */
        // **使用 .onReceive 监听来自 HuanCapture 的 Combine publisher**
        .onReceive(huanCapture.$connectionState) { newState in
             updateStatus(for: newState)
        }
        .onReceive(huanCapture.$localSDP) { sdp in
             handleLocalSDP(sdp)
        }
        .onReceive(huanCapture.iceCandidateSubject) { candidate in
             handleICECandidate(candidate)
        }
        .onReceive(huanCapture.$captureError) { error in
             handleError(error)
        }
        // **新增：监听 isMirrored 变化并调用方法**
        .onChange(of: isMirrored) { _, newValue in
             logger.info("Mirror toggle changed to \(newValue), calling setPreviewMirrored")
             huanCapture.setPreviewMirrored(newValue)
        }
        // **新增：视图出现时根据摄像头设置初始镜像状态**
        .onAppear {
             // 检查初始摄像头位置并设置镜像
             isMirrored = (huanCapture.currentCameraPosition == .front)
             // 同时调用一次 setPreviewMirrored 确保初始状态一致
             huanCapture.setPreviewMirrored(isMirrored)
             logger.info("ContentView appeared, initial mirror state set to \(isMirrored) based on camera \(huanCapture.currentCameraPosition.rawValue)")
        }
        .onDisappear {
             // 视图消失时尝试停止推流
             if isStreaming {
                  huanCapture.stopStreaming()
                  logger.info("ContentView disappeared, stopped streaming.")
             }
        }
    }

    // **移除 getVideoTrack() 辅助函数**
    /*
     private func getVideoTrack() -> RTCVideoTrack? {
         return huanCapture.videoTrack
     }
     */

    // 开始/停止推流的逻辑
    private func toggleStreaming() {
        if isStreaming {
            huanCapture.stopStreaming()
             statusText = "已停止"
             localSDPString = ""
             iceCandidatesString = ""
             receivedCandidates = [] // 清空
            logger.info("Streaming stopped by button.")
        } else {
            huanCapture.startStreaming()
            statusText = "正在启动..."
             localSDPString = "正在生成 Offer SDP..."
             iceCandidatesString = ""
             receivedCandidates = [] // 清空
            logger.info("Streaming started by button.")
        }
        isStreaming.toggle()
    }

    // **处理 Combine 事件的辅助方法**
    private func updateStatus(for state: RTCIceConnectionState) {
         logger.info("Received connection state update: \(state.description)")
         switch state {
         case .connected, .completed:
             statusText = "连接成功 (Connected)"
             // isStreaming 保持 true
         case .disconnected:
             statusText = "连接已断开 (Disconnected)"
             isStreaming = false // 更新按钮状态
         case .failed:
             statusText = "连接失败 (Failed)"
             isStreaming = false // 更新按钮状态
         case .closed:
             // 只有在用户明确停止时才显示"已停止"，否则显示断开
             if !isStreaming {
                 statusText = "已停止"
             } else {
                 statusText = "连接已关闭 (Closed)"
                 isStreaming = false // 更新按钮状态
             }
         case .new:
             statusText = "准备就绪"
         case .checking:
             statusText = "正在连接... (Checking)"
         case .count:
             break // Should not happen
         @unknown default:
             statusText = "未知状态"
         }
    }

    private func handleLocalSDP(_ sdp: RTCSessionDescription?) {
        guard let sdp = sdp else {
             // 如果 SDP 变回 nil (例如停止时)，清空显示
             if isStreaming { // 防止停止时重复清空
                 localSDPString = ""
             }
            return
        }
        logger.info("Received local SDP update.")
         self.localSDPString = "类型: \(sdp.type.rawValue)\n\n\(sdp.sdp)"
         self.statusText = "已生成 Offer SDP，请发送给接收端"
    }

    private func handleICECandidate(_ candidate: RTCIceCandidate) {
         logger.info("Received ICE candidate update.")
         let candidateString = "类型: \(candidate.sdpMLineIndex) (\(candidate.sdpMid ?? "nil"))\n\(candidate.sdp)\n\n"
         self.iceCandidatesString += candidateString
         self.receivedCandidates.append(candidate)
         // self.statusText = "已生成 ICE Candidate，请发送给接收端" // 状态更新太频繁
    }

    private func handleError(_ error: Error?) {
         guard let error = error else { return }
         logger.error("Received error update: \(error.localizedDescription)")
         self.statusText = "错误: \(error.localizedDescription)"
         self.isStreaming = false // 出错时停止
         self.localSDPString = ""
         self.iceCandidatesString = ""
         self.receivedCandidates = [] // 清空
         // 可以在这里显示一个 Alert
    }
}

// **移除 Delegate 遵循**
/*
extension ContentView: HuanCaptureDelegate {
    // ... delegate methods removed ...
}
*/


#Preview {
    ContentView()
}
