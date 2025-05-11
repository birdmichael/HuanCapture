import WebRTC
import CoreVideo

public class ExternalFrameProvider: VideoFrameProvider {
    public weak var delegate: VideoFrameProviderDelegate?
    public private(set) var isRunning: Bool = false

    private let logger = PrintLog()
    private let isLoggingEnabled: Bool

    public init( isLoggingEnabled: Bool = true) {
        self.isLoggingEnabled = isLoggingEnabled
    }

    public static func create(isLoggingEnabled: Bool = true) -> ExternalFrameProvider {
        return ExternalFrameProvider(isLoggingEnabled: isLoggingEnabled)
    }

    public func startProviding() {
        if isLoggingEnabled { logger.info("ExternalFrameProvider: Starting (ready to receive frames).") }
        isRunning = true
    }

    public func stopProviding() {
        if isLoggingEnabled { logger.info("ExternalFrameProvider: Stopping (will no longer process frames).") }
        isRunning = false
    }

    public func consumePixelBuffer(_ pixelBuffer: CVPixelBuffer, rotation: RTCVideoRotation, timestampNs: Int64) {
        guard isRunning else {
            if isLoggingEnabled { logger.warning("ExternalFrameProvider: Not running, dropping external pixel buffer.") }
            return
        }

        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let rtcVideoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: rotation, timeStampNs: timestampNs)
        delegate?.videoFrameProvider(self, didCapture: rtcVideoFrame)
    }
} 
