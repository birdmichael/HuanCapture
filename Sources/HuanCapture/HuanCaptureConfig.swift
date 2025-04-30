import Foundation
#if canImport(es_cast_client_ios)
import es_cast_client_ios
#endif

public enum SignalingMode {
    case webSocket
    #if canImport(es_cast_client_ios)
    case esMessenger(EsDevice)
    #endif
    case custom

    public static func == (lhs: SignalingMode, rhs: SignalingMode) -> Bool {
        switch (lhs, rhs) {
        case (.webSocket, .webSocket):
            return true
#if canImport(es_cast_client_ios)
        case let (.esMessenger(d1), .esMessenger(d2)):
             return d1.id == d2.id
        #endif
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
    /// 使用的信令模式。
    public let signalingMode: SignalingMode

    public static let `default` = HuanCaptureConfig(signalingModeInput: .webSocket)

    public init(
        webSocketPort: UInt16 = 8080,
        isLoggingEnabled: Bool = true,
        maxBitrateBps: Int = 50_000_000,
        minBitrateBps: Int = 1_000_000,
        maxFramerateFps: Int = 30,
        signalingModeInput: SignalingMode
    ) {
        self.webSocketPort = webSocketPort
        self.isLoggingEnabled = isLoggingEnabled
        self.maxBitrateBps = maxBitrateBps
        self.minBitrateBps = minBitrateBps
        self.maxFramerateFps = maxFramerateFps
        self.signalingMode = signalingModeInput
    }
} 
