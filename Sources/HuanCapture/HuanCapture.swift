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


public class HuanCaptureManager: RTCVideoCapturer, AVCaptureVideoDataOutputSampleBufferDelegate, RTCPeerConnectionDelegate, ObservableObject {

    @Published public private(set) var connectionState: RTCIceConnectionState = .new
    @Published public private(set) var localSDP: RTCSessionDescription?
    @Published public private(set) var captureError: Error?
    @Published public private(set) var currentCameraPosition: AVCaptureDevice.Position = .back
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
        guard let videoDevice = findCamera(position: currentCameraPosition) else {
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

    private func findCamera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if isLoggingEnabled { logger.debug("Searching for camera with position: \(position.rawValue)") }

        #if os(iOS)
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInUltraWideCamera]
        #elseif os(macOS)
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        #else
        let deviceTypes: [AVCaptureDevice.DeviceType] = []
        #endif

        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: position)

        if let wideAngle = discoverySession.devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) {
             if isLoggingEnabled { logger.info("Found built-in wide angle camera: \(wideAngle.localizedName)") }
            return wideAngle
        }

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

            guard let videoDevice = self.findCamera(position: targetPosition) else {
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
            switch self.currentCameraPosition {
            case .front:
                return ._90
            case .back:
                return ._90
            default:
                if self.isLoggingEnabled { logger.warning("Camera position is not front or back (\(self.currentCameraPosition.rawValue)), using rotation 0.") }
                return ._0
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
