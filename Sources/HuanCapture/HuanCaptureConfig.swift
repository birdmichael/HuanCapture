import Foundation


public struct HuanCaptureConfig {
    public var enableWebSocketSignaling: Bool

    public var webSocketPort: UInt16
    
    public var isLoggingEnabled: Bool
    
    public var maxBitrateBps: Int 
    
    public var minBitrateBps: Int
    
    public var maxFramerateFps: Int

    public static let `default` = HuanCaptureConfig()

    public init(
        enableWebSocketSignaling: Bool = true,
        webSocketPort: UInt16 = 8080,
        isLoggingEnabled: Bool = true,
        maxBitrateBps: Int = 50_000_000, 
        minBitrateBps: Int = 1_000_000,  
        maxFramerateFps: Int = 30        
    ) {
        self.enableWebSocketSignaling = enableWebSocketSignaling
        self.webSocketPort = webSocketPort
        self.isLoggingEnabled = isLoggingEnabled
        self.maxBitrateBps = maxBitrateBps
        self.minBitrateBps = minBitrateBps
        self.maxFramerateFps = maxFramerateFps
    }
} 
