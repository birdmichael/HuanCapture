import Foundation

public protocol SignalingServerDelegate: AnyObject {
    func signalingServer(didReceiveAnswer sdp: String)
    
    func signalingServer(didReceiveCandidate candidate: String, sdpMid: String?, sdpMLineIndex: Int32?)
}

public protocol SignalingServerProtocol: AnyObject {
    var delegate: SignalingServerDelegate? { get set }
    
    func start()
    
    func stop()
    
    func sendOffer(sdp: String)
    
    func sendCandidate(sdp: String, sdpMid: String?, sdpMLineIndex: Int32?)
} 
