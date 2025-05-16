//
//  HuanCapture.swift
//  HuanCapture
//
//  Created by BM on 2025/4/23.
//
import WebRTC
import AVFoundation
import OSLog
import Combine
import SwiftUI


struct PrintLog {
    func info(_ message: String) {
        print(message)
    }
    
    func warning(_ message: String) {
        print(message)
    }
    
    func error(_ message: String) {
        print(message)
    }
    func debug(_ message: String) {
        print(message)
    }
}

public enum CameraType: RawRepresentable { // Ensure RawRepresentable conformance here or in the extension
    public typealias RawValue = String

    case wideAngle
    case telephoto
    case ultraWide

    public init?(rawValue: RawValue) {
        switch rawValue {
        case "wideAngle": self = .wideAngle
        case "telephoto": self = .telephoto
        case "ultraWide": self = .ultraWide
        default: return nil
        }
    }

    public var rawValue: RawValue {
        switch self {
        case .wideAngle: return "wideAngle"
        case .telephoto: return "telephoto"
        case .ultraWide: return "ultraWide"
        }
    }

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .wideAngle:
            return .builtInWideAngleCamera
        case .telephoto:
            return .builtInTelephotoCamera
        case .ultraWide:
            return .builtInUltraWideCamera
        }
    }

    var localizedName: String {
        switch self {
        case .wideAngle:
            return "广角"
        case .telephoto:
            return "长焦"
        case .ultraWide:
            return "超广角"
        }
    }
}

// MARK: - Publicly Visible State Enums

public enum PublicWebSocketStatus {
    case idle
    case starting
    case listening(port: UInt16)
    case stopped
    case failed(String)
    case clientConnected
    case clientDisconnected
    case notApplicable
}

public class HuanCaptureManager: RTCVideoCapturer, RTCPeerConnectionDelegate, SignalingServerDelegate, WebSocketSignalingServerStateDelegate, VideoFrameProviderDelegate, ObservableObject {

    @Published public private(set) var connectionState: RTCIceConnectionState = .new
    @Published public private(set) var localSDP: RTCSessionDescription?
    @Published public private(set) var captureError: Error?
    @Published public private(set) var currentCameraPosition: AVCaptureDevice.Position = .back
    @Published public private(set) var currentCameraType: CameraType = .wideAngle
    @Published public private(set) var availableBackCameraTypes: [CameraType] = []
    @Published public var deviceOrientation: UIDeviceOrientation = .portrait {
        didSet {
            cameraControlProvider?.deviceOrientation = deviceOrientation
        }
    }
    @Published public private(set) var webSocketStatus: PublicWebSocketStatus = .idle
    @Published public private(set) var isPreviewMirrored: Bool = false
    public let iceCandidateSubject = PassthroughSubject<RTCIceCandidate, Never>()
    public let previewView: UIView
    public private(set) var config: HuanCaptureConfig

    private let internalPreviewView = RTCMTLVideoView(frame: .zero)
    private var peerConnectionFactory: RTCPeerConnectionFactory!
    private var peerConnection: RTCPeerConnection?
    private var videoSource: RTCVideoSource!
    private var videoTrack: RTCVideoTrack!
    private let rtcAudioSession = RTCAudioSession.sharedInstance()
    internal let logger: PrintLog
    private var isStoppingManually = false
    internal var signalingServer: SignalingServerProtocol?
    
    public private(set) var frameProvider: VideoFrameProvider
    private var cameraControlProvider: CameraControlProvider? {
        frameProvider as? CameraControlProvider
    }
    private var externalFrameConsumer: ExternalFrameProvider? {
        frameProvider as? ExternalFrameProvider
    }

    public var isLoggingEnabled: Bool { config.isLoggingEnabled }

