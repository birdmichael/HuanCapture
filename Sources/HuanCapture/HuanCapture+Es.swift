import Foundation
import es_cast_client_ios
import OSLog
import AVFoundation
import Combine

// MARK: - EsAction Constants and Extensions

extension EsAction {
    enum EsEventName {
        static let sdp = "answer"
        static let ice = "HuanCapture_ICE"
        static let state = "HuanCapture"
        static let camera = "switchCamera"
        static let mirrored = "switchMirror"
        static let backCameraAll = "HuanCapture_BackCameraAll"
        static let backCamera = "switchRegular"
    }
    
    static func makeHuanCaptureBackCameraAll(cameras: [CameraType]) -> EsAction {
        let cameraData = cameras.map { ["type": $0.rawValue, "name": $0.localizedName] }
        let payload = ["cameras": cameraData]
        let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [])
        let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return EsAction.makeCustom(name: EsEventName.backCameraAll).args(jsonString)
    }

    static func makeHuanCaptureState(enabled: Bool) -> EsAction {
        return EsAction.makeCustom(name: EsEventName.state).args(enabled ? "1" : "0")
    }
}

// MARK: - HuanCaptureManager Extension for EsMessenger

extension HuanCaptureManager {
    
    private var esLogger: PrintLog {
        PrintLog()
    }

    internal func setupEsSignaling(device: EsDevice) {
        let esSignaler = EsSignalingServer(device: device, isLoggingEnabled: config.isLoggingEnabled, manager: self)
        esSignaler.delegate = self
        self.signalingServer = esSignaler
        if config.isLoggingEnabled { esLogger.info("EsSignalingServer setup complete for device: \(device.deviceName)") }
    }

    public func handleEsEvent(_ event: EsEvent) {
        if config.isLoggingEnabled { esLogger.info("Handling EsEvent: \(event.name)") }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch event.name {
            case EsAction.EsEventName.sdp:
                self.handleEsSdpEvent(event.args as? String)
            case EsAction.EsEventName.ice:
                self.handleEsIceEvent(event.args as? String)
            case EsAction.EsEventName.state:
                self.handleEsStateEvent(event.args as? String)
            case EsAction.EsEventName.camera:
                self.switchCamera()
            case EsAction.EsEventName.mirrored:
                self.setPreviewMirrored(!self.isPreviewMirrored)
            case EsAction.EsEventName.backCamera:
                self.handleEsBackCameraSwitchEvent(event.args as? String)
            case EsAction.EsEventName.backCameraAll:
                if self.config.isLoggingEnabled { self.esLogger.info("Received BackCameraAll event (usually sent from phone), ignoring.") }
            default:
                if self.config.isLoggingEnabled { self.esLogger.warning("Received unhandled EsEvent name: \(event.name)") }
            }
        }
    }

    public func esSetAnswer(sdp: String) {
         if config.isLoggingEnabled { esLogger.info("Setting Answer SDP received via ES channel.") }
         guard let esSignaler = self.signalingServer as? EsSignalingServer else {
             if config.isLoggingEnabled { esLogger.warning("esSetAnswer called, but signaling mode is not EsMessenger.") }
             return
         }
         esSignaler.handleAnswerSdp(sdp)
    }
    
    // MARK: - Private ES Event Handlers

    private func handleEsSdpEvent(_ args: String?) {
        guard let argsString = args, 
              let argsData = argsString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any],
              let type = json["action"] as? String,
              let sdp = json["sdp"] as? String else {
            if config.isLoggingEnabled { esLogger.warning("Received SDP event with invalid or missing arguments: \(String(describing: args))") }
            return
        }
        
            if type == "answer" {
                if config.isLoggingEnabled { esLogger.info("Handling received Answer SDP via ES.") }
                guard let esSignaler = self.signalingServer as? EsSignalingServer else { return }
                esSignaler.handleAnswerSdp(sdp)
            } else if type == "offer" {
                if config.isLoggingEnabled { esLogger.warning("Received unexpected Offer SDP via ES from TV.") }
        } else {
            if config.isLoggingEnabled { esLogger.warning("Received SDP event with unknown type: \(type)") }
        }
    }

    private func handleEsIceEvent(_ args: String?) {
        guard let jsonString = args, let data = jsonString.data(using: .utf8) else {
            if config.isLoggingEnabled { esLogger.warning("Received ICE event with invalid or missing arguments.") }
            return
        }
        do {
             if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                let type = json["type"] as? String, type == "candidate",
                let candidateSdp = json["candidate"] as? String {
               
                let sdpMid = json["sdpMid"] as? String
                let sdpMLineIndex = json["sdpMLineIndex"] as? Int32 ?? -1
                
                 if config.isLoggingEnabled { esLogger.info("Handling received ICE Candidate via ES.") }
                 guard let esSignaler = self.signalingServer as? EsSignalingServer else { return }
                 esSignaler.handleIceCandidate(sdp: candidateSdp, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex)
             } else {
                  if config.isLoggingEnabled { esLogger.warning("Failed to parse ICE Candidate JSON or missing fields from: \(jsonString)") }
             }
        } catch {
             if config.isLoggingEnabled { esLogger.error("Error decoding ICE Candidate JSON: \(error.localizedDescription) from: \(jsonString)") }
        }
    }
    
    private func handleEsStateEvent(_ args: String?) {
        guard let stateValue = args else {
             if config.isLoggingEnabled { esLogger.warning("Received State event with missing arguments.") }
            return
        }
        if stateValue == "1" {
            if config.isLoggingEnabled { esLogger.info("Received ES event to start streaming.") }
            startStreaming()
        } else if stateValue == "0" {
            if config.isLoggingEnabled { esLogger.info("Received ES event to stop streaming.") }
            stopStreaming()
        } else {
             if config.isLoggingEnabled { esLogger.warning("Received State event with invalid value: \(stateValue).") }
        }
    }
    
    private func handleEsBackCameraSwitchEvent(_ args: String?) {
         guard let requestedTypeRawValue = args else {
             if config.isLoggingEnabled { esLogger.warning("Received BackCamera event with missing arguments.") }
            return
        }
        
        if let requestedType = self.availableBackCameraTypes.first(where: { $0.rawValue == requestedTypeRawValue }) {
             if config.isLoggingEnabled { esLogger.info("Received ES event to switch back camera type to: \(requestedType.localizedName)") }
             self.switchToBackCameraType(requestedType)
        } else {
            if config.isLoggingEnabled { esLogger.info("Requested back camera type '\(requestedTypeRawValue)' not directly available or found. Attempting general switch.") }
            self.switchBackCameraType()
        }
    }

    // MARK: - Sending ES Events

    internal func sendAvailableBackCamerasToEsDevice() {
        guard case .esMessenger(let device) = config.signalingMode else {
            return
        }
        guard !self.availableBackCameraTypes.isEmpty else {
            if config.isLoggingEnabled { esLogger.warning("No available back camera types detected to send for EsMessenger.") }
            return
        }
        
        if config.isLoggingEnabled { esLogger.info("Sending available back camera types to ES device: \(device.deviceName)") }
        let action = EsAction.makeHuanCaptureBackCameraAll(cameras: self.availableBackCameraTypes)
        EsMessenger.shared.sendDeviceCommand(device: device, action: action)
    }
}

extension EsEvent {
    var name: String {
        return data["action"] as? String ?? ""
    }
    
    var args: Any {
        return data["args"]
    }
}

