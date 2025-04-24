import WebRTC

public extension RTCIceConnectionState {
    var description: String {
        switch self {
        case .new: return "New"
        case .checking: return "Checking"
        case .connected: return "Connected"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .disconnected: return "Disconnected"
        case .closed: return "Closed"
        case .count: return "Count"
        @unknown default: return "Unknown (\(self.rawValue))"
        }
    }
}

public extension RTCSignalingState {
     var description: String {
        switch self {
        case .stable: return "Stable"
        case .haveLocalOffer: return "HaveLocalOffer"
        case .haveLocalPrAnswer: return "HaveLocalPrAnswer"
        case .haveRemoteOffer: return "HaveRemoteOffer"
        case .haveRemotePrAnswer: return "HaveRemotePrAnswer"
        case .closed: return "Closed"
        @unknown default: return "Unknown (\(self.rawValue))"
        }
    }
}

public extension RTCIceGatheringState {
     var description: String {
        switch self {
        case .new: return "New"
        case .gathering: return "Gathering"
        case .complete: return "Complete"
        @unknown default: return "Unknown (\(self.rawValue))"
        }
    }
}

public extension RTCDataChannelState {
    var description: String {
        switch self {
        case .connecting: return "Connecting"
        case .open: return "Open"
        case .closing: return "Closing"
        case .closed: return "Closed"
        @unknown default: return "Unknown (\(self.rawValue))"
        }
    }
}

public extension RTCRtpMediaType {
    var description: String {
        switch self {
        case .audio: 
            return "Audio"
        case .video: 
            return "Video"
        case .data:
            return "data"
        case .unsupported:
            return "unsupported"
        @unknown default:
            return "Unknown (rawValue: \(self.rawValue))"
        }
    }
} 
