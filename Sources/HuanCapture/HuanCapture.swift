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

#if canImport(es_cast_client_ios)
import es_cast_client_ios
#endif

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

public class HuanCaptureManager: RTCVideoCapturer, AVCaptureVideoDataOutputSampleBufferDelegate, RTCPeerConnectionDelegate, SignalingServerDelegate, WebSocketSignalingServerStateDelegate, ObservableObject {

    @Published public private(set) var connectionState: RTCIceConnectionState = .new
    @Published public private(set) var localSDP: RTCSessionDescription?
    @Published public private(set) var captureError: Error?
    @Published public private(set) var currentCameraPosition: AVCaptureDevice.Position = .back
    @Published public private(set) var currentCameraType: CameraType = .wideAngle
    @Published public private(set) var availableBackCameraTypes: [CameraType] = []
    @Published public var deviceOrientation: UIDeviceOrientation = .portrait
    @Published public private(set) var webSocketStatus: PublicWebSocketStatus = .idle
    public let iceCandidateSubject = PassthroughSubject<RTCIceCandidate, Never>()
    public let previewView: UIView
    public private(set) var config: HuanCaptureConfig

    private let internalPreviewView = RTCMTLVideoView(frame: .zero)
    private var peerConnectionFactory: RTCPeerConnectionFactory!
    private var peerConnection: RTCPeerConnection?
    private var videoSource: RTCVideoSource!
    private var videoTrack: RTCVideoTrack!
    private let rtcAudioSession = RTCAudioSession.sharedInstance()
    private var captureSession: AVCaptureSession!
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoOutputQueue = DispatchQueue(label: "com.huancapture.videoOutputQueue")
    internal let logger: Logger
    private var isStoppingManually = false
    internal var signalingServer: SignalingServerProtocol?
    private var lastLoggedOrientationWarning: (AVCaptureDevice.Position, UIDeviceOrientation)? = nil

    public var isLoggingEnabled: Bool {
        get { return config.isLoggingEnabled }
    }
    
    @available(*, deprecated, message: "Use init(config:) instead to specify configuration.")
    public convenience override init() {
        self.init(config: HuanCaptureConfig.default)
    }

    public init(config: HuanCaptureConfig = HuanCaptureConfig.default) {
        self.config = config
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.huancapture", category: "HuanCapture")
        self.previewView = internalPreviewView
        super.init()
        if config.isLoggingEnabled { logger.info("HuanCapture initializing with config: Mode=\(String(describing: config.signalingMode)), Logging=\(config.isLoggingEnabled)") }

        internalPreviewView.videoContentMode = .scaleAspectFill

        switch config.signalingMode {
        case .webSocket:
            let wsSignaler = WebSocketSignalingServer(port: config.webSocketPort, isLoggingEnabled: config.isLoggingEnabled)
            wsSignaler.delegate = self
            wsSignaler.internalStateDelegate = self
            self.signalingServer = wsSignaler
            self.webSocketStatus = .idle
            if config.isLoggingEnabled { logger.info("Using WebSocket signaling mode.") }
            
        #if canImport(es_cast_client_ios)
            
        case .esMessenger(let device):
            setupEsSignaling(device: device)
            self.webSocketStatus = .notApplicable
            if config.isLoggingEnabled { logger.info("Using EsMessenger signaling mode.") }
        
            if config.isLoggingEnabled { logger.error("EsMessenger mode configured but es_cast_client_ios not imported. Falling back to custom mode.") }
            self.signalingServer = nil
            self.webSocketStatus = .notApplicable
            
            #endif
            
        case .custom:
            self.signalingServer = nil
            self.webSocketStatus = .notApplicable
            if config.isLoggingEnabled { logger.info("Using custom signaling mode.") }
        default:
             if config.isLoggingEnabled { logger.warning("Unknown signaling mode encountered during init. Defaulting to custom.") }
             self.signalingServer = nil
             self.webSocketStatus = .notApplicable
        }

        setupWebRTC()
        setupAVFoundation()
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

    private func setupAVFoundation() {
        if config.isLoggingEnabled { logger.debug("Setting up AVFoundation...") }
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .hd4K3840x2160

        currentCameraPosition = .back
        currentCameraType = .wideAngle
        

        detectAvailableBackCameraTypes()
        guard let videoDevice = findCamera(position: currentCameraPosition, type: currentCameraType) else {
            if config.isLoggingEnabled { logger.error("Failed to find back camera.") }
            DispatchQueue.main.async { [weak self] in
                 guard let self = self else { return }
                 self.captureError = NSError(domain: "HuanCaptureError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Back camera not found"])
            }
            return
        }

        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            if config.isLoggingEnabled { logger.error("Failed to create AVCaptureDeviceInput: \(error.localizedDescription)") }
            DispatchQueue.main.async { [weak self] in
                 guard let self = self else { return }
                 self.captureError = error
            }
            return
        }

