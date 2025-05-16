import Foundation
import es_cast_client_ios

public enum SignalingMode {
    case webSocket
    case esMessenger(EsDevice)
    case custom

    public static func == (lhs: SignalingMode, rhs: SignalingMode) -> Bool {
        switch (lhs, rhs) {
        case (.webSocket, .webSocket):
            return true
        case let (.esMessenger(d1), .esMessenger(d2)):
             return d1.id == d2.id
      
        case (.custom, .custom):
            return true
        default:
             return false
        }
    }
}

public struct HuanCaptureConfig {
    public let webSocketPort: UInt16
    @available(*, deprecated, message: "Use signalingMode instead.")
    public var enableWebSocketSignaling: Bool {
        switch signalingMode {
         case .webSocket: return true
         default: return false
         }
    }
    public let isLoggingEnabled: Bool
    /// WebRTC 连接的最大比特率 (bps)。
    public let maxBitrateBps: Int
    /// WebRTC 连接的最小比特率 (bps)。
    public let minBitrateBps: Int
    /// WebRTC 连接的最大帧率 (fps)。
    public let maxFramerateFps: Int
    /// WebRTC 连接的视频缩放比例。
    public let scaleResolutionDownBy : Int?
    /// 使用的信令模式。
    public let signalingMode: SignalingMode

    public static let `default` = HuanCaptureConfig(signalingModeInput: .webSocket)

    public init(
        webSocketPort: UInt16 = 8080,
        isLoggingEnabled: Bool = true,
        maxBitrateBps: Int = 50_000_000,
        minBitrateBps: Int = 1_000_000,
        maxFramerateFps: Int = 30,
        scaleResolutionDownBy: Int? = nil,
        signalingModeInput: SignalingMode
    ) {
        self.webSocketPort = webSocketPort
        self.isLoggingEnabled = isLoggingEnabled
        self.maxBitrateBps = maxBitrateBps
        self.minBitrateBps = minBitrateBps
        self.maxFramerateFps = maxFramerateFps
        self.scaleResolutionDownBy = scaleResolutionDownBy
        self.signalingMode = signalingModeInput
    }
} 
