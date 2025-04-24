import Foundation
import Network
import OSLog

// MARK: - Server State Enum

enum WebSocketServerState {
    case idle
    case starting
    case listening(port: UInt16)
    case stopped
    case failed(Error?)
    case clientConnected(NWEndpoint)
    case clientDisconnected(NWEndpoint)
}

// MARK: - Signaling Message Structure

enum SignalingMessageType: String, Codable {
    case offer, answer, candidate
}

struct SignalingMessage: Codable {
    let type: SignalingMessageType
    let sessionDescription: String? // For offer/answer
    let candidate: CandidatePayload?  // For candidate
}

struct CandidatePayload: Codable {
    let sdp: String
    let sdpMLineIndex: Int32
    let sdpMid: String?
}

// TODO: 实现 WebSocket 服务器逻辑
// 你可能需要添加像 Starscream 这样的依赖到 Package.swift
// 或者使用 Network.framework (适用于较新的 Apple 平台)
class WebSocketSignalingServer {

    private let port: NWEndpoint.Port
    weak var delegate: WebSocketSignalingServerDelegate?
    private var listener: NWListener?
    private var connections: [NWEndpoint: NWConnection] = [:] // <-- Key by Endpoint
    private let queue = DispatchQueue(label: "com.huancapture.websocket.server.queue")
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.huancapture", category: "WebSocketServer")
    private var isRunning = false
    private let isLoggingEnabled: Bool
    private var state: WebSocketServerState = .idle {
        didSet {
            // Notify delegate on state change (on the main queue)
            DispatchQueue.main.async {
                 self.delegate?.webSocketServer(self, didChangeState: self.state)
            }
        }
    }

    // Storage for signaling state to send to new clients
    private var lastOfferSDP: String? = nil
    private var gatheredCandidates: [CandidatePayload] = []
    private let stateAccessQueue = DispatchQueue(label: "com.huancapture.websocket.server.state.queue") // For thread safety