        if let input = videoDeviceInput, captureSession.canAddInput(input) {
            captureSession.addInput(input)
            if config.isLoggingEnabled { logger.debug("AVCaptureDeviceInput added.") }
        } else {
            if config.isLoggingEnabled { logger.error("Could not add video device input to capture session.") }
            DispatchQueue.main.async { [weak self] in
                 guard let self = self else { return }
                 self.captureError = NSError(domain: "HuanCaptureError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not add video input"])
            }
            return
        }

        videoDataOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            if config.isLoggingEnabled { logger.debug("AVCaptureVideoDataOutput added.") }
        } else {
            if config.isLoggingEnabled { logger.error("Could not add video data output to capture session.") }
            DispatchQueue.main.async { [weak self] in
                 guard let self = self else { return }
                 self.captureError = NSError(domain: "HuanCaptureError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not add video output"])
            }
            return
        }

        if config.isLoggingEnabled { logger.debug("AVFoundation setup complete.") }
    }

    private func findCamera(position: AVCaptureDevice.Position, type: CameraType? = nil) -> AVCaptureDevice? {
        if config.isLoggingEnabled { 
            if let type = type {
                logger.debug("Searching for camera with position: \(position.rawValue) and type: \(type.localizedName)")
            } else {
                logger.debug("Searching for camera with position: \(position.rawValue)")
            }
        }

        #if os(iOS)
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInUltraWideCamera]
        #elseif os(macOS)
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        #else
        let deviceTypes: [AVCaptureDevice.DeviceType] = []
        #endif

        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: position)
        
        // 如果指定了相机类型，则优先查找该类型
        if let type = type {
            let targetDeviceType = type.deviceType
            if let targetCamera = discoverySession.devices.first(where: { $0.deviceType == targetDeviceType }) {
                if config.isLoggingEnabled { logger.info("Found camera of requested type: \(targetCamera.localizedName)") }
                return targetCamera
            } else {
                if config.isLoggingEnabled { logger.warning("Camera of type \(type.localizedName) not found, falling back to default") }
            }
        }
        
        // 如果没有指定类型或找不到指定类型，则优先选择广角相机
        if let wideAngle = discoverySession.devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) {
             if config.isLoggingEnabled { logger.info("Found built-in wide angle camera: \(wideAngle.localizedName)") }
            return wideAngle
        }

        // 如果没有找到广角相机，则返回第一个可用的相机
        let device = discoverySession.devices.first
        if let device = device {
             if config.isLoggingEnabled { logger.info("Found camera: \(device.localizedName)") }
        } else {
             if config.isLoggingEnabled { logger.warning("Camera not found for position: \(position.rawValue)") }
        }
        return device
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
                          
                          self.startCaptureSession()
                      }
                 }
             }
        }
    }

    public func stopStreaming() {
        guard peerConnection != nil || captureSession.isRunning else {
            if config.isLoggingEnabled { logger.info("Streaming already stopped or not running.") }
            return
        }

        if config.isLoggingEnabled { logger.info("Attempting to stop streaming...") }
        self.isStoppingManually = true

        signalingServer?.stop()

        stopCaptureSession()

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
        if config.isLoggingEnabled { logger.info("Attempting to switch camera...") }
        guard let captureSession = self.captureSession else {
            if config.isLoggingEnabled { logger.warning("Capture session not initialized.") }
            return
        }

        videoOutputQueue.async { [weak self] in
            guard let self = self else { return }

            let targetPosition: AVCaptureDevice.Position = (self.currentCameraPosition == .back) ? .front : .back
            if self.config.isLoggingEnabled { self.logger.debug("Switching camera to position: \(targetPosition.rawValue)") }

            let targetCameraType = targetPosition == .front ? .wideAngle : self.currentCameraType
            guard let videoDevice = self.findCamera(position: targetPosition, type: targetCameraType) else {
                if self.config.isLoggingEnabled { self.logger.error("Failed to find camera for position: \(targetPosition.rawValue)") }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.captureError = NSError(domain: "HuanCaptureError", code: 9, userInfo: [NSLocalizedDescriptionKey: "Target camera not found: \(targetPosition)"])
                }
                return
            }

            guard let newVideoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
                if self.config.isLoggingEnabled { self.logger.error("Failed to create AVCaptureDeviceInput for the new camera.") }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.captureError = NSError(domain: "HuanCaptureError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to create new camera input"])
                }
                return
            }

            captureSession.beginConfiguration()
            defer {
                captureSession.commitConfiguration()
                if self.config.isLoggingEnabled { self.logger.debug("Capture session configuration committed.") }
            }

            if let currentInput = self.videoDeviceInput {
                captureSession.removeInput(currentInput)
                if self.config.isLoggingEnabled { self.logger.debug("Removed old camera input.") }
            }

            if captureSession.canAddInput(newVideoInput) {
                captureSession.addInput(newVideoInput)
                self.videoDeviceInput = newVideoInput
                DispatchQueue.main.async {
                     self.currentCameraPosition = targetPosition
                     if targetPosition == .front {
                         self.currentCameraType = .wideAngle
                     }
                }
                if self.config.isLoggingEnabled { self.logger.info("Successfully switched camera to \(targetPosition.rawValue).") }
            } else {
                if self.config.isLoggingEnabled { self.logger.error("Could not add new camera input to capture session.") }
                if let currentInput = self.videoDeviceInput, captureSession.canAddInput(currentInput) {
                    captureSession.addInput(currentInput)
                    if self.config.isLoggingEnabled { self.logger.warning("Re-added previous camera input after failing to add new one.") }
                } else {
                    if self.config.isLoggingEnabled { self.logger.error("Failed to re-add previous input either. Capture session might be broken.") }
                }
                 DispatchQueue.main.async { [weak self] in
                      guard let self = self else { return }
                      self.captureError = NSError(domain: "HuanCaptureError", code: 11, userInfo: [NSLocalizedDescriptionKey: "Could not add new camera input"])
                 }
            }
        }
    }

    public func setPreviewMirrored(_ mirrored: Bool) {
        if config.isLoggingEnabled { logger.info("Setting preview mirrored: \(mirrored)") }
        internalPreviewView.transform = mirrored ? CGAffineTransform(scaleX: -1.0, y: 1.0) : .identity
    }

    // MARK: - Camera Type Management
    
    @discardableResult
    public func switchBackCameraType() -> CameraType? {
        if let nextType = getNextAvailableCameraType() {
            return switchToBackCameraType(nextType)
        }
        return nil
    }
    
    @discardableResult
    public func switchToBackCameraType(_ type: CameraType) -> CameraType? {
        if config.isLoggingEnabled { logger.info("Attempting to switch to specific back camera type: \(type.localizedName)...") }
        
        guard currentCameraPosition == .back else {
            if config.isLoggingEnabled { logger.warning("Cannot switch camera type when using front camera.") }
            return nil
        }
        
        guard availableBackCameraTypes.contains(type) else {
            if config.isLoggingEnabled { logger.warning("Requested camera type \(type.localizedName) is not available on this device.") }
            return nil
        }
        
        if currentCameraType == type {
            if config.isLoggingEnabled { logger.info("Already using camera type: \(type.localizedName)") }
            return currentCameraType
        }
        
        guard let captureSession = self.captureSession else {
            if config.isLoggingEnabled { logger.warning("Capture session not initialized.") }
            return nil
        }
        
        var result: CameraType? = nil
        let semaphore = DispatchSemaphore(value: 0)
        
        videoOutputQueue.async { [weak self] in
            guard let self = self else { 
                semaphore.signal()
                return 
            }
            
            if self.config.isLoggingEnabled { self.logger.debug("Switching camera type to: \(type.localizedName)") }
            
            guard let videoDevice = self.findCamera(position: .back, type: type) else {
                if self.config.isLoggingEnabled { self.logger.error("Could not find camera device for type \(type.localizedName)") }
                semaphore.signal()
                return
            }
            
            if self.switchToCamera(device: videoDevice, type: type) {
                result = type
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 2.0)
        return result
    }
    
    private func getNextAvailableCameraType() -> CameraType? {
        if availableBackCameraTypes.isEmpty || availableBackCameraTypes.count == 1 {
            if config.isLoggingEnabled { logger.warning("No multiple available back camera types") }
            return nil
        }
        
        if let currentIndex = availableBackCameraTypes.firstIndex(where: { $0 == currentCameraType }) {
            let nextIndex = (currentIndex + 1) % availableBackCameraTypes.count
            return availableBackCameraTypes[nextIndex]
        } else {
            return availableBackCameraTypes.first
        }
    }
    
    private func switchBackCameraType_legacy() {
        if config.isLoggingEnabled { logger.info("Attempting to switch back camera type...") }
        
        guard currentCameraPosition == .back else {
            if config.isLoggingEnabled { logger.warning("Cannot switch camera type when using front camera.") }
            return
        }
        
        guard let captureSession = self.captureSession else {
            if config.isLoggingEnabled { logger.warning("Capture session not initialized.") }
            return
        }
        
        videoOutputQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard let nextCameraType = self.getNextAvailableCameraType() else {
                if self.config.isLoggingEnabled { self.logger.warning("No available next camera type") }
                return
            }
            
            if self.config.isLoggingEnabled { self.logger.debug("Switching camera type to: \(nextCameraType.localizedName)") }
            

            guard let videoDevice = self.findCamera(position: .back, type: nextCameraType) else {
                if self.config.isLoggingEnabled { self.logger.warning("Could not find camera of type \(nextCameraType.localizedName), trying next type") }
                
                let alternativeType: CameraType
                if let nextTypeIndex = self.availableBackCameraTypes.firstIndex(where: { $0 == nextCameraType }),
                   self.availableBackCameraTypes.count > 1 {
                    let alternativeIndex = (nextTypeIndex + 1) % self.availableBackCameraTypes.count
                    alternativeType = self.availableBackCameraTypes[alternativeIndex]
                } else {
                    alternativeType = .wideAngle
                }
                
                guard let alternativeDevice = self.findCamera(position: .back, type: alternativeType) else {
                    if self.config.isLoggingEnabled { self.logger.error("No alternative camera types available") }
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.captureError = NSError(domain: "HuanCaptureError", code: 12, userInfo: [NSLocalizedDescriptionKey: "没有可用的其他类型摄像头"])
                    }
                    return
                }
                
                if self.config.isLoggingEnabled { self.logger.info("Found alternative camera type: \(alternativeType.localizedName)") }
                self.switchToCamera(device: alternativeDevice, type: alternativeType)
                return
            }
            
            self.switchToCamera(device: videoDevice, type: nextCameraType)
        }
    }
    private func switchToCamera(device: AVCaptureDevice, type: CameraType) -> Bool {
        guard let captureSession = self.captureSession else { return false }
        
        guard let newVideoInput = try? AVCaptureDeviceInput(device: device) else {
            if self.config.isLoggingEnabled { self.logger.error("Failed to create AVCaptureDeviceInput for the new camera.") }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.captureError = NSError(domain: "HuanCaptureError", code: 13, userInfo: [NSLocalizedDescriptionKey: "无法创建新摄像头输入"])
            }
            return false
        }
        
        captureSession.beginConfiguration()
        defer {
            captureSession.commitConfiguration()
            if self.config.isLoggingEnabled { self.logger.debug("Capture session configuration committed.") }
        }
        
        if let currentInput = self.videoDeviceInput {
            captureSession.removeInput(currentInput)
            if self.config.isLoggingEnabled { self.logger.debug("Removed old camera input.") }
        }
        
        if captureSession.canAddInput(newVideoInput) {
            captureSession.addInput(newVideoInput)
            self.videoDeviceInput = newVideoInput
            DispatchQueue.main.async {
                self.currentCameraType = type
            }
            if self.config.isLoggingEnabled { self.logger.info("Successfully switched to camera type: \(type.localizedName)") }
            return true
        } else {
            if self.config.isLoggingEnabled { self.logger.error("Could not add new camera input to capture session.") }
            if let currentInput = self.videoDeviceInput, captureSession.canAddInput(currentInput) {
                captureSession.addInput(currentInput)
                if self.config.isLoggingEnabled { self.logger.warning("Re-added previous camera input after failing to add new one.") }
            } else {
                if self.config.isLoggingEnabled { self.logger.error("Failed to re-add previous input either. Capture session might be broken.") }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.captureError = NSError(domain: "HuanCaptureError", code: 14, userInfo: [NSLocalizedDescriptionKey: "无法添加新摄像头输入"])
            }
            return false
        }
    }
    
    // MARK: - Available Camera Detection
    
    private func detectAvailableBackCameraTypes() {
        if config.isLoggingEnabled { logger.debug("Detecting available back camera types...") }
        
        var detectedTypes: [CameraType] = []
        
        #if os(iOS)
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInUltraWideCamera]
        #elseif os(macOS)
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        #else
        let deviceTypes: [AVCaptureDevice.DeviceType] = []
        #endif
        
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .back)
        
        if discoverySession.devices.contains(where: { $0.deviceType == .builtInWideAngleCamera }) {
            detectedTypes.append(.wideAngle)
            if config.isLoggingEnabled { logger.info("Device supports back wide angle camera") }
        }
        
        if discoverySession.devices.contains(where: { $0.deviceType == .builtInTelephotoCamera }) {
            detectedTypes.append(.telephoto)
            if config.isLoggingEnabled { logger.info("Device supports back telephoto camera") }
        }
        
        if discoverySession.devices.contains(where: { $0.deviceType == .builtInUltraWideCamera }) {
            detectedTypes.append(.ultraWide)
            if config.isLoggingEnabled { logger.info("Device supports back ultra wide camera") }
        }
        
        if detectedTypes.isEmpty {
            detectedTypes.append(.wideAngle)
            if config.isLoggingEnabled { logger.warning("No back camera types detected, using wide angle as default") }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.availableBackCameraTypes = detectedTypes
            if self.config.isLoggingEnabled { self.logger.debug("Available back camera types: \(detectedTypes.map { $0.localizedName }.joined(separator: ", "))") }
        }
    }
    
    // MARK: - Private Helpers

    private func configureSenderParameters() {
        guard let pc = peerConnection else {
            if config.isLoggingEnabled { logger.warning("PeerConnection not available for configuring sender parameters.") }
            return
        }

        guard let sender = pc.senders.first(where: { $0.track?.kind == kRTCMediaStreamTrackKindVideo }) else {
            if config.isLoggingEnabled { logger.warning("Could not find video sender to configure parameters.") }
            return
        }

        let parameters = sender.parameters

        guard !parameters.encodings.isEmpty else {
            if config.isLoggingEnabled { logger.warning("Sender parameters encodings array is empty.") }
            return
        }

        var encodingParam = parameters.encodings[0]
        
        encodingParam.maxBitrateBps = NSNumber(value: config.maxBitrateBps)
        
        encodingParam.minBitrateBps = NSNumber(value: config.minBitrateBps)
        
        encodingParam.maxFramerate = NSNumber(value: config.maxFramerateFps)
        
        parameters.encodings[0] = encodingParam
        sender.parameters = parameters 
        if config.isLoggingEnabled { 
            logger.info("Applied encoding parameters from config: MaxBitrate=\(self.config.maxBitrateBps), MinBitrate=\(self.config.minBitrateBps), MaxFramerate=\(self.config.maxFramerateFps)") 
        }
    }
    
    private func startCaptureSession() {
        if config.isLoggingEnabled { logger.info("Starting AVCaptureSession...") }
        videoOutputQueue.async { [weak self] in
             guard let self = self else { return }
             if !self.captureSession.isRunning {
                 self.captureSession.startRunning()
                 if self.config.isLoggingEnabled { self.logger.info("AVCaptureSession started.") }
            } else {
                 if self.config.isLoggingEnabled { self.logger.warning("AVCaptureSession already running.") }
            }
        }
    }

    private func stopCaptureSession() {
        if config.isLoggingEnabled { logger.info("Stopping AVCaptureSession...") }
         videoOutputQueue.async { [weak self] in
             guard let self = self else { return }
             if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                 if self.config.isLoggingEnabled { self.logger.info("AVCaptureSession stopped.") }
            } else {
                 if self.config.isLoggingEnabled { self.logger.warning("AVCaptureSession already stopped.") }
            }
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            if config.isLoggingEnabled { logger.warning("Failed to get CVPixelBuffer from CMSampleBuffer.") }
            return
        }
        let timeStampNs = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1_000_000_000
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)

        let rotation: RTCVideoRotation = {
            let currentCombination = (self.currentCameraPosition, self.deviceOrientation)
            var rotationResult: RTCVideoRotation = ._90 
            var isHandled = false
            
            switch currentCombination {
            case (.front, .portrait):           rotationResult = ._90; isHandled = true
            case (.front, .portraitUpsideDown): rotationResult = ._270; isHandled = true
            case (.front, .landscapeLeft):      rotationResult = ._180; isHandled = true
            case (.front, .landscapeRight):     rotationResult = ._0;   isHandled = true
            case (.back, .portrait):            rotationResult = ._90; isHandled = true
            case (.back, .portraitUpsideDown):  rotationResult = ._270; isHandled = true
            case (.back, .landscapeLeft):       rotationResult = ._0;   isHandled = true
            case (.back, .landscapeRight):      rotationResult = ._180; isHandled = true
            default:
                
                isHandled = false
            }
            
            if !isHandled {
                
                if self.config.isLoggingEnabled {
                    
                    var shouldLogWarning = false
                    if let lastWarning = self.lastLoggedOrientationWarning {
                        
                        if lastWarning != currentCombination {
                            shouldLogWarning = true
                        }
                    } else {
                        
                        shouldLogWarning = true
                    }

                    
                    if shouldLogWarning {
                       logger.warning("Unhandled device orientation \(self.deviceOrientation.rawValue) for camera position \(self.currentCameraPosition.rawValue). Using default rotation (.rotation90).")
                       self.lastLoggedOrientationWarning = currentCombination 
                    }
                }
            } else {
                
                self.lastLoggedOrientationWarning = nil
            }
            
            return rotationResult
        }()

        let rtcVideoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: rotation, timeStampNs: Int64(timeStampNs))
        videoSource.capturer(self, didCapture: rtcVideoFrame)
    }

    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
         if config.isLoggingEnabled { logger.warning("Dropped video frame.") }
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
                #if canImport(es_cast_client_ios)
                if case .esMessenger = self.config.signalingMode {
                     self.sendAvailableBackCamerasToEsDevice()
                }
                #endif

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
                 #if canImport(es_cast_client_ios)
                 if self.config.signalingMode == .custom {
                     if self.config.isLoggingEnabled { self.logger.info("Sending ICE candidate via PassthroughSubject for custom mode.") }
                     self.iceCandidateSubject.send(candidate)
                 } else if case .esMessenger = self.config.signalingMode {
                     if self.config.isLoggingEnabled { self.logger.warning("Generated ICE candidate in esMessenger mode but signalingServer is nil.") }
                 } else if self.config.signalingMode == .webSocket {
                      if self.config.isLoggingEnabled { self.logger.warning("Generated ICE candidate in webSocket mode but signalingServer is nil.") }
                 }
                 #else
                 if self.config.signalingMode == .custom {
                     if self.config.isLoggingEnabled { self.logger.info("Sending ICE candidate via PassthroughSubject for custom mode (es_cast_client_ios not imported).") }
                     self.iceCandidateSubject.send(candidate)
                 } else {
                     if self.config.isLoggingEnabled { self.logger.warning("Generated ICE candidate but no signaling server available and not in custom mode (es_cast_client_ios not imported).") }
                 }
                 #endif
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
             logger.info("Logging setting change requested: \(enabled ? "Enabled" : "Disabled") (Note: Affects future checks of config.isLoggingEnabled)")
        }
    }
}

