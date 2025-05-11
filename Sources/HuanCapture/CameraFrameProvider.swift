import AVFoundation
import WebRTC
import UIKit

public class CameraFrameProvider: NSObject, VideoFrameProvider, CameraControlProvider, AVCaptureVideoDataOutputSampleBufferDelegate {
    public weak var delegate: VideoFrameProviderDelegate?
    public private(set) var isRunning: Bool = false

    public private(set) var currentCameraPosition: AVCaptureDevice.Position
    public private(set) var currentCameraType: CameraType
    public private(set) var availableBackCameraTypes: [CameraType] = []
    public var deviceOrientation: UIDeviceOrientation = .portrait
    public private(set) var isPreviewMirrored: Bool = false

    private let captureSession: AVCaptureSession
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let videoDataOutput: AVCaptureVideoDataOutput
    private let videoOutputQueue: DispatchQueue
    private let logger = PrintLog()
    private let isLoggingEnabled: Bool
    private var lastLoggedOrientationWarning: (AVCaptureDevice.Position, UIDeviceOrientation)? = nil

    public init(isLoggingEnabled: Bool = true,
                initialPosition: AVCaptureDevice.Position = .back,
                initialType: CameraType = .wideAngle) {
        self.isLoggingEnabled = isLoggingEnabled
        self.currentCameraPosition = initialPosition
        self.currentCameraType = initialPosition == .front ? .wideAngle : initialType 

        self.captureSession = AVCaptureSession()
        self.videoDataOutput = AVCaptureVideoDataOutput()
        self.videoOutputQueue = DispatchQueue(label: "com.huancapture.camera.videoOutputQueue")
        super.init()
        setupAVFoundation()
    }

    public static func create(isLoggingEnabled: Bool = true,
                              initialPosition: AVCaptureDevice.Position = .back, 
                              initialType: CameraType = .wideAngle) -> CameraFrameProvider {
        return CameraFrameProvider(isLoggingEnabled: isLoggingEnabled, 
                                   initialPosition: initialPosition, 
                                   initialType: initialType)
    }