    public init(frameProvider: VideoFrameProvider, config: HuanCaptureConfig = HuanCaptureConfig.default) {
        self.frameProvider = frameProvider
        self.config = config
        self.logger = PrintLog()
        self.previewView = internalPreviewView
        super.init()
        if config.isLoggingEnabled { logger.info("HuanCapture initializing. Provider: \(type(of: frameProvider)), Logging: \(config.isLoggingEnabled)") }

        internalPreviewView.videoContentMode = .scaleAspectFill

        self.frameProvider.delegate = self

        if let camProvider = self.cameraControlProvider {
            self.currentCameraPosition = camProvider.currentCameraPosition
            self.currentCameraType = camProvider.currentCameraType
            self.availableBackCameraTypes = camProvider.availableBackCameraTypes
            self.isPreviewMirrored = camProvider.isPreviewMirrored
            camProvider.deviceOrientation = self.deviceOrientation
        }

        switch config.signalingMode {
        case .webSocket:
            let wsSignaler = WebSocketSignalingServer(port: config.webSocketPort, isLoggingEnabled: config.isLoggingEnabled)
            wsSignaler.delegate = self; wsSignaler.internalStateDelegate = self; self.signalingServer = wsSignaler; self.webSocketStatus = .idle
            if config.isLoggingEnabled { logger.info("Using WebSocket signaling.") }
        
        case .esMessenger(let device):
            self.webSocketStatus = .notApplicable
            if config.isLoggingEnabled { logger.info("Using EsMessenger signaling.") }
            
            setupEsSignaling(device: device)
            
        case .custom:
            self.signalingServer = nil; self.webSocketStatus = .notApplicable
            if config.isLoggingEnabled { logger.info("Using custom signaling.") }
        }

        setupWebRTC()

        if config.isLoggingEnabled { logger.info("HuanCapture initialized.") }
    }

    deinit {
        if let track = videoTrack {
            track.remove(internalPreviewView)
        }
        stopStreaming()
        if config.isLoggingEnabled { logger.info("HuanCapture deinitialized.") }
    }

    // MARK: - Setup

    private func setupWebRTC() {
        if config.isLoggingEnabled { logger.debug("Setting up WebRTC...") }
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        peerConnectionFactory = RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)

        configureAudioSession()

        videoSource = peerConnectionFactory.videoSource()
        videoTrack = peerConnectionFactory.videoTrack(with: videoSource, trackId: "video0")