    init(port: UInt16, isLoggingEnabled: Bool) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.isLoggingEnabled = isLoggingEnabled
        if isLoggingEnabled { logger.info("WebSocketSignalingServer initialized for port \(String(port)). Network.framework will be used.") }
        self.state = .idle // Initial state
    }

    deinit {
        stop()
    }

    func start() {
        // Reset state when starting
        stateAccessQueue.sync { 
            lastOfferSDP = nil
            gatheredCandidates.removeAll()
        }
        // New guard logic:
        switch state {
            case .idle, .stopped, .failed: 
                break // Proceed if in a startable state
            default: 
                // If not in a startable state, log and return
                if isLoggingEnabled { logger.warning("Server is not in a startable state (idle, stopped, or failed). Current state: \(String(describing: self.state))") }
                return
        }
        
        if isLoggingEnabled { logger.info("Attempting to start WebSocket server on port \(self.port.rawValue)... ") }
        state = .starting
        do {
            let parameters = NWParameters.tcp
            let webSocketOptions = NWProtocolWebSocket.Options()
             webSocketOptions.autoReplyPing = true
            parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)
            
            listener = try NWListener(using: parameters, on: self.port)
        } catch {
            let error = error
            if isLoggingEnabled { logger.error("Failed to create NWListener: \(error.localizedDescription)") }
            state = .failed(error)
            return
        }

        listener?.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            switch newState {
            case .ready:
                self.isRunning = true
                self.state = .listening(port: self.port.rawValue)
                if self.isLoggingEnabled { self.logger.info("WebSocket server started and listening on port \(self.port.rawValue)") }
            case .failed(let error):
                 if self.isLoggingEnabled { self.logger.error("WebSocket server failed to start: \(error.localizedDescription)") }
                 self.state = .failed(error)
                 // 尝试清理
                 self.listener?.cancel()
                 self.connections.forEach { $0.value.cancel() }
                 self.connections.removeAll()
                 self.isRunning = false
            case .cancelled:
                 if self.isLoggingEnabled { self.logger.info("WebSocket server listener cancelled.") }
                 self.state = .stopped // State change before setting isRunning
                 self.isRunning = false
            default:
                if self.isLoggingEnabled { self.logger.debug("Listener state changed: \(String(describing: newState))") }
            }
        }

        listener?.newConnectionHandler = { [weak self] newConnection in
            guard let self = self else { return }
            if self.isLoggingEnabled { self.logger.info("New client connection received from: \(String(describing: newConnection.endpoint))") }
             // State update happens within accept()
            self.accept(connection: newConnection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        // Reset state when stopping
        stateAccessQueue.sync {
            lastOfferSDP = nil
            gatheredCandidates.removeAll()
        }
        guard isRunning else {
            // logger.info("Server is not running.")
            return
        }
        if isLoggingEnabled { logger.info("Attempting to stop WebSocket server...") }
        state = .stopped // Set state first
        isRunning = false
        listener?.cancel()
        listener = nil
        // Make a copy of connections before iterating
        let currentConnections = connections
        connections.removeAll()
        currentConnections.values.forEach { connection in // <-- Iterate over dictionary values
            connection.cancel()
        }
        if isLoggingEnabled { logger.info("WebSocket server stopped.") }
    }

    private func accept(connection: NWConnection) {
        connections[connection.endpoint] = connection
        // state = .clientConnected(connection.endpoint) // Move state update after sending initial data
        
        connection.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            if self.isLoggingEnabled { self.logger.debug("Connection state changed to: \(String(describing: newState)) for \(String(describing: connection.endpoint))") }
            switch newState {
            case .ready:
                if self.isLoggingEnabled { self.logger.info("Client connected and ready: \(String(describing: connection.endpoint))") }
                // *** Send stored offer and candidates to the new client ***
                self.sendStoredState(to: connection)
                self.state = .clientConnected(connection.endpoint) // Update state AFTER sending initial info
                self.receiveMessage(connection: connection) // Start receiving messages
            case .failed(let error):
                if self.isLoggingEnabled { self.logger.error("Client connection failed: \(error.localizedDescription) for \(String(describing: connection.endpoint))") }
                self.connectionDidFail(connection: connection)
            case .cancelled:
                if self.isLoggingEnabled { self.logger.info("Client connection cancelled for \(String(describing: connection.endpoint))") }
                self.connectionDidEnd(connection: connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    // New method to send stored state to a specific connection
    private func sendStoredState(to connection: NWConnection) {
        stateAccessQueue.sync { // Access shared state safely
            // Send Offer if available
            if let offerSDP = lastOfferSDP {
                if isLoggingEnabled { logger.info("Sending stored Offer to new client \(String(describing: connection.endpoint))") }
                let offerMessage = SignalingMessage(type: .offer, sessionDescription: offerSDP, candidate: nil)
                 if let data = encodeMessage(offerMessage) {
                      sendData(data, to: connection)
                 }
            }
            
            // Send gathered Candidates if available
            if !gatheredCandidates.isEmpty {
                 if isLoggingEnabled { logger.info("Sending \(self.gatheredCandidates.count) stored Candidates to new client \(String(describing: connection.endpoint))") }
                 for candidatePayload in gatheredCandidates {
                     let candidateMessage = SignalingMessage(type: .candidate, sessionDescription: nil, candidate: candidatePayload)
                     if let data = encodeMessage(candidateMessage) {
                         sendData(data, to: connection)
                     }
                 }
            }
        }
    }
    
    // Helper to encode messages
    private func encodeMessage(_ message: SignalingMessage) -> Data? {
        let encoder = JSONEncoder()
        do {
            return try encoder.encode(message)
        } catch {
            if isLoggingEnabled { logger.error("Failed to encode message: \(error.localizedDescription)") }
            return nil
        }
    }

    private func receiveMessage(connection: NWConnection) {
        connection.receiveMessage { [weak self] (content, context, isComplete, error) in
            guard let self = self else { return }
            
            if let data = content, !data.isEmpty {
                // We received data, process it
                self.handleReceivedData(data, from: connection)
            }
            
            if let error = error {
                if self.isLoggingEnabled { self.logger.error("Receive error on connection \(String(describing: connection.endpoint)): \(error.localizedDescription)") }
                self.connectionDidFail(connection: connection)
                return // Don't schedule next receive if there was an error
            }
            
            if isComplete {
                // The remote endpoint closed the connection gracefully.
                // Note: In WebSocket, isComplete is often true for each message.
                // We rely on stateUpdateHandler for definitive closure.
                if self.isLoggingEnabled { self.logger.debug("Receive completed for connection \(String(describing: connection.endpoint))") }
            }

            // If the connection is still viable, schedule the next receive
            // Check connection state before scheduling next receive
            if connection.state == .ready {
                self.receiveMessage(connection: connection) // Continue receiving
            }
        }
    }
    
    private func handleReceivedData(_ data: Data, from connection: NWConnection) {
        let decoder = JSONDecoder()
        do {
            let message = try decoder.decode(SignalingMessage.self, from: data)
            if self.isLoggingEnabled { self.logger.info("Received message type: \(message.type.rawValue) from \(String(describing: connection.endpoint))") }
            
            DispatchQueue.main.async { // Call delegate on main thread
                switch message.type {
                case .answer:
                    if let sdp = message.sessionDescription {
                        self.delegate?.webSocketServer(self, didReceiveAnswer: sdp)
                    } else {
                        if self.isLoggingEnabled { self.logger.warning("Received answer message without SDP content from \(String(describing: connection.endpoint))") }
                    }
                case .candidate:
                    if let candidatePayload = message.candidate {
                        self.delegate?.webSocketServer(self, didReceiveCandidate: candidatePayload.sdp, sdpMid: candidatePayload.sdpMid, sdpMLineIndex: candidatePayload.sdpMLineIndex)
                    } else {
                        if self.isLoggingEnabled { self.logger.warning("Received candidate message without payload from \(String(describing: connection.endpoint))") }
                    }
                case .offer: 
                    // Usually, the server receives answer/candidate, but handle if needed
                    if self.isLoggingEnabled { self.logger.warning("Received offer message from client \(String(describing: connection.endpoint)). Server typically sends offers.") }
                     // Optionally, broadcast this offer to other clients if implementing multi-peer
                }
            }
        } catch {
            if self.isLoggingEnabled { self.logger.error("Failed to decode message from \(String(describing: connection.endpoint)): \(error.localizedDescription)") }
            // Optionally, send an error message back to the client
        }        
    }
    
    private func sendData(_ data: Data, to connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "context", metadata: [metadata])
        
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed({ [weak self] error in
            guard let self = self else { return }
            if let error = error {
                if self.isLoggingEnabled { self.logger.error("Send error to \(String(describing: connection.endpoint)): \(error.localizedDescription)") }
                // Handle error, maybe close connection
                self.connectionDidFail(connection: connection)
            } else {
                // self.logger.debug("Data sent successfully to \(connection.endpoint)")
            }
        }))
    }

    private func broadcastData(_ data: Data) {
        connections.values.forEach { connection in 
            if connection.state == .ready {
                sendData(data, to: connection)
            }
        }
    }

    func sendOffer(_ sdp: String) {
        // Store the offer before broadcasting
        stateAccessQueue.sync { 
            lastOfferSDP = sdp 
            // Clear old candidates when a new offer is sent?
            // gatheredCandidates.removeAll() // Decide if this is needed based on your flow
        }
        
        if isLoggingEnabled { logger.info("Broadcasting Offer SDP...") }
        let message = SignalingMessage(type: .offer, sessionDescription: sdp, candidate: nil)
        if let data = encodeMessage(message) {
            broadcastData(data) // Broadcast to existing connections
        }
    }

    func sendCandidate(_ candidateSdp: String, sdpMid: String?, sdpMLineIndex: Int32?) {
        guard let lineIndex = sdpMLineIndex else {
            if isLoggingEnabled { logger.warning("Cannot send candidate without sdpMLineIndex") }
            return
        }
        let payload = CandidatePayload(sdp: candidateSdp, sdpMLineIndex: lineIndex, sdpMid: sdpMid)
        
        // Store the candidate before broadcasting
        stateAccessQueue.sync { gatheredCandidates.append(payload) }
        
        if isLoggingEnabled { logger.info("Broadcasting ICE Candidate...") }
        let message = SignalingMessage(type: .candidate, sessionDescription: nil, candidate: payload)
        if let data = encodeMessage(message) {
            broadcastData(data) // Broadcast to existing connections
        }
    }

    private func connectionDidFail(connection: NWConnection) {
        if isLoggingEnabled { logger.warning("Connection failed or closed: \(String(describing: connection.endpoint))") }
        let endpoint = connection.endpoint // Capture before removing
        self.connections.removeValue(forKey: endpoint)
        state = .clientDisconnected(endpoint) // Update state
        connection.cancel()
    }

    private func connectionDidEnd(connection: NWConnection) {
        if isLoggingEnabled { logger.info("Connection ended: \(String(describing: connection.endpoint))") }
        let endpoint = connection.endpoint // Capture before removing
        self.connections.removeValue(forKey: endpoint)
        state = .clientDisconnected(endpoint) // Update state
    }
    
    // ... Delegate protocol remains the same ...

}

// ... Delegate protocol definition ...
protocol WebSocketSignalingServerDelegate: AnyObject {
    func webSocketServer(_ server: WebSocketSignalingServer, didChangeState newState: WebSocketServerState)
    func webSocketServer(_ server: WebSocketSignalingServer, didReceiveAnswer sdp: String)
    func webSocketServer(_ server: WebSocketSignalingServer, didReceiveCandidate candidate: String, sdpMid: String?, sdpMLineIndex: Int32?)
}

// Helper extension for state checking
extension WebSocketServerState {
    var isStoppedOrFailed: Bool {
        switch self {
        case .stopped, .failed: return true
        default: return false
        }
    }
} 
