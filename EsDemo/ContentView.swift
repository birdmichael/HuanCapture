import AVFoundation
import Combine
import es_cast_client_ios
import HuanCapture
import OSLog
import SwiftUI
import UIKit
import WebRTC

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    let level: LogLevel

    enum LogLevel { case info, warning, error }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

struct RandomColorAnimatedView: View {
    @State private var currentNumber: Int = 0
    @State private var backgroundColor: Color = .red
    @State private var timer: Timer?
    
    private let colors: [Color] = [.red, .blue, .green, .orange, .purple, .pink, .yellow, .cyan, .mint, .indigo]
    
    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: backgroundColor)
            
            Text("\(currentNumber)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 5, y: 5)
                .scaleEffect(currentNumber % 2 == 0 ? 1.0 : 1.2)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: currentNumber)
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startAnimation() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            withAnimation {
                currentNumber = Int.random(in: 0...999)
                backgroundColor = colors.randomElement() ?? .red
            }
        }
    }
}

struct CapturePreviewRepresentable: UIViewRepresentable {
    let captureView: UIView

    func makeUIView(context: Context) -> UIView {
        captureView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var captureManager: HuanCaptureManager
    @EnvironmentObject var store: Store

//    private var config: HuanCaptureConfig

    @State private var isMirrored = false
    @State private var showControls = false
    @State private var logMessages: [LogEntry] = []
    private let maxLogEntries = 100

    init(device: EsDevice, isScreen: Bool) {
        let config = HuanCaptureConfig(maxBitrateBps: 300_000,
                                       minBitrateBps: 50_000,
                                       maxFramerateFps: 20,
                                       scaleResolutionDownBy: 6,
                                       signalingModeInput: .esMessenger(device))
        if isScreen {
            _captureManager = StateObject(wrappedValue: HuanCaptureManager(frameProvider: InAppScreenFrameProvider(), config: config))
        } else {
            _captureManager = StateObject(wrappedValue: HuanCaptureManager(frameProvider: CameraFrameProvider(), config: config))
        }
        
    }

    var body: some View {
        ZStack {
            if store.isScreen {
                RandomColorAnimatedView()
                    .edgesIgnoringSafeArea(.all)
            } else {
                HuanCapturePreview(captureManager: captureManager)
                    .edgesIgnoringSafeArea(.all)
            }
            

            VStack {
                statusBar
                    .padding(.top, 5)
                    .padding(.horizontal)

                Spacer()

                
                bottomControls
                    .padding(.bottom, 10)
                    .padding(.horizontal)
                    .opacity(store.isScreen ? 0 : 1)
            }
        }
        .statusBar(hidden: true)
        .task {
            log(.info, "视图已加载")
            setupDeviceOrientationHandling()
            captureManager.setPreviewMirrored(isMirrored)
        }
        .onDisappear {
            log(.info, "视图已消失，停止推流")
            captureManager.stopStreaming()
        }
        .sheet(isPresented: $showControls) {
            ControlsSheetView(captureManager: captureManager,
                              isMirrored: $isMirrored,
                              logMessages: $logMessages,
                              webSocketPort: nil)
        }
        .onReceive(captureManager.$connectionState) { newState in
            log(.info, "WebRTC 状态: \(newState.chineseDescription)")
        }
        .onReceive(captureManager.$captureError) { error in
            if let error {
                log(.error, "错误: \(error.localizedDescription)")
            }
        }
        .onReceive(captureManager.$currentCameraPosition) { position in
            log(.info, "摄像头: \(position.localizedName)")
        }
        .onReceive(captureManager.$currentCameraType) { type in
            log(.info, "类型: \(type.localizedName)")
        }
        .onAppear {
            captureManager.startStreaming()
        }
    }

    private var statusBar: some View {
        HStack {
            statusIndicator(color: captureManager.connectionState.color,
                            label: "WebRTC:\(captureManager.connectionState.chineseDescription)")

            Spacer()

            // 退出
            Button {
                store.showCapture = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 25))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.4), in: Circle())
                    .shadow(radius: 3)
            }
        }
        .padding(.vertical, 5)
    }

    private func statusIndicator(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 0.5))
                .shadow(radius: 1)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var bottomControls: some View {
        HStack {
            Spacer()
            controlsButton
        }
        .padding(.vertical, 10)
    }

    private var startStopButton: some View {
        Button {
            let isIdleOrDisconnected = captureManager.connectionState.isIdleOrDisconnected
            if isIdleOrDisconnected {
                log(.info, "请求开始推流")
                captureManager.startStreaming()
            } else {
                log(.info, "请求停止推流")
                captureManager.stopStreaming()
            }
        } label: {
            let isRunning = !captureManager.connectionState.isIdleOrDisconnected

            Image(systemName: isRunning ? "stop.circle.fill" : "play.circle.fill")
                .font(.system(size: 50))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, isRunning ? .red : .green)
                .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
        }
        .padding(.leading)
    }

    private var controlsButton: some View {
        Button {
            showControls = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 30))
                .foregroundColor(.white)
                .padding(10)
                .background(Color.black.opacity(0.4), in: Circle())
                .shadow(radius: 3)
        }
        .padding(.trailing)
    }

    private func log(_ level: LogEntry.LogLevel, _ message: String) {
        let newEntry = LogEntry(message: message, level: level)
        logMessages.append(newEntry)
        if logMessages.count > maxLogEntries {
            logMessages.removeFirst(logMessages.count - maxLogEntries)
        }
        print("[\(level)] \(message)")
    }

    private func setupDeviceOrientationHandling() {
        captureManager.deviceOrientation = UIDevice.current.orientation

        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in
            let newOrientation = UIDevice.current.orientation
            if newOrientation.isPortrait || newOrientation.isLandscape {
                captureManager.deviceOrientation = newOrientation
            }
        }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }
}

