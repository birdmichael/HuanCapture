#if canImport(es_cast_client_ios)
import Foundation
import es_cast_client_ios
import OSLog

/// 使用 EsMessenger 实现的信令服务器。
class EsSignalingServer: SignalingServerProtocol {
    weak var delegate: SignalingServerDelegate?
    private let targetDevice: EsDevice
    private let isLoggingEnabled: Bool
    private let logger: Logger

    // JSON 编码器和解码器可以复用
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // 自定义事件名称常量
    private enum EsEventName {
        static let sdp = "HuanCapture_SDP"
        static let ice = "HuanCapture_ICE"
        static let state = "HuanCapture"
        static let camera = "HuanCapture_Camera"
        static let mirrored = "HuanCapture_Mirrored"
        static let backCameraAll = "HuanCapture_BackCameraAll"
        static let backCamera = "HuanCapture_BackCamera"
    }

    // 内部状态，当前未使用，但可以添加以跟踪发送状态等
    private var isStarted = false

    init(device: EsDevice, isLoggingEnabled: Bool) {
        self.targetDevice = device
        self.isLoggingEnabled = isLoggingEnabled
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.huancapture", category: "EsSignalingServer")
        if isLoggingEnabled { logger.info("EsSignalingServer initialized for device: \(device.deviceName) (\(device.deviceIp))") }
    }

    func start() {
        // 对于 EsMessenger，"启动" 概念上是已经连接的状态，
        // 因此这里主要是标记内部状态。
        isStarted = true
        if isLoggingEnabled { logger.info("EsSignalingServer started (marked as active). Assumes EsMessenger connection is handled externally.") }
    }

    func stop() {
        // 同样，"停止" 只是标记内部状态。
        isStarted = false
        if isLoggingEnabled { logger.info("EsSignalingServer stopped (marked as inactive).") }
    }

    func sendOffer(sdp: String) {
        guard isStarted else {
            if isLoggingEnabled { logger.warning("EsSignalingServer not started, cannot send offer.") }
            return
        }

        if isLoggingEnabled { logger.info("Sending Offer SDP via EsMessenger...") }
        
        // 封装 SDP 数据为 JSON
        let payload = ["type": "offer", "sdp": sdp]
        guard let jsonData = try? encoder.encode(payload) else {
            if isLoggingEnabled { logger.error("Failed to encode Offer SDP to JSON.") }
            return
        }
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
             if isLoggingEnabled { logger.error("Failed to convert Offer SDP JSON data to String.") }
             return
        }
        
        // 创建 EsAction 并发送
        let action = EsAction.makeCustom(name: EsEventName.sdp).args(jsonString)
        EsMessenger.shared.sendDeviceCommand(device: targetDevice, action: action)
    }

    func sendCandidate(sdp: String, sdpMid: String?, sdpMLineIndex: Int32?) {
         guard isStarted else {
            if isLoggingEnabled { logger.warning("EsSignalingServer not started, cannot send candidate.") }
            return
        }
        
        if isLoggingEnabled { logger.info("Sending ICE Candidate via EsMessenger...") }
        
        // 封装 ICE Candidate 数据为 JSON
        var payload: [String: Any?] = [
            "type": "candidate",
            "candidate": sdp,
            "sdpMLineIndex": sdpMLineIndex,
            "sdpMid": sdpMid
        ]
        // Clean nil values if needed, though JSONSerialization handles them
        payload = payload.compactMapValues { $0 }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            if isLoggingEnabled { logger.error("Failed to encode ICE Candidate to JSON.") }
            return
        }
         guard let jsonString = String(data: jsonData, encoding: .utf8) else {
             if isLoggingEnabled { logger.error("Failed to convert ICE Candidate JSON data to String.") }
             return
        }
        
        // 创建 EsAction 并发送
        let action = EsAction.makeCustom(name: EsEventName.ice).args(jsonString)
        EsMessenger.shared.sendDeviceCommand(device: targetDevice, action: action)
    }
    
    // MARK: - Methods to receive data from HuanCapture+Es
    // 这些方法由 HuanCaptureManager 在收到 EsEvent 时调用
    
    /// 由外部调用，用于处理收到的 Answer SDP。
    func handleAnswerSdp(_ sdp: String) {
         if isLoggingEnabled { logger.info("Received Answer SDP from external handler.") }
         // 回调给 HuanCaptureManager
         DispatchQueue.main.async {
             self.delegate?.signalingServer(didReceiveAnswer: sdp)
         }
    }
    
    /// 由外部调用，用于处理收到的 ICE Candidate。
    func handleIceCandidate(sdp: String, sdpMid: String?, sdpMLineIndex: Int32?) {
         if isLoggingEnabled { logger.info("Received ICE Candidate from external handler.") }
         // 回调给 HuanCaptureManager
         DispatchQueue.main.async {
             self.delegate?.signalingServer(didReceiveCandidate: sdp, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex)
         }
    }
}

#endif // canImport(es_cast_client_ios) 