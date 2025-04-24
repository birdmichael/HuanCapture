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

public enum CameraType {
    case wideAngle
    case telephoto
    case ultraWide
    
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


public class HuanCaptureManager: RTCVideoCapturer, AVCaptureVideoDataOutputSampleBufferDelegate, RTCPeerConnectionDelegate, ObservableObject {

    @Published public private(set) var connectionState: RTCIceConnectionState = .new
    @Published public private(set) var localSDP: RTCSessionDescription?
    @Published public private(set) var captureError: Error?
    @Published public private(set) var currentCameraPosition: AVCaptureDevice.Position = .back
    @Published public private(set) var currentCameraType: CameraType = .wideAngle
    @Published public private(set) var availableBackCameraTypes: [CameraType] = []
    @Published public var deviceOrientation: UIDeviceOrientation = .portrait
    public let iceCandidateSubject = PassthroughSubject<RTCIceCandidate, Never>()
    public let previewView: UIView

    public var isLoggingEnabled: Bool = true

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
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HuanCapture")
    private var isStoppingManually = false

    public override init() {
        self.previewView = internalPreviewView
        super.init()
        if isLoggingEnabled { logger.info("HuanCapture initializing...") }

        internalPreviewView.videoContentMode = .scaleAspectFill

        setupWebRTC()
        setupAVFoundation()
        if isLoggingEnabled { logger.info("HuanCapture initialized.") }
    }

    deinit {
        if let track = videoTrack {
            track.remove(internalPreviewView)
        }
        stopStreaming()
        if isLoggingEnabled { logger.info("HuanCapture deinitialized.") }
    }

    // MARK: - Setup

    private func setupWebRTC() {
        if isLoggingEnabled { logger.debug("Setting up WebRTC...") }
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        peerConnectionFactory = RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)

        configureAudioSession()

        videoSource = peerConnectionFactory.videoSource()
        videoTrack = peerConnectionFactory.videoTrack(with: videoSource, trackId: "video0")

        videoTrack.add(internalPreviewView)
        if isLoggingEnabled { logger.debug("Added video track to internal preview view.") }
        if isLoggingEnabled { logger.debug("WebRTC setup complete.") }
    }

    private func configureAudioSession() {
        if isLoggingEnabled { logger.debug("Configuring RTCAudioSession...") }
        rtcAudioSession.lockForConfiguration()
        defer {
            rtcAudioSession.unlockForConfiguration()
            if isLoggingEnabled { logger.debug("RTCAudioSession configuration unlocked.") }
        }
        do {
            try rtcAudioSession.setCategory(AVAudioSession.Category.playAndRecord)
            try rtcAudioSession.setMode(AVAudioSession.Mode.videoChat)
            try rtcAudioSession.overrideOutputAudioPort(.speaker)
            if isLoggingEnabled { logger.info("RTCAudioSession configured successfully (Audio Disabled).") }
        } catch {
            if isLoggingEnabled { logger.error("Error configuring RTCAudioSession: \(error.localizedDescription)") }
        }
    }

    private func setupAVFoundation() {
        if isLoggingEnabled { logger.debug("Setting up AVFoundation...") }
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .vga640x480

        currentCameraPosition = .back
        currentCameraType = .wideAngle
        

        detectAvailableBackCameraTypes()
        guard let videoDevice = findCamera(position: currentCameraPosition, type: currentCameraType) else {
            if isLoggingEnabled { logger.error("Failed to find back camera.") }
            DispatchQueue.main.async { [weak self] in
                 guard let self = self else { return }
                 self.captureError = NSError(domain: "HuanCaptureError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Back camera not found"])
            }
            return
        }

        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            if isLoggingEnabled { logger.error("Failed to create AVCaptureDeviceInput: \(error.localizedDescription)") }
            DispatchQueue.main.async { [weak self] in
                 guard let self = self else { return }
                 self.captureError = error
            }
            return
        }

        if let input = videoDeviceInput, captureSession.canAddInput(input) {
            captureSession.addInput(input)
            if isLoggingEnabled { logger.debug("AVCaptureDeviceInput added.") }
        } else {
            if isLoggingEnabled { logger.error("Could not add video device input to capture session.") }
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
            if isLoggingEnabled { logger.debug("AVCaptureVideoDataOutput added.") }
        } else {
            if isLoggingEnabled { logger.error("Could not add video data output to capture session.") }
            DispatchQueue.main.async { [weak self] in
                 guard let self = self else { return }
                 self.captureError = NSError(domain: "HuanCaptureError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not add video output"])
            }
            return
        }

        if isLoggingEnabled { logger.debug("AVFoundation setup complete.") }
    }

    private func findCamera(position: AVCaptureDevice.Position, type: CameraType? = nil) -> AVCaptureDevice? {
        if isLoggingEnabled { 
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
                if isLoggingEnabled { logger.info("Found camera of requested type: \(targetCamera.localizedName)") }
                return targetCamera
            } else {
                if isLoggingEnabled { logger.warning("Camera of type \(type.localizedName) not found, falling back to default") }
            }
        }
        
        // 如果没有指定类型或找不到指定类型，则优先选择广角相机
        if let wideAngle = discoverySession.devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) {
             if isLoggingEnabled { logger.info("Found built-in wide angle camera: \(wideAngle.localizedName)") }
            return wideAngle
        }

        // 如果没有找到广角相机，则返回第一个可用的相机
        let device = discoverySession.devices.first
        if let device = device {
             if isLoggingEnabled { logger.info("Found camera: \(device.localizedName)") }
        } else {
             if isLoggingEnabled { logger.warning("Camera not found for position: \(position.rawValue)") }
        }
        return device
    }

    // MARK: - Public Control Methods

    public func startStreaming() {
        if isLoggingEnabled { logger.info("Attempting to start streaming...") }
        self.isStoppingManually = false
        guard peerConnection == nil else {
            if isLoggingEnabled { logger.warning("Streaming already started or starting.") }
            return
        }

        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        peerConnection = peerConnectionFactory.peerConnection(with: configuration, constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: self)

        guard let pc = peerConnection else {
            if isLoggingEnabled { logger.error("Failed to create RTCPeerConnection.") }
            DispatchQueue.main.async { [weak self] in
                 guard let self = self else { return }
                 self.captureError = NSError(domain: "HuanCaptureError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create PeerConnection"])
            }
            return
        }
        if isLoggingEnabled { logger.info("RTCPeerConnection created.") }

        let streamIds = ["stream0"]
        let initObject = RTCRtpTransceiverInit()
        initObject.direction = .sendOnly
        initObject.streamIds = streamIds
        if pc.addTransceiver(with: videoTrack, init: initObject) != nil {
             if isLoggingEnabled { logger.debug("Video transceiver added with direction sendOnly.") }
        } else {
             if isLoggingEnabled { logger.error("Failed to add video transceiver.") }
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
             DispatchQueue.main.async {
                 guard let self = self else { return }
                 if let error = error {
                     if self.isLoggingEnabled { self.logger.error("Failed to create offer SDP: \(error.localizedDescription)") }
                     self.captureError = error
                     self.stopStreaming()
                     return
                 }

                 guard let sdp = sdp else {
                     if self.isLoggingEnabled { self.logger.error("SDP offer is nil, but no error reported.") }
                     self.captureError = NSError(domain: "HuanCaptureError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create offer, SDP was nil"])
                     self.stopStreaming()
                     return
                 }

                 if self.isLoggingEnabled { self.logger.info("Offer SDP created successfully.") }
                 pc.setLocalDescription(sdp) { [weak self] (error) in
                      DispatchQueue.main.async {
                          guard let self = self else { return }
                          if let error = error {
                             if self.isLoggingEnabled { self.logger.error("Failed to set local SDP: \(error.localizedDescription)") }
                             self.captureError = error
                             self.stopStreaming()
                             return
                          }
                          if self.isLoggingEnabled { self.logger.info("Local SDP set successfully.") }
                          self.localSDP = sdp
                          self.startCaptureSession()
                      }
                 }
             }
        }
    }

    public func stopStreaming() {
        guard peerConnection != nil || captureSession.isRunning else {
            if isLoggingEnabled { logger.info("Streaming already stopped or not running.") }
            return
        }

        if isLoggingEnabled { logger.info("Attempting to stop streaming...") }
        self.isStoppingManually = true

        stopCaptureSession()

        if let pc = peerConnection {
            pc.close()
            if isLoggingEnabled { logger.info("RTCPeerConnection close() called.") }
        }
        peerConnection = nil

        DispatchQueue.main.async {
             if self.connectionState != .closed {
                 self.connectionState = .closed
             }
             self.localSDP = nil
             self.captureError = nil
        }
        if isLoggingEnabled { logger.info("Streaming stop requested.") }
    }

    public func setRemoteDescription(_ remoteSDP: RTCSessionDescription) {
        guard let pc = peerConnection else {
            if isLoggingEnabled { logger.error("PeerConnection not available when trying to set remote description.") }
            return
        }
         guard pc.localDescription != nil else {
            if isLoggingEnabled { logger.error("Local description must be set before setting remote description.") }
            DispatchQueue.main.async { [weak self] in
                 guard let self = self else { return }
                 self.captureError = NSError(domain: "HuanCaptureError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Local description not set"])
            }
            return
         }

        if isLoggingEnabled { logger.info("Setting remote SDP (type: \(remoteSDP.type.rawValue))...") }
        pc.setRemoteDescription(remoteSDP) { [weak self] (error) in
             DispatchQueue.main.async {
                 guard let self = self else { return }
                 if let error = error {
                     if self.isLoggingEnabled { self.logger.error("Failed to set remote SDP: \(error.localizedDescription)") }
                     self.captureError = error
                     return
                 }
                 if self.isLoggingEnabled { self.logger.info("Remote SDP set successfully.") }
             }
        }
    }

    public func addICECandidate(_ iceCandidate: RTCIceCandidate) {
         guard let pc = peerConnection else {
            if isLoggingEnabled { logger.error("PeerConnection not available when trying to add ICE candidate.") }
            return
         }
         guard pc.remoteDescription != nil else {
            if isLoggingEnabled { logger.warning("Remote description not set yet, queuing ICE candidate might be necessary depending on signaling.") }
             return
         }

        if isLoggingEnabled { logger.debug("Adding received ICE candidate: \(iceCandidate.sdp)") }
        pc.add(iceCandidate) { [weak self] (error) in
             guard let self = self else { return }
             if let error = error {
                 if self.isLoggingEnabled { self.logger.error("Failed to add ICE candidate: \(error.localizedDescription)") }
             } else {
                  if self.isLoggingEnabled { self.logger.debug("ICE candidate added successfully.") }
             }
        }
    }

    public func switchCamera() {
        if isLoggingEnabled { logger.info("Attempting to switch camera...") }
        guard let captureSession = self.captureSession else {
            if isLoggingEnabled { logger.warning("Capture session not initialized.") }
            return
        }

        videoOutputQueue.async { [weak self] in
            guard let self = self else { return }

            let targetPosition: AVCaptureDevice.Position = (self.currentCameraPosition == .back) ? .front : .back
            if self.isLoggingEnabled { self.logger.debug("Switching camera to position: \(targetPosition.rawValue)") }

            // 切换到前置摄像头时重置为广角类型，切换到后置时保持当前类型
            let targetCameraType = targetPosition == .front ? .wideAngle : self.currentCameraType
            guard let videoDevice = self.findCamera(position: targetPosition, type: targetCameraType) else {
                if self.isLoggingEnabled { self.logger.error("Failed to find camera for position: \\(targetPosition.rawValue)") }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.captureError = NSError(domain: "HuanCaptureError", code: 9, userInfo: [NSLocalizedDescriptionKey: "Target camera not found: \\(targetPosition)"])
                }
                return
            }

            guard let newVideoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
                if self.isLoggingEnabled { self.logger.error("Failed to create AVCaptureDeviceInput for the new camera.") }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.captureError = NSError(domain: "HuanCaptureError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to create new camera input"])
                }
                return
            }

            captureSession.beginConfiguration()
            defer {
                captureSession.commitConfiguration()
                if self.isLoggingEnabled { self.logger.debug("Capture session configuration committed.") }
            }

            if let currentInput = self.videoDeviceInput {
                captureSession.removeInput(currentInput)
                if self.isLoggingEnabled { self.logger.debug("Removed old camera input.") }
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
                if self.isLoggingEnabled { self.logger.info("Successfully switched camera to \(targetPosition.rawValue).") }
            } else {
                if self.isLoggingEnabled { self.logger.error("Could not add new camera input to capture session.") }
                if let currentInput = self.videoDeviceInput, captureSession.canAddInput(currentInput) {
                    captureSession.addInput(currentInput)
                    if self.isLoggingEnabled { self.logger.warning("Re-added previous camera input after failing to add new one.") }
                } else {
                    if self.isLoggingEnabled { self.logger.error("Failed to re-add previous input either. Capture session might be broken.") }
                }
                 DispatchQueue.main.async { [weak self] in
                      guard let self = self else { return }
                      self.captureError = NSError(domain: "HuanCaptureError", code: 11, userInfo: [NSLocalizedDescriptionKey: "Could not add new camera input"])
                 }
            }
        }
    }

    public func setPreviewMirrored(_ mirrored: Bool) {
        if isLoggingEnabled { logger.info("Setting preview mirrored: \(mirrored)") }
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
        if isLoggingEnabled { logger.info("Attempting to switch to specific back camera type: \(type.localizedName)...") }
        
        guard currentCameraPosition == .back else {
            if isLoggingEnabled { logger.warning("Cannot switch camera type when using front camera.") }
            return nil
        }
        
        guard availableBackCameraTypes.contains(type) else {
            if isLoggingEnabled { logger.warning("Requested camera type \(type.localizedName) is not available on this device.") }
            return nil
        }
        
        if currentCameraType == type {
            if isLoggingEnabled { logger.info("Already using camera type: \(type.localizedName)") }
            return currentCameraType
        }
        
        guard let captureSession = self.captureSession else {
            if isLoggingEnabled { logger.warning("Capture session not initialized.") }
            return nil
        }
        
        var result: CameraType? = nil
        let semaphore = DispatchSemaphore(value: 0)
        
        videoOutputQueue.async { [weak self] in
            guard let self = self else { 
                semaphore.signal()
                return 
            }
            
            if self.isLoggingEnabled { self.logger.debug("Switching camera type to: \(type.localizedName)") }
            
            guard let videoDevice = self.findCamera(position: .back, type: type) else {
                if self.isLoggingEnabled { self.logger.error("Could not find camera device for type \(type.localizedName)") }
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
            if isLoggingEnabled { logger.warning("No multiple available back camera types") }
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
        if isLoggingEnabled { logger.info("Attempting to switch back camera type...") }
        
        guard currentCameraPosition == .back else {
            if isLoggingEnabled { logger.warning("Cannot switch camera type when using front camera.") }
            return
        }
        
        guard let captureSession = self.captureSession else {
            if isLoggingEnabled { logger.warning("Capture session not initialized.") }
            return
        }
        
        videoOutputQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard let nextCameraType = self.getNextAvailableCameraType() else {
                if self.isLoggingEnabled { self.logger.warning("No available next camera type") }
                return
            }
            
            if self.isLoggingEnabled { self.logger.debug("Switching camera type to: \(nextCameraType.localizedName)") }
            

            guard let videoDevice = self.findCamera(position: .back, type: nextCameraType) else {
                if self.isLoggingEnabled { self.logger.warning("Could not find camera of type \(nextCameraType.localizedName), trying next type") }
                
                let alternativeType: CameraType
                if let nextTypeIndex = self.availableBackCameraTypes.firstIndex(where: { $0 == nextCameraType }),
                   self.availableBackCameraTypes.count > 1 {
                    let alternativeIndex = (nextTypeIndex + 1) % self.availableBackCameraTypes.count
                    alternativeType = self.availableBackCameraTypes[alternativeIndex]
                } else {
                    alternativeType = .wideAngle
                }
                
                guard let alternativeDevice = self.findCamera(position: .back, type: alternativeType) else {
                    if self.isLoggingEnabled { self.logger.error("No alternative camera types available") }
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.captureError = NSError(domain: "HuanCaptureError", code: 12, userInfo: [NSLocalizedDescriptionKey: "没有可用的其他类型摄像头"])
                    }
                    return
                }
                
                if self.isLoggingEnabled { self.logger.info("Found alternative camera type: \(alternativeType.localizedName)") }
                self.switchToCamera(device: alternativeDevice, type: alternativeType)
                return
            }
            
            self.switchToCamera(device: videoDevice, type: nextCameraType)
        }
    }
    private func switchToCamera(device: AVCaptureDevice, type: CameraType) -> Bool {
        guard let captureSession = self.captureSession else { return false }
        
        guard let newVideoInput = try? AVCaptureDeviceInput(device: device) else {
            if self.isLoggingEnabled { self.logger.error("Failed to create AVCaptureDeviceInput for the new camera.") }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.captureError = NSError(domain: "HuanCaptureError", code: 13, userInfo: [NSLocalizedDescriptionKey: "无法创建新摄像头输入"])
            }
            return false
        }
        
        captureSession.beginConfiguration()
        defer {
            captureSession.commitConfiguration()
            if self.isLoggingEnabled { self.logger.debug("Capture session configuration committed.") }
        }
        
        if let currentInput = self.videoDeviceInput {
            captureSession.removeInput(currentInput)
            if self.isLoggingEnabled { self.logger.debug("Removed old camera input.") }
        }
        
        if captureSession.canAddInput(newVideoInput) {
            captureSession.addInput(newVideoInput)
            self.videoDeviceInput = newVideoInput
            DispatchQueue.main.async {
                self.currentCameraType = type
            }
            if self.isLoggingEnabled { self.logger.info("Successfully switched to camera type: \(type.localizedName)") }
            return true
        } else {
            if self.isLoggingEnabled { self.logger.error("Could not add new camera input to capture session.") }
            if let currentInput = self.videoDeviceInput, captureSession.canAddInput(currentInput) {
                captureSession.addInput(currentInput)
                if self.isLoggingEnabled { self.logger.warning("Re-added previous camera input after failing to add new one.") }
            } else {
                if self.isLoggingEnabled { self.logger.error("Failed to re-add previous input either. Capture session might be broken.") }
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
        if isLoggingEnabled { logger.debug("Detecting available back camera types...") }
        
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
            if isLoggingEnabled { logger.info("Device supports back wide angle camera") }
        }
        
        if discoverySession.devices.contains(where: { $0.deviceType == .builtInTelephotoCamera }) {
            detectedTypes.append(.telephoto)
            if isLoggingEnabled { logger.info("Device supports back telephoto camera") }
        }
        
        if discoverySession.devices.contains(where: { $0.deviceType == .builtInUltraWideCamera }) {
            detectedTypes.append(.ultraWide)
            if isLoggingEnabled { logger.info("Device supports back ultra wide camera") }
        }
        
        if detectedTypes.isEmpty {
            detectedTypes.append(.wideAngle)
            if isLoggingEnabled { logger.warning("No back camera types detected, using wide angle as default") }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.availableBackCameraTypes = detectedTypes
            if self.isLoggingEnabled { self.logger.debug("Available back camera types: \(detectedTypes.map { $0.localizedName }.joined(separator: ", "))") }
        }
    }
    
    // MARK: - Private Helpers

    private func startCaptureSession() {
        if isLoggingEnabled { logger.info("Starting AVCaptureSession...") }
        videoOutputQueue.async { [weak self] in
             guard let self = self else { return }
             if !self.captureSession.isRunning {
                 self.captureSession.startRunning()
                 if self.isLoggingEnabled { self.logger.info("AVCaptureSession started.") }
            } else {
                 if self.isLoggingEnabled { self.logger.warning("AVCaptureSession already running.") }
            }
        }
    }

    private func stopCaptureSession() {
        if isLoggingEnabled { logger.info("Stopping AVCaptureSession...") }
         videoOutputQueue.async { [weak self] in
             guard let self = self else { return }
             if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                 if self.isLoggingEnabled { self.logger.info("AVCaptureSession stopped.") }
            } else {
                 if self.isLoggingEnabled { self.logger.warning("AVCaptureSession already stopped.") }
            }
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            if isLoggingEnabled { logger.warning("Failed to get CVPixelBuffer from CMSampleBuffer.") }
            return
        }
        let timeStampNs = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1_000_000_000
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)

        let rotation: RTCVideoRotation = {
            switch (self.currentCameraPosition, self.deviceOrientation) {
            case (.front, .portrait):
                return ._90
            case (.front, .portraitUpsideDown):
                return ._270
            case (.front, .landscapeLeft):
                return ._180
            case (.front, .landscapeRight):
                return ._0
            case (.back, .portrait):
                return ._90
            case (.back, .portraitUpsideDown):
                return ._270
            case (.back, .landscapeLeft):
                return ._0
            case (.back, .landscapeRight):
                return ._180
            default:
                if self.isLoggingEnabled { logger.warning("Camera position is not front or back (\(self.currentCameraPosition.rawValue)) or unknown orientation (\(self.deviceOrientation.rawValue)), using default rotation.") }
                return ._90
            }
        }()

        let rtcVideoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: rotation, timeStampNs: Int64(timeStampNs))
        videoSource.capturer(self, didCapture: rtcVideoFrame)
    }

    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
         if isLoggingEnabled { logger.warning("Dropped video frame.") }
     }

    // MARK: - RTCPeerConnectionDelegate

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        if isLoggingEnabled { logger.info("PeerConnection signaling state changed: \(stateChanged.description)") }
    }

    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        if isLoggingEnabled { logger.info("PeerConnection should negotiate.") }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let previousState = self.connectionState
            guard previousState != newState else { return }
            self.connectionState = newState

            let wasStopping = self.isStoppingManually
            if self.isLoggingEnabled { self.logger.info("ICE State Change: \(previousState.description) -> \(newState.description) (Manually Stopping: \(wasStopping))") }

            switch newState {
            case .connected, .completed:
                if self.isLoggingEnabled { self.logger.info("WebRTC Connection Established.") }
                self.isStoppingManually = false
                self.captureError = nil

            case .disconnected:
                if wasStopping {
                    if self.isLoggingEnabled { self.logger.info("WebRTC Disconnected during manual stop process.") }
                } else {
                    if self.isLoggingEnabled { self.logger.warning("WebRTC Connection Disconnected unexpectedly. May recover.") }
                }

            case .failed:
                if wasStopping {
                    if self.isLoggingEnabled { self.logger.info("WebRTC Connection Failed during manual stop process. Clearing potential errors.") }
                    self.captureError = nil
                } else {
                    if self.isLoggingEnabled { self.logger.error("WebRTC Connection Failed unexpectedly.") }
                    self.captureError = NSError(domain: "HuanCaptureError", code: 7, userInfo: [NSLocalizedDescriptionKey: "ICE connection failed"])
                }

            case .closed:
                if self.isLoggingEnabled { self.logger.info("WebRTC Connection Closed.") }
                self.isStoppingManually = false
                if let currentError = self.captureError as NSError?,
                   currentError.domain == "HuanCaptureError",
                   currentError.code == 7 {
                    self.captureError = nil
                }

            case .new, .checking, .count:
                if self.isLoggingEnabled { self.logger.debug("WebRTC Connection State is intermediate: \(newState.description)") }

            @unknown default:
                if self.isLoggingEnabled { self.logger.warning("Unknown ICE Connection State encountered: \(newState.description)") }
            }
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        if isLoggingEnabled { logger.info("PeerConnection ICE gathering state changed: \(newState.description)") }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        if isLoggingEnabled { logger.info("Generated ICE candidate: \(candidate.sdp)") }
         DispatchQueue.main.async { [weak self] in
             guard let self = self else { return }
             self.iceCandidateSubject.send(candidate)
         }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        if isLoggingEnabled { logger.info("Removed \(candidates.count) ICE candidate(s).") }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if isLoggingEnabled { logger.info("PeerConnection did add stream: \(stream.streamId) - (Unused in send-only)") }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        if isLoggingEnabled { logger.info("PeerConnection did remove stream: \(stream.streamId) - (Unused in send-only)") }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        if isLoggingEnabled { logger.info("PeerConnection did open data channel: \(dataChannel.label) - (Unused in send-only)") }
    }
}