struct ControlsSheetView: View {
    @ObservedObject var captureManager: HuanCaptureManager
    @Binding var isMirrored: Bool
    @Binding var logMessages: [LogEntry]
    let webSocketPort: UInt16?

    @Environment(\.dismiss) var dismissSheet
    @State private var selectedCameraType: CameraType

    init(captureManager: HuanCaptureManager, isMirrored: Binding<Bool>, logMessages: Binding<[LogEntry]>, webSocketPort: UInt16?) {
        self.captureManager = captureManager
        self._isMirrored = isMirrored
        self._logMessages = logMessages
        self.webSocketPort = webSocketPort
        _selectedCameraType = State(initialValue: captureManager.currentCameraType)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                List {
                    if let port = webSocketPort {
                        Section("WebSocket 服务器") {
                            HStack {
                                Image(systemName: "network")
                                Text("监听端口: \(port.description)")
                            }.foregroundColor(.secondary)
                        }
                    }

                    Section("摄像头控制") {
                        HStack {
                            Label("切换摄像头", systemImage: "arrow.triangle.2.circlepath.camera")
                            Spacer()
                            Button("切换") { captureManager.switchCamera() }.buttonStyle(.borderless)
                        }

                        let showTypeSwitch = captureManager.availableBackCameraTypes.count > 1 && captureManager.currentCameraPosition == .back
                        if showTypeSwitch {
                            VStack(alignment: .leading) {
                                Text("相机类型")
                                cameraTypePicker
                            }.padding(.vertical, 4)
                        } else {
                            HStack {
                                Text("相机类型")
                                Spacer()
                                Text("\(captureManager.currentCameraType.localizedName)")
                                    .foregroundColor(.gray)
                            }
                        }
                    }

                    Section("预览设置") {
                        Toggle("镜像预览", isOn: $isMirrored)
                            .onChange(of: isMirrored) { _, newValue in
                                captureManager.setPreviewMirrored(newValue)
                            }
                    }
                }
                .listStyle(.insetGrouped)

                logView
                    .frame(height: 180)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedCorner(radius: 10, corners: [.bottomLeft, .bottomRight]))
            }
            .navigationTitle("控制与日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismissSheet() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var cameraTypePicker: some View {
        Picker("相机类型", selection: $selectedCameraType) {
            ForEach(captureManager.availableBackCameraTypes, id: \.self) { type in
                Text(type.localizedName).tag(type)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .onChange(of: selectedCameraType) { _, newValue in
            captureManager.switchToBackCameraType(newValue)
        }
        .onReceive(captureManager.$currentCameraType) { managerType in
            if selectedCameraType != managerType {
                selectedCameraType = managerType
            }
        }
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("实时日志")
                    .font(.headline)
                    .padding(.leading)
                Spacer()
            }
            .padding(.top, 10)
            .padding(.bottom, 5)

            Divider().padding(.horizontal)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(logMessages) { entry in
                            logEntryView(entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .onChange(of: logMessages.count) {
                    if let lastId = logMessages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private func logEntryView(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.formattedTimestamp)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 65, alignment: .leading)
            Text(entry.message)
                .font(.system(size: 12))
                .foregroundColor(logColor(for: entry.level))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
        }
    }

    private func logColor(for level: LogEntry.LogLevel) -> Color {
        switch level {
        case .info: .primary
        case .warning: .orange
        case .error: .red
        }
    }
}

struct HuanCapturePreview: UIViewRepresentable {
    let captureManager: HuanCaptureManager

    func makeUIView(context: Context) -> UIView {
        captureManager.previewView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension AVCaptureDevice.Position {
    var localizedName: String {
        switch self {
        case .back: return "后置摄像头"
        case .front: return "前置摄像头"
        case .unspecified: return "未指定"
        @unknown default: return "未知"
        }
    }

    var shortName: String {
        switch self {
        case .back: return "Back"
        case .front: return "Front"
        case .unspecified: return "Unspec."
        @unknown default: return "Unk."
        }
    }
}

extension CameraType {
    var localizedName: String {
        switch self {
        case .wideAngle: "广角"
        case .telephoto: "长焦"
        case .ultraWide: "超广角"
        }
    }

    var shortName: String {
        switch self {
        case .wideAngle: "Wide"
        case .telephoto: "Tele"
        case .ultraWide: "Ultra"
        }
    }
}

extension PublicWebSocketStatus {
    var chineseDescription: String {
        switch self {
        case .idle: "空闲"
        case .starting: "启动中..."
        case .listening(let port): "监听端口: \(port)"
        case .stopped: "已停止"
        case .failed(let reason): "失败: \(reason)"
        case .clientConnected: "客户端已连接"
        case .clientDisconnected: "客户端断开"
        case .notApplicable:
            "未处理"
        }
    }

    var color: Color {
        switch self {
        case .idle,
             .stopped,
             .clientDisconnected: return .gray
        case .starting: return .orange
        case .listening,
             .clientConnected: return .green
        case .failed: return .red
        @unknown default:
            return .gray
        }
    }
}

extension RTCIceConnectionState {
    var chineseDescription: String {
        switch self {
        case .new: return "新建"
        case .checking: return "检查中"
        case .connected: return "已连接"
        case .completed: return "已完成"
        case .disconnected: return "已断开"
        case .failed: return "连接失败"
        case .closed: return "已关闭"
        @unknown default: return "未知"
        }
    }

    var color: Color {
        switch self {
        case .new,
             .checking: return .orange
        case .connected,
             .completed: return .green
        case .disconnected: return .yellow
        case .failed,
             .closed: return .red
        @unknown default:
            return .gray
        }
    }
}

extension RTCIceConnectionState {
    var isIdleOrDisconnected: Bool {
        switch self {
        case .new,
             .disconnected,
             .failed,
             .closed: true
        default: false
        }
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
