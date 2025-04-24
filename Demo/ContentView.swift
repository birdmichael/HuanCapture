import SwiftUI
import WebRTC
import HuanCapture
import OSLog
import Combine
import UIKit

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
    @State private var currentCameraTypeText = "广角"
    @State private var localSDPString = ""
    @State private var iceCandidatesString = ""
    @State private var receivedCandidates: [RTCIceCandidate] = []
    @State private var deviceOrientation: UIDeviceOrientation = .portrait
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ContentView")

    var body: some View {
        Group {
            if deviceOrientation == .portrait || deviceOrientation == .portraitUpsideDown {
                verticalLayout
            } else if deviceOrientation == .landscapeLeft || deviceOrientation == .landscapeRight {
                horizontalLayout
            } else {
                verticalLayout
            }
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
        .onReceive(huanCapture.$currentCameraType) { type in
            switch type {
            case .wideAngle:
                currentCameraTypeText = "广角"
            case .telephoto:
                currentCameraTypeText = "长焦"
            case .ultraWide:
                currentCameraTypeText = "超广角"
            }
            logger.debug("摄像头类型变更为: \(currentCameraTypeText)")
        }
        .onAppear {
            isMirrored = false
            huanCapture.setPreviewMirrored(isMirrored)
            setupOrientationNotification()
            logger.info("ContentView appeared, initial mirror state set to false")
        }
        .onDisappear {
            if isStreaming {
                huanCapture.stopStreaming()
                logger.info("ContentView disappeared, stopped streaming.")
            }
            NotificationCenter.default.removeObserver(NotificationCenter.default.self, name: UIDevice.orientationDidChangeNotification, object: nil)
        }
    }
    
    private var verticalLayout: some View {
        VStack(spacing: 18) {
            Text("HuanCapture").font(.largeTitle).bold()
                .foregroundColor(.blue)
                .padding(.top, 12)
            
            previewView
                .padding(.horizontal)
            
            controlButtons
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            signalingInfoView
                .padding(.horizontal)
            
            Spacer()
        }
    }
    
    private var horizontalLayout: some View {
        GeometryReader { geometry in
            horizontalLayoutContent(geometry: geometry)
        }
    }
    
    private func horizontalLayoutContent(geometry: GeometryProxy) -> some View {
        HStack(spacing: 10) {
            VStack {
                Text("HuanCapture").font(.title2).bold()
                    .foregroundColor(.blue)
                    .padding(.top, 8)
                
                previewView
                    .padding(.horizontal, 8)
                
                if huanCapture.currentCameraPosition == .back {
                    HStack {
                        Text("当前: \(currentCameraTypeText)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                    }
                    .padding(.top, 4)
                }
                
                Spacer()
            }
            .frame(width: geometry.size.width * 0.55)
            
            VStack(spacing: 12) {
                ScrollView {
                    VStack(spacing: 12) {
                        controlButtons
                            .padding(.top, 8)
                        
                        Divider()
                        
                        signalingInfoView
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(width: geometry.size.width * 0.45)
            .padding(.vertical, 10)
        }
    }
    
    private var previewView: some View {
        ZStack {
            CapturePreviewRepresentable(captureView: huanCapture.previewView)
                .frame(maxWidth: .infinity)
                .aspectRatio(deviceOrientation.isPortrait ? 3/4 : 4/3, contentMode: .fit)
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
    }
    
    private var controlButtons: some View {
        VStack(spacing: 20) {
            HStack(spacing: 30) {
                Button {
                    toggleStreaming()
                } label: {
                    Image(systemName: isStreaming ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(isStreaming ? .red : .green)
                }
                
                Button {
                    huanCapture.switchCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 30))
                        .foregroundColor(.blue)
                }
                
                Button {
                    isMirrored.toggle()
                    huanCapture.setPreviewMirrored(isMirrored)
                } label: {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 30))
                        .foregroundColor(isMirrored ? .indigo : .gray)
                }
            }
            
            if huanCapture.currentCameraPosition == .back {
                VStack(spacing: 8) {
                    Text("相机类型")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 5) {
                        ForEach(huanCapture.availableBackCameraTypes, id: \.self) { cameraType in
                            Button {
                                huanCapture.switchToBackCameraType(cameraType)
                            } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: cameraType == .wideAngle ? "camera.aperture" : 
                                                     (cameraType == .telephoto ? "camera.circle" : "camera.metering.center.weighted"))
                                        .font(.system(size: 16))
                                    
                                    Text(cameraType == .wideAngle ? "广角" : 
                                         (cameraType == .telephoto ? "长焦" : "超广角"))
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .frame(width: 40, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(huanCapture.currentCameraType == cameraType ? 
                                              Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(huanCapture.currentCameraType == cameraType ? 
                                                Color.blue : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        
                        Button {
                            huanCapture.switchBackCameraType()
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 16))
                                
                                Text("切换")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue.opacity(0.15))
                            )
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .padding(.vertical, 8)
                .transition(.opacity)
                .animation(.easeInOut, value: huanCapture.currentCameraPosition)
                .animation(.easeInOut, value: huanCapture.currentCameraType)
            }
        }
    }
    
    private var signalingInfoView: some View {
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
            .frame(height: deviceOrientation.isPortrait ? 160 : 150)
        } label: {
            Label("信令信息", systemImage: "network")
                .font(.headline)
                .foregroundColor(.secondary)
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
    
    private func setupOrientationNotification() {
        deviceOrientation = UIDevice.current.orientation.isValidInterfaceOrientation ? UIDevice.current.orientation : .portrait
        huanCapture.deviceOrientation = deviceOrientation
        
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) {  _ in
            let newOrientation = UIDevice.current.orientation
            
            if newOrientation.isValidInterfaceOrientation {
                self.deviceOrientation = newOrientation
                self.huanCapture.deviceOrientation = newOrientation
                self.logger.info("设备方向已更新为: \(newOrientation.rawValue)")
            }
        }
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
