#if canImport(es_cast_client_ios)
import es_cast_client_ios
import Foundation
import OSLog

class EsSignalingServer: SignalingServerProtocol {
    weak var delegate: SignalingServerDelegate?
    weak var manager: HuanCaptureManager?
    private let targetDevice: EsDevice
    private let isLoggingEnabled: Bool
    private let logger: Logger

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()


    private enum EsEventName {
        static let sdp = "OnLinkWebRTC"
        static let ice = "HuanCapture_ICE"
        static let state = "HuanCapture"
        static let camera = "HuanCapture_Camera"
        static let mirrored = "HuanCapture_Mirrored"
        static let backCameraAll = "HuanCapture_BackCameraAll"
        static let backCamera = "HuanCapture_BackCamera"
    }

    private var isStarted = false

    init(device: EsDevice, isLoggingEnabled: Bool, manager: HuanCaptureManager? = nil) {
        self.targetDevice = device
        self.isLoggingEnabled = isLoggingEnabled
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.huancapture", category: "EsSignalingServer")
        self.manager = manager
        if isLoggingEnabled { logger.info("EsSignalingServer initialized for device: \(device.deviceName) (\(device.deviceIp))") }
    }
    
    deinit {
        if isLoggingEnabled { logger.info("EsSignalingServer deinitialized") }
    }

    func start() {
        isStarted = true
        if isLoggingEnabled { logger.info("EsSignalingServer started (marked as active). Assumes EsMessenger connection is handled externally.") }
        let action = EsAction.makeCustom(name: "HuanCapture")
        EsMessenger.shared.addDelegate(self)
        EsMessenger.shared.sendDeviceCommand(device: targetDevice, action: action)
    }
    

    func stop() {
        isStarted = false
        EsMessenger.shared.removeDelegate(self)
        if isLoggingEnabled { logger.info("EsSignalingServer stopped (marked as inactive).") }
    }

    func sendOffer(sdp: String) {
        let processedSdp = sdp.replacingOccurrences(of: "\r\n", with: "#")

        guard isStarted else {
            if isLoggingEnabled { logger.warning("EsSignalingServer not started, cannot send offer.") }
            return
        }
        

        if isLoggingEnabled { logger.info("Sending Offer SDP via EsMessenger with chunking...") }

        let chunkSize = 512 // 字节
        let sdpData = processedSdp.data(using: .utf8) ?? Data()
        let totalLength = sdpData.count
        let totalChunks = Int(ceil(Double(totalLength) / Double(chunkSize)))
        let messageId = UUID().uuidString

        for i in 0..<totalChunks {
            let start = i * chunkSize
            let end = min(start + chunkSize, totalLength)
            let chunkData = sdpData.subdata(in: start..<end)
            let chunkString = String(data: chunkData, encoding: .utf8) ?? ""

            let payload: [String: Any] = [
                "action": "offer",
                "sdp": chunkString,
                "chunkNumber": i + 1,
                "totalChunks": totalChunks,
                "id": messageId
            ]
            let action = EsAction.makeCustom(name: EsEventName.sdp).args(["url": "home", "params": payload])
            EsMessenger.shared.sendDeviceCommand(device: targetDevice, action: action)
            if isLoggingEnabled { logger.info("Sent SDP chunk \(i + 1)/\(totalChunks) with id: \(messageId)") }
        }
    }

    func sendCandidate(sdp: String, sdpMid: String?, sdpMLineIndex: Int32?) {
        guard isStarted else {
            if isLoggingEnabled { logger.warning("EsSignalingServer not started, cannot send candidate.") }
            return
        }

        if isLoggingEnabled { logger.info("Sending ICE Candidate via EsMessenger...") }

        // 封装 ICE Candidate 数据为 JSON
        var payload: [String: Any?] = [
            "action": "candidate",
            "candidate": sdp,
            "sdpMLineIndex": sdpMLineIndex,
            "sdpMid": sdpMid
        ]

        let action = EsAction.makeCustom(name: EsEventName.sdp).args(["url": "home", "params": payload])
        EsMessenger.shared.sendDeviceCommand(device: targetDevice, action: action)
    }

    func handleAnswerSdp(_ sdp: String) {
        if isLoggingEnabled { logger.info("Received Answer SDP from external handler.") }
        DispatchQueue.main.async {
            self.delegate?.signalingServer(didReceiveAnswer: sdp)
        }
    }

    func handleIceCandidate(sdp: String, sdpMid: String?, sdpMLineIndex: Int32?) {
        if isLoggingEnabled { logger.info("Received ICE Candidate from external handler.") }
        DispatchQueue.main.async {
            self.delegate?.signalingServer(didReceiveCandidate: sdp, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex)
        }
    }
}

extension EsSignalingServer: MessengerCallback {
    func onFindDevice(_ device: EsDevice) {
        
    }
    
    func onReceiveEvent(_ event: EsEvent) {
        self.manager?.handleEsEvent(event)
    }
}

#endif