    private func setupAVFoundation() {
        if isLoggingEnabled { logger.debug("CameraProvider: Setting up AVFoundation...") }
        captureSession.sessionPreset = .hd4K3840x2160

        detectAvailableBackCameraTypes()
        guard let videoDevice = findCamera(position: currentCameraPosition, type: currentCameraType) else {
            let error = NSError(domain: "CameraFrameProviderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Initial camera not found for position \(currentCameraPosition) and type \(currentCameraType.localizedName)"])
            if isLoggingEnabled { logger.error("CameraProvider: \(error.localizedDescription)") }
            delegate?.videoFrameProvider(self, didEncounterError: error)
            return
        }

        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            if isLoggingEnabled { logger.error("CameraProvider: Failed to create AVCaptureDeviceInput: \(error.localizedDescription)") }
            delegate?.videoFrameProvider(self, didEncounterError: error)
            return
        }

        if let input = videoDeviceInput, captureSession.canAddInput(input) {
            captureSession.addInput(input)
        } else {
            let error = NSError(domain: "CameraFrameProviderError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not add video device input to capture session"])
            if isLoggingEnabled { logger.error("CameraProvider: \(error.localizedDescription)") }
            delegate?.videoFrameProvider(self, didEncounterError: error)
            return
        }

        videoDataOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        } else {
            let error = NSError(domain: "CameraFrameProviderError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not add video data output to capture session"])
            if isLoggingEnabled { logger.error("CameraProvider: \(error.localizedDescription)") }
            delegate?.videoFrameProvider(self, didEncounterError: error)
            return
        }
        if isLoggingEnabled { logger.debug("CameraProvider: AVFoundation setup complete.") }
    }

    public func startProviding() {
        if isLoggingEnabled { logger.info("CameraProvider: Starting capture session...") }
        videoOutputQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                self.isRunning = true
                if self.isLoggingEnabled { self.logger.info("CameraProvider: Capture session started.") }
            } else {
                if self.isLoggingEnabled { self.logger.warning("CameraProvider: Capture session already running.") }
            }
        }
    }

    public func stopProviding() {
        if isLoggingEnabled { logger.info("CameraProvider: Stopping capture session...") }
        videoOutputQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                self.isRunning = false
                if self.isLoggingEnabled { self.logger.info("CameraProvider: Capture session stopped.") }
            } else {
                if self.isLoggingEnabled { self.logger.warning("CameraProvider: Capture session already stopped.") }
            }
        }
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            if isLoggingEnabled { logger.warning("CameraProvider: Failed to get CVPixelBuffer.") }
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
                if self.isLoggingEnabled {
                    var shouldLogWarning = false
                    if let lastWarning = self.lastLoggedOrientationWarning {
                        if lastWarning != currentCombination {
                            shouldLogWarning = true
                        }
                    } else {
                        shouldLogWarning = true
                    }
                    if shouldLogWarning {
                       logger.warning("CameraProvider: Unhandled orientation \(self.deviceOrientation.rawValue) for camera \(self.currentCameraPosition.rawValue). Defaulting to ._90.")
                       self.lastLoggedOrientationWarning = currentCombination 
                    }
                }
            } else {
                self.lastLoggedOrientationWarning = nil
            }
            return rotationResult
        }()

        let rtcVideoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: rotation, timeStampNs: Int64(timeStampNs))
        delegate?.videoFrameProvider(self, didCapture: rtcVideoFrame)
    }

    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if isLoggingEnabled { logger.warning("CameraProvider: Dropped video frame.") }
    }
    
    private func findCamera(position: AVCaptureDevice.Position, type: CameraType? = nil) -> AVCaptureDevice? {
        if isLoggingEnabled { 
            let typeName = type?.localizedName ?? "any available"
            logger.debug("CameraProvider: Searching for camera position: \(position.rawValue), type: \(typeName)")
        }

        #if os(iOS)
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInUltraWideCamera]
        #else 
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera] // macOS example
        #endif

        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: position)
        
        if let type = type {
            let targetDeviceType = type.deviceType
            if let targetCamera = discoverySession.devices.first(where: { $0.deviceType == targetDeviceType }) {
                if isLoggingEnabled { logger.info("CameraProvider: Found requested type: \(targetCamera.localizedName)") }
                return targetCamera
            }
            if isLoggingEnabled { logger.warning("CameraProvider: Type \(type.localizedName) not found, falling back.") }
        }
        
        if let wideAngle = discoverySession.devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) {
            if isLoggingEnabled { logger.info("CameraProvider: Found wide angle: \(wideAngle.localizedName)") }
            return wideAngle
        }

        let device = discoverySession.devices.first
        if let device = device {
            if isLoggingEnabled { logger.info("CameraProvider: Found first available: \(device.localizedName)") }
        } else {
            if isLoggingEnabled { logger.warning("CameraProvider: No camera found for position: \(position.rawValue)") }
        }
        return device
    }
    
    private func detectAvailableBackCameraTypes() {
        if isLoggingEnabled { logger.debug("CameraProvider: Detecting available back camera types...") }
        var detectedTypes: [CameraType] = []
        #if os(iOS)
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInUltraWideCamera]
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .back)
        if discoverySession.devices.contains(where: { $0.deviceType == .builtInWideAngleCamera }) { detectedTypes.append(.wideAngle) }
        if discoverySession.devices.contains(where: { $0.deviceType == .builtInTelephotoCamera }) { detectedTypes.append(.telephoto) }
        if discoverySession.devices.contains(where: { $0.deviceType == .builtInUltraWideCamera }) { detectedTypes.append(.ultraWide) }
        #else
        detectedTypes.append(.wideAngle) // macOS default
        #endif
        
        if detectedTypes.isEmpty { detectedTypes.append(.wideAngle) }
        self.availableBackCameraTypes = detectedTypes
        delegate?.videoFrameProvider(self, didUpdateAvailableBackCameraTypes: detectedTypes)
        if isLoggingEnabled { logger.debug("CameraProvider: Available back types: \(detectedTypes.map { $0.localizedName }.joined(separator: ", "))") }
    }

    public func switchCamera() {
        if isLoggingEnabled { logger.info("CameraProvider: Attempting to switch camera...") }
        videoOutputQueue.async { [weak self] in
            guard let self = self else { return }
            let targetPosition: AVCaptureDevice.Position = (self.currentCameraPosition == .back) ? .front : .back
            let targetCameraType = targetPosition == .front ? .wideAngle : self.currentCameraType 

            guard let videoDevice = self.findCamera(position: targetPosition, type: targetCameraType) else {
                let error = NSError(domain: "CameraFrameProviderError", code: 9, userInfo: [NSLocalizedDescriptionKey: "Target camera not found for switch: \(targetPosition)"])
                if self.isLoggingEnabled { self.logger.error("CameraProvider: \(error.localizedDescription)") }
                self.delegate?.videoFrameProvider(self, didEncounterError: error)
                return
            }
            if self.switchToCameraDevice(videoDevice, position: targetPosition, type: targetCameraType) {
                self.delegate?.videoFrameProvider(self, didUpdateCameraPosition: self.currentCameraPosition)
                self.delegate?.videoFrameProvider(self, didUpdateCameraType: self.currentCameraType)
            }
        }
    }
    
    @discardableResult
    public func switchToBackCameraType(_ type: CameraType) -> CameraType? {
        if isLoggingEnabled { logger.info("CameraProvider: Attempting to switch to back camera type: \(type.localizedName)...") }
        guard currentCameraPosition == .back else {
            if isLoggingEnabled { logger.warning("CameraProvider: Cannot switch back camera type when using front camera.") }
            return nil
        }
        guard availableBackCameraTypes.contains(type) else {
            if isLoggingEnabled { logger.warning("CameraProvider: Requested camera type \(type.localizedName) is not available.") }
            return nil
        }
        if currentCameraType == type {
            if isLoggingEnabled { logger.info("CameraProvider: Already using camera type: \(type.localizedName)") }
            return currentCameraType
        }
        
        var resultType: CameraType? = nil
        let semaphore = DispatchSemaphore(value: 0)
        videoOutputQueue.async { [weak self] in
            guard let self = self else { semaphore.signal(); return }
            guard let videoDevice = self.findCamera(position: .back, type: type) else {
                let error = NSError(domain: "CameraFrameProviderError", code: 12, userInfo: [NSLocalizedDescriptionKey: "Could not find camera device for type \(type.localizedName)"])
                if self.isLoggingEnabled { self.logger.error("CameraProvider: \(error.localizedDescription)") }
                self.delegate?.videoFrameProvider(self, didEncounterError: error)
                semaphore.signal()
                return
            }
            if self.switchToCameraDevice(videoDevice, position: .back, type: type) {
                resultType = type
                self.delegate?.videoFrameProvider(self, didUpdateCameraType: self.currentCameraType)
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
        return resultType
    }
    
    @discardableResult
    public func switchBackCameraType() -> CameraType? {
        if availableBackCameraTypes.isEmpty || availableBackCameraTypes.count == 1 {
            if isLoggingEnabled { logger.warning("CameraProvider: No multiple available back camera types to switch.") }
            return nil
        }
        guard let currentIndex = availableBackCameraTypes.firstIndex(where: { $0 == currentCameraType }) else {
             return switchToBackCameraType(availableBackCameraTypes.first!) // Switch to first if current not found
        }
        let nextIndex = (currentIndex + 1) % availableBackCameraTypes.count
        return switchToBackCameraType(availableBackCameraTypes[nextIndex])
    }

    private func switchToCameraDevice(_ device: AVCaptureDevice, position: AVCaptureDevice.Position, type: CameraType) -> Bool {
        guard let newVideoInput = try? AVCaptureDeviceInput(device: device) else {
            let error = NSError(domain: "CameraFrameProviderError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to create new camera input for device \(device.localizedName)"])
            if isLoggingEnabled { logger.error("CameraProvider: \(error.localizedDescription)") }
            delegate?.videoFrameProvider(self, didEncounterError: error)
            return false
        }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        if let currentInput = self.videoDeviceInput {
            captureSession.removeInput(currentInput)
        }

        if captureSession.canAddInput(newVideoInput) {
            captureSession.addInput(newVideoInput)
            self.videoDeviceInput = newVideoInput
            self.currentCameraPosition = position
            self.currentCameraType = type 
            if isLoggingEnabled { logger.info("CameraProvider: Switched to camera \(device.localizedName), position \(position.rawValue), type \(type.localizedName).") }
            return true
        } else {
            if let currentInput = self.videoDeviceInput, captureSession.canAddInput(currentInput) { // Re-add old input
                captureSession.addInput(currentInput)
                if isLoggingEnabled { logger.warning("CameraProvider: Could not add new input, re-added previous one.") }
            } else {
                let error = NSError(domain: "CameraFrameProviderError", code: 11, userInfo: [NSLocalizedDescriptionKey: "Could not add new camera input, and failed to re-add previous."])
                 if isLoggingEnabled { logger.error("CameraProvider: \(error.localizedDescription)") }
                delegate?.videoFrameProvider(self, didEncounterError: error)
            }
            return false
        }
    }

    public func setPreviewMirrored(_ mirrored: Bool) {
        if isLoggingEnabled { logger.info("CameraProvider: Setting preview mirrored: \(mirrored)") }
        isPreviewMirrored = mirrored
        delegate?.videoFrameProvider(self, didUpdatePreviewMirrored: mirrored)
        
        // Actual mirroring of the video stream needs to be handled at the capturer/renderer level if needed.
        // The AVCaptureConnection's videoMirrored property is often what's used for local preview mirroring.
        // For WebRTC, if the remote side needs a mirrored view, that's usually handled by the sender
        // or negotiated. This flag is more for local state tracking or local preview hints.
        if let connection = videoDataOutput.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = mirrored && currentCameraPosition == .front // Often only front camera is mirrored
            }
        }
    }
} 