        videoTrack.add(internalPreviewView)
        if config.isLoggingEnabled { logger.debug("Added video track to internal preview view.") }
        if config.isLoggingEnabled { logger.debug("WebRTC setup complete.") }
    }

    private func configureAudioSession() {
        if config.isLoggingEnabled { logger.debug("Configuring RTCAudioSession...") }
        rtcAudioSession.lockForConfiguration()
        defer {
            rtcAudioSession.unlockForConfiguration()
            if config.isLoggingEnabled { logger.debug("RTCAudioSession configuration unlocked.") }
        }
        do {
            try rtcAudioSession.setCategory(AVAudioSession.Category.playAndRecord)
            try rtcAudioSession.setMode(AVAudioSession.Mode.videoChat)
            try rtcAudioSession.overrideOutputAudioPort(.speaker)
            if config.isLoggingEnabled { logger.info("RTCAudioSession configured successfully (Audio Disabled).") }
        } catch {
            if config.isLoggingEnabled { logger.error("Error configuring RTCAudioSession: \(error.localizedDescription)") }
        }
    }

    // MARK: - Public Control Methods

    public func startStreaming() {
        if config.isLoggingEnabled { logger.info("Attempting to start streaming...") }
        self.isStoppingManually = false
        guard peerConnection == nil else {
            if config.isLoggingEnabled { logger.warning("Streaming already started or starting.") }
            return
        }
        
        signalingServer?.start()

        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        peerConnection = peerConnectionFactory.peerConnection(with: configuration, constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: self)

        guard let pc = peerConnection else {
            if config.isLoggingEnabled { logger.error("Failed to create RTCPeerConnection.") }
            DispatchQueue.main.async { [weak self] in
                 guard let self = self else { return }
                 self.captureError = NSError(domain: "HuanCaptureError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create PeerConnection"])
                 self.signalingServer?.stop()
            }
            return
        }
        if config.isLoggingEnabled { logger.info("RTCPeerConnection created.") }

        let streamIds = ["stream0"]
        let initObject = RTCRtpTransceiverInit()
        initObject.direction = .sendOnly
        initObject.streamIds = streamIds
        if pc.addTransceiver(with: videoTrack, init: initObject) != nil {
             if config.isLoggingEnabled { logger.debug("Video transceiver added with direction sendOnly.") }
        } else {
             if config.isLoggingEnabled { logger.error("Failed to add video transceiver.") }
             DispatchQueue.main.async { [weak self] in
                  guard let self = self else { return }
                  self.captureError = NSError(domain: "HuanCaptureError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to add video transceiver"])
             }
             stopStreaming()
             return
        }

        let constraints = RTCMediaConstraints(mandatoryConstraints: [kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse,
                                                                   kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueFalse],
                                            optionalConstraints: nil)

        pc.offer(for: constraints) { [weak self] (sdp, error) in
             DispatchQueue.main.async { // Ensure UI/state updates are on main thread
                 guard let self = self else { return }
                 if let error = error {
                     if self.config.isLoggingEnabled { self.logger.error("Failed to create offer SDP: \(error.localizedDescription)") }
                     self.captureError = error
                     self.stopStreaming()
                     return
                 }

                 guard let sdp = sdp else {
                     if self.config.isLoggingEnabled { self.logger.error("SDP offer is nil, but no error reported.") }
                     self.captureError = NSError(domain: "HuanCaptureError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create offer, SDP was nil"])
                     self.stopStreaming()
                     return
                 }

                 if self.config.isLoggingEnabled { self.logger.info("Offer SDP created successfully.") }
                 pc.setLocalDescription(sdp) { [weak self] (error) in
                      DispatchQueue.main.async { // Ensure UI/state updates are on main thread
                          guard let self = self else { return }
                          if let error = error {
                             if self.config.isLoggingEnabled { self.logger.error("Failed to set local SDP: \(error.localizedDescription)") }
                             self.captureError = error
                             self.stopStreaming()
                             return
                          }
                          if self.config.isLoggingEnabled { self.logger.info("Local SDP set successfully.") }
                          self.localSDP = sdp

                          self.configureSenderParameters()

                          self.signalingServer?.sendOffer(sdp: sdp.sdp)
                          
                          self.frameProvider.startProviding()
                      }
                 }
             }
        }
    }

    public func stopStreaming() {
        guard peerConnection != nil || frameProvider.isRunning else {
            if config.isLoggingEnabled { logger.info("Streaming already stopped or not running.") }
            return
        }

        if config.isLoggingEnabled { logger.info("Attempting to stop streaming...") }
        self.isStoppingManually = true

        signalingServer?.stop()

        frameProvider.stopProviding()

        if let pc = peerConnection {
            pc.close()
            if config.isLoggingEnabled { logger.info("RTCPeerConnection close() called.") }
        }
        peerConnection = nil

        DispatchQueue.main.async {
             if self.connectionState != .closed {
                 self.connectionState = .closed
             }
             self.localSDP = nil
             self.captureError = nil
        }
        if config.isLoggingEnabled { logger.info("Streaming stop requested.") }
    }

    public func setRemoteDescription(_ remoteSDP: RTCSessionDescription) {
        guard let pc = peerConnection else {
            if config.isLoggingEnabled { logger.error("PeerConnection not available when trying to set remote description.") }
            return
        }
         guard pc.localDescription != nil else {
            if config.isLoggingEnabled { logger.error("Local description must be set before setting remote description.") }
            DispatchQueue.main.async { [weak self] in
                 guard let self = self else { return }
                 self.captureError = NSError(domain: "HuanCaptureError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Local description not set"])
            }
            return
         }

        if config.isLoggingEnabled { logger.info("Setting remote SDP (type: \(remoteSDP.type.rawValue))...") }
        pc.setRemoteDescription(remoteSDP) { [weak self] (error) in
             DispatchQueue.main.async {
                 guard let self = self else { return }
                 if let error = error {
                     if self.config.isLoggingEnabled { self.logger.error("Failed to set remote SDP: \(error.localizedDescription)") }
                     self.captureError = error
                     return
                 }
                 if self.config.isLoggingEnabled { self.logger.info("Remote SDP set successfully.") }
             }
        }
    }

    public func addICECandidate(_ iceCandidate: RTCIceCandidate) {
         guard let pc = peerConnection else {
            if config.isLoggingEnabled { logger.error("PeerConnection not available when trying to add ICE candidate.") }
            return
         }
         if pc.remoteDescription == nil {
            if config.isLoggingEnabled { logger.warning("Remote description not set yet when adding ICE candidate. Proceeding for Trickle ICE.") }
         }

        if config.isLoggingEnabled { logger.debug("Adding received ICE candidate: \(iceCandidate.sdp)") }
        pc.add(iceCandidate) { [weak self] (error) in
             guard let self = self else { return }
             if let error = error {
                 if self.config.isLoggingEnabled { self.logger.error("Failed to add ICE candidate: \(error.localizedDescription)") }
             } else {
                  if self.config.isLoggingEnabled { self.logger.debug("ICE candidate added successfully.") }
             }
        }
    }

    public func switchCamera() {
        guard let camControls = self.cameraControlProvider else {
            if config.isLoggingEnabled { logger.warning("switchCamera called but not in camera provider mode.") }
            return
        }
        camControls.switchCamera()
    }

    public func setPreviewMirrored(_ mirrored: Bool) {
        if config.isLoggingEnabled { logger.info("HuanCaptureManager: Setting preview mirrored: \(mirrored)") }
        internalPreviewView.transform = mirrored ? CGAffineTransform(scaleX: -1.0, y: 1.0) : .identity
        cameraControlProvider?.setPreviewMirrored(mirrored)
    }

    // MARK: - Camera Type Management
    
    @discardableResult
    public func switchBackCameraType() -> CameraType? {
        guard let camControls = self.cameraControlProvider else {
            if config.isLoggingEnabled { logger.warning("switchBackCameraType called but not in camera provider mode.") }
            return nil
        }
        return camControls.switchBackCameraType()
    }
    
    @discardableResult
    public func switchToBackCameraType(_ type: CameraType) -> CameraType? {
        guard let camControls = self.cameraControlProvider else {
            if config.isLoggingEnabled { logger.warning("switchToBackCameraType called but not in camera provider mode.") }
            return nil
        }
        return camControls.switchToBackCameraType(type)
    }
    
    // MARK: - Available Camera Detection
    
    // MARK: - Private Helpers

    private func configureSenderParameters() {
        guard let pc = peerConnection, 
              let sender = pc.senders.first(where: { $0.track?.kind == kRTCMediaStreamTrackKindVideo }),
              !sender.parameters.encodings.isEmpty else {
            if config.isLoggingEnabled { logger.warning("Could not configure sender parameters: No video sender or empty encodings.") }
            return
        }

        let parameters = sender.parameters
        var encodingParam = parameters.encodings[0]
        
        encodingParam.maxBitrateBps = NSNumber(value: config.maxBitrateBps)
        encodingParam.minBitrateBps = NSNumber(value: config.minBitrateBps)
        encodingParam.maxFramerate = NSNumber(value: config.maxFramerateFps)
        if let scaleResolutionDownBy = config.scaleResolutionDownBy {
            encodingParam.scaleResolutionDownBy = NSNumber(value: scaleResolutionDownBy)
        }
        
        
        parameters.encodings[0] = encodingParam
        sender.parameters = parameters 

        if config.isLoggingEnabled { 
            logger.info("Applied encoding parameters: MaxBitrate=\(config.maxBitrateBps), MinBitrate=\(config.minBitrateBps), MaxFramerate=\(config.maxFramerateFps)") 
        }
     }

    // MARK: - RTCPeerConnectionDelegate

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        if config.isLoggingEnabled { logger.info("PeerConnection signaling state changed: \(stateChanged.descriptionString)") }
    }

    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        if config.isLoggingEnabled { logger.info("PeerConnection should negotiate.") }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async { [weak self] in // Ensure UI/state updates are on main thread
            guard let self = self else { return }

            let previousState = self.connectionState
            guard previousState != newState else { return }
            self.connectionState = newState

            let wasStopping = self.isStoppingManually
            if self.config.isLoggingEnabled { self.logger.info("ICE State Change: \(previousState.descriptionString) -> \(newState.descriptionString) (Manually Stopping: \(wasStopping))") }

            switch newState {
            case .connected, .completed:
                if self.config.isLoggingEnabled { self.logger.info("WebRTC Connection Established.") }
                self.isStoppingManually = false
                self.captureError = nil
                if case .esMessenger = self.config.signalingMode {
                     self.sendAvailableBackCamerasToEsDevice()
                }

            case .disconnected:
                if wasStopping {
                    if self.config.isLoggingEnabled { self.logger.info("WebRTC Disconnected during manual stop process.") }
                } else {
                    if self.config.isLoggingEnabled { self.logger.warning("WebRTC Connection Disconnected unexpectedly. May recover.") }
                }

            case .failed:
                if wasStopping {
                    if self.config.isLoggingEnabled { self.logger.info("WebRTC Connection Failed during manual stop process. Clearing potential errors.") }
                    self.captureError = nil
                } else {
                    if self.config.isLoggingEnabled { self.logger.error("WebRTC Connection Failed unexpectedly.") }
                    self.captureError = NSError(domain: "HuanCaptureError", code: 7, userInfo: [NSLocalizedDescriptionKey: "ICE connection failed"])
                }

            case .closed:
                if self.config.isLoggingEnabled { self.logger.info("WebRTC Connection Closed.") }
                self.isStoppingManually = false
                if let currentError = self.captureError as NSError?,
                   currentError.domain == "HuanCaptureError",
                   currentError.code == 7 {
                    self.captureError = nil 
                }

            case .new, .checking, .count:
                if self.config.isLoggingEnabled { self.logger.debug("WebRTC Connection State is intermediate: \(newState.descriptionString)") }

            @unknown default:
                if self.config.isLoggingEnabled { self.logger.warning("Unknown ICE Connection State encountered: \(newState.descriptionString)") }
            }
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        if config.isLoggingEnabled { logger.info("PeerConnection ICE gathering state changed: \(newState.descriptionString)") }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        if config.isLoggingEnabled { logger.info("Generated ICE candidate: \(candidate.sdp)") }
        
        if let server = signalingServer {
             server.sendCandidate(sdp: candidate.sdp, sdpMid: candidate.sdpMid, sdpMLineIndex: candidate.sdpMLineIndex)
        } else {
             DispatchQueue.main.async { [weak self] in
                 guard let self = self else { return }
                 if self.config.signalingMode == .custom {
                     if self.config.isLoggingEnabled { self.logger.info("Sending ICE candidate via PassthroughSubject for custom mode.") }
                     self.iceCandidateSubject.send(candidate)
                 } else if case .esMessenger = self.config.signalingMode {
                     if self.config.isLoggingEnabled { self.logger.warning("Generated ICE candidate in esMessenger mode but signalingServer is nil.") }
                 } else if self.config.signalingMode == .webSocket {
                      if self.config.isLoggingEnabled { self.logger.warning("Generated ICE candidate in webSocket mode but signalingServer is nil.") }
                 }
             }
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        if config.isLoggingEnabled { logger.info("Removed \(candidates.count) ICE candidate(s).") }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if config.isLoggingEnabled { logger.info("PeerConnection did add stream: \(stream.streamId) - (Unused in send-only)") }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        if config.isLoggingEnabled { logger.info("PeerConnection did remove stream: \(stream.streamId) - (Unused in send-only)") }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        if config.isLoggingEnabled { logger.info("PeerConnection did open data channel: \(dataChannel.label) - (Unused in send-only)") }
    }

    // MARK: - SignalingServerDelegate (NEW)

    public func signalingServer(didReceiveAnswer sdp: String) {
        if config.isLoggingEnabled { logger.info("SignalingDelegate: Received Answer SDP") }
        let sessionDescription = RTCSessionDescription(type: .answer, sdp: sdp)
        self.setRemoteDescription(sessionDescription)
    }

    public func signalingServer(didReceiveCandidate candidate: String, sdpMid: String?, sdpMLineIndex: Int32?) {
        if config.isLoggingEnabled { logger.info("SignalingDelegate: Received ICE Candidate") }
        let iceCandidate = RTCIceCandidate(sdp: candidate, sdpMLineIndex: sdpMLineIndex ?? -1, sdpMid: sdpMid)
        self.addICECandidate(iceCandidate)
    }

    // MARK: - WebSocketSignalingServerStateDelegate (Was WebSocketSignalingServerDelegate)
    
    // Renamed method to match the new delegate protocol
    internal func webSocketServer(_ server: WebSocketSignalingServer, didChangeState newState: WebSocketServerState) {
        var newPublicStatus: PublicWebSocketStatus? = nil

        // Map internal WS state to public status
        switch newState {
        case .idle:
            newPublicStatus = .idle
        case .starting:
            newPublicStatus = .starting
        case .listening(let port):
            newPublicStatus = .listening(port: port)
        case .stopped:
            newPublicStatus = .stopped
        case .failed(let error):
            newPublicStatus = .failed(error?.localizedDescription ?? "Unknown error")
        case .clientConnected:
            newPublicStatus = .clientConnected
        case .clientDisconnected:
            newPublicStatus = .clientDisconnected
        }
        
        if let status = newPublicStatus {
            DispatchQueue.main.async {
                if case .webSocket = self.config.signalingMode {
                     self.webSocketStatus = status
                }
            }
        }

        if config.isLoggingEnabled { logger.debug("Manager received WS state update: \(String(describing: newState)) -> Mapped Public Status: \(String(describing: newPublicStatus)) ") }
    }
    

    // MARK: - Logging Control
    public func setLogging(enabled: Bool) {
        if config.isLoggingEnabled != enabled {
             logger.info("Logging setting change requested to: \(enabled). Note: Affects future checks, not past logs or provider's log setting if passed at init.")
        }
    }

    // VideoFrameProviderDelegate Methods
    public func videoFrameProvider(_ provider: VideoFrameProvider, didCapture videoFrame: RTCVideoFrame) {
        self.videoSource.capturer(self, didCapture: videoFrame)
    }
    public func videoFrameProvider(_ provider: VideoFrameProvider, didEncounterError error: Error) {
        DispatchQueue.main.async { self.captureError = error }
        if config.isLoggingEnabled { logger.error("Error from VideoFrameProvider: \(error.localizedDescription)") }
        }
    public func videoFrameProvider(_ provider: VideoFrameProvider, didUpdateCameraPosition position: AVCaptureDevice.Position) {
        DispatchQueue.main.async { self.currentCameraPosition = position }
}
    public func videoFrameProvider(_ provider: VideoFrameProvider, didUpdateCameraType type: CameraType) {
        DispatchQueue.main.async { self.currentCameraType = type }
    }
    public func videoFrameProvider(_ provider: VideoFrameProvider, didUpdateAvailableBackCameraTypes types: [CameraType]) {
        DispatchQueue.main.async { self.availableBackCameraTypes = types }
    }
    public func videoFrameProvider(_ provider: VideoFrameProvider, didUpdatePreviewMirrored mirrored: Bool) {
        DispatchQueue.main.async { self.isPreviewMirrored = mirrored }
    }
}


