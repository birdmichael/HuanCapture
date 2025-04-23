import SwiftUI
import WebRTC
import HuanCapture
import OSLog
import Combine

struct CapturePreviewRepresentable: UIViewRepresentable {
    let captureView: UIView

    func makeUIView(context: Context) -> UIView {
        return captureView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
    }
}

struct ContentView: View {
    @StateObject private var huanCapture = HuanCaptureManager()
    
    @State private var isStreaming = false
    @State private var isMirrored = false
    @State private var statusText = "准备就绪"
    @State private var localSDPString = ""
    @State private var iceCandidatesString = ""
    @State private var receivedCandidates: [RTCIceCandidate] = []
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ContentView")

    var body: some View {
        VStack(spacing: 18) {
            Text("HuanCapture").font(.largeTitle).bold()
                .foregroundColor(.blue)
                .padding(.top, 12)
            
            ZStack {
                CapturePreviewRepresentable(captureView: huanCapture.previewView)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3/4, contentMode: .fit)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isStreaming ? Color.blue : Color.gray.opacity(0.3), lineWidth: isStreaming ? 3 : 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    .animation(.easeInOut(duration: 0.3), value: isStreaming)
                
                VStack {
                    Spacer()
                    Text(statusText)
                        .font(.footnote).bold()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal)
            
            HStack(spacing: 30) {
                // 开始/停止按钮 - 仅使用图标
                Button {
                    toggleStreaming()
                } label: {
                    Image(systemName: isStreaming ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(isStreaming ? .red : .green)
                }
                
                // 切换镜头按钮 - 仅使用图标
                Button {
                    huanCapture.switchCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 30))
                        .foregroundColor(.blue)
                }
                
                // 镜像按钮 - 仅使用图标
                Button {
                    isMirrored.toggle()
                    huanCapture.setPreviewMirrored(isMirrored)
                } label: {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 30))
                        .foregroundColor(isMirrored ? .indigo : .gray)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            GroupBox {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !localSDPString.isEmpty {
                            Text("本地 SDP").font(.headline).foregroundColor(.blue)
                            Text(localSDPString)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color.blue.opacity(0.05))
                                .cornerRadius(8)
                        }
                        
                        if !iceCandidatesString.isEmpty {
                            Divider().padding(.vertical, 4)
                            Text("ICE 候选者").font(.headline).foregroundColor(.blue)
                            Text(iceCandidatesString)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color.blue.opacity(0.05))
                                .cornerRadius(8)
                        }
                    }
                    .padding(4)
                }
                .frame(height: 160)
            } label: {
                Label("信令信息", systemImage: "network")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            Spacer()
        }
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
            if let error = error {
                statusText = "错误: \(error.localizedDescription)"
                logger.error("捕获错误: \(error.localizedDescription)")
            }
        }
        .onReceive(huanCapture.$currentCameraPosition) { position in
            logger.debug("摄像头位置变更为: \(position == .front ? "前置" : "后置")")
        }
        .onAppear {
            isMirrored = false
            huanCapture.setPreviewMirrored(isMirrored)
            logger.info("ContentView appeared, initial mirror state set to false")
        }
        .onDisappear {
            if isStreaming {
                huanCapture.stopStreaming()
                logger.info("ContentView disappeared, stopped streaming.")
            }
        }
    }

    private func toggleStreaming() {
        isStreaming.toggle()
        if isStreaming {
            huanCapture.startStreaming()
            logger.info("开始推流")
        } else {
            huanCapture.stopStreaming()
            statusText = "准备就绪"
            logger.info("停止推流")
        }
    }
    
    private func updateStatus(for state: RTCIceConnectionState) {
        switch state {
        case .new, .checking:
            statusText = "正在连接..."
        case .connected, .completed:
            statusText = "已连接"
        case .disconnected:
            statusText = "已断开连接"
        case .failed:
            statusText = "连接失败"
        case .closed:
            statusText = "连接关闭"
        case .count:
            statusText = "Count (未知状态)"
        @unknown default:
            statusText = "未知连接状态"
        }
        
        logger.info("WebRTC连接状态更新为: \(statusText)")
    }
    
    private func handleLocalSDP(_ sdp: RTCSessionDescription?) {
        guard let sdp = sdp else { return }
        
        let sdpType = sdp.type == .offer ? "Offer" : "Answer"
        localSDPString = "类型: \(sdpType)\n\(sdp.sdp)"
        logger.debug("获取到本地SDP: \(sdpType)")
    }
    
    private func handleICECandidate(_ candidate: RTCIceCandidate) {
        receivedCandidates.append(candidate)
        
        if !receivedCandidates.isEmpty {
            var candidatesText = ""
            for (index, candidate) in receivedCandidates.enumerated() {
                candidatesText.append("#\(index+1): \(candidate.sdp)\n")
            }
            iceCandidatesString = candidatesText
        }
        
        logger.debug("新ICE候选: \(candidate.sdp)")
    }
}

#Preview {
    ContentView()
}
