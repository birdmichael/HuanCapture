import WebRTC
import ReplayKit
import AVFoundation

public class InAppScreenFrameProvider: NSObject, VideoFrameProvider {
    public weak var delegate: VideoFrameProviderDelegate?
    public private(set) var isRunning: Bool = false

    private let logger = PrintLog()
    private let isLoggingEnabled: Bool
    private let screenRecorder = RPScreenRecorder.shared()

    public init(isLoggingEnabled: Bool = true) {
        self.isLoggingEnabled = isLoggingEnabled
        screenRecorder.isMicrophoneEnabled = false
        super.init()
    }

    public static func create(isLoggingEnabled: Bool = true) -> InAppScreenFrameProvider {
        return InAppScreenFrameProvider(isLoggingEnabled: isLoggingEnabled)
    }

    public func startProviding() {
        guard !isRunning else {
            if isLoggingEnabled { logger.warning("InAppScreenFrameProvider: Already running.") }
            return
        }

        guard screenRecorder.isAvailable else {
            if isLoggingEnabled { logger.error("InAppScreenFrameProvider: Screen recording is not available.") }
            delegate?.videoFrameProvider(self, didEncounterError: NSError(domain: "InAppScreenFrameProviderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Screen recording not available."]))
            return
        }

        if isLoggingEnabled { logger.info("InAppScreenFrameProvider: Attempting to start screen capture.") }

        screenRecorder.startCapture(handler: { [weak self] (sampleBuffer, bufferType, error) in
            guard let self = self else { return }
            guard self.isRunning else { return }

            if let error = error {
                if self.isLoggingEnabled { self.logger.error("InAppScreenFrameProvider: Capture error: \\(error.localizedDescription)") }
                self.delegate?.videoFrameProvider(self, didEncounterError: error)
                self.stopProviding() // Stop if an error occurs during capture
                return
            }

            if bufferType == .video {
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                    if self.isLoggingEnabled { self.logger.warning("InAppScreenFrameProvider: Could not get pixel buffer from sample buffer.") }
                    return
                }

                let timestampNs = Int64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1_000_000_000)
                
                let rotation = RTCVideoRotation._0

                let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
                let rtcVideoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: rotation, timeStampNs: timestampNs)
                self.delegate?.videoFrameProvider(self, didCapture: rtcVideoFrame)
            }

        }) { [weak self] (error) in
            guard let self = self else { return }
            if let error = error {
                if self.isLoggingEnabled { self.logger.error("InAppScreenFrameProvider: Failed to start capture: \\(error.localizedDescription)") }
                self.delegate?.videoFrameProvider(self, didEncounterError: error)
                self.isRunning = false
            } else {
                if self.isLoggingEnabled { self.logger.info("InAppScreenFrameProvider: Screen capture started successfully.") }
                self.isRunning = true
            }
        }
    }

    public func stopProviding() {
        guard isRunning else {
            if isLoggingEnabled { logger.info("InAppScreenFrameProvider: Not running or already stopped.") }
            return
        }

        if isLoggingEnabled { logger.info("InAppScreenFrameProvider: Stopping screen capture.") }
        
        screenRecorder.stopCapture { [weak self] (error) in
            guard let self = self else { return }
            if let error = error {
                if self.isLoggingEnabled { self.logger.error("InAppScreenFrameProvider: Error stopping capture: \\(error.localizedDescription)") }
            } else {
                if self.isLoggingEnabled { self.logger.info("InAppScreenFrameProvider: Screen capture stopped successfully.") }
            }
        }
        isRunning = false
    }
} 
