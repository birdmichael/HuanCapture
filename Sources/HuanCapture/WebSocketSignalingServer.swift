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

class WebSocketSignalingServer: SignalingServerProtocol {

    private let port: NWEndpoint.Port
    weak var delegate: SignalingServerDelegate?
    weak var internalStateDelegate: WebSocketSignalingServerStateDelegate?
    private var listener: NWListener?
    private var connections: [NWEndpoint: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.huancapture.websocket.server.queue")
    private let logger = PrintLog()
    private var isRunning = false
    private let isLoggingEnabled: Bool
    private var state: WebSocketServerState = .idle {
        didSet {
            DispatchQueue.main.async {
                 self.internalStateDelegate?.webSocketServer(self, didChangeState: self.state)
            }
        }
    }

    private var lastOfferSDP: String? = nil
    private var gatheredCandidates: [CandidatePayload] = []
    private let stateAccessQueue = DispatchQueue(label: "com.huancapture.websocket.server.state.queue")

    init(port: UInt16, isLoggingEnabled: Bool) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.isLoggingEnabled = isLoggingEnabled
        if isLoggingEnabled { logger.info("WebSocketSignalingServer initialized for port \(String(port)). Network.framework will be used.") }
        self.state = .idle
    }

    deinit {
        stop()
    }

    // MARK: - SignalingServerProtocol Conformance

    func start() {
        stateAccessQueue.sync {
            lastOfferSDP = nil
            gatheredCandidates.removeAll()
        }
        switch state {
            case .idle, .stopped, .failed:
                break
            default:
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
                 self.listener?.cancel()
                 self.connections.forEach { $0.value.cancel() }
                 self.connections.removeAll()
                 self.isRunning = false
            case .cancelled:
                 if self.isLoggingEnabled { self.logger.info("WebSocket server listener cancelled.") }
                 self.state = .stopped
                 self.isRunning = false
            default:
                if self.isLoggingEnabled { self.logger.debug("Listener state changed: \(String(describing: newState))") }
            }
        }

        listener?.newConnectionHandler = { [weak self] newConnection in
            guard let self = self else { return }
            if self.isLoggingEnabled { self.logger.info("New client connection received from: \(String(describing: newConnection.endpoint))") }
            self.accept(connection: newConnection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        stateAccessQueue.sync {
            lastOfferSDP = nil
            gatheredCandidates.removeAll()
        }
        guard isRunning else {
            return
        }
        if isLoggingEnabled { logger.info("Attempting to stop WebSocket server...") }
        state = .stopped
        isRunning = false
        listener?.cancel()
        listener = nil
        let currentConnections = connections
        connections.removeAll()
        currentConnections.values.forEach { connection in
            connection.cancel()
        }
        if isLoggingEnabled { logger.info("WebSocket server stopped.") }
    }

    func sendOffer(sdp: String) {
        stateAccessQueue.sync {
            lastOfferSDP = sdp
        }

        if isLoggingEnabled { logger.info("Broadcasting Offer SDP...") }
        let message = SignalingMessage(type: .offer, sessionDescription: sdp, candidate: nil)
        if let data = encodeMessage(message) {
            broadcastData(data)
        }
    }

    func sendCandidate(sdp: String, sdpMid: String?, sdpMLineIndex: Int32?) {
         guard let lineIndex = sdpMLineIndex else {
            if isLoggingEnabled { logger.warning("Cannot send candidate without sdpMLineIndex") }
            return
        }
        let payload = CandidatePayload(sdp: sdp, sdpMLineIndex: lineIndex, sdpMid: sdpMid)

        stateAccessQueue.sync { gatheredCandidates.append(payload) }

        if isLoggingEnabled { logger.info("Broadcasting ICE Candidate...") }
        let message = SignalingMessage(type: .candidate, sessionDescription: nil, candidate: payload)
        if let data = encodeMessage(message) {
            broadcastData(data)
        }
    }

    // MARK: - Private Helpers

    private func accept(connection: NWConnection) {
        connections[connection.endpoint] = connection

        connection.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            if self.isLoggingEnabled { self.logger.debug("Connection state changed to: \(String(describing: newState)) for \(String(describing: connection.endpoint))") }
            switch newState {
            case .ready:
                if self.isLoggingEnabled { self.logger.info("Client connected and ready: \(String(describing: connection.endpoint))") }
                self.sendStoredState(to: connection)
                self.state = .clientConnected(connection.endpoint)
                self.receiveMessage(connection: connection)
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

    private func sendStoredState(to connection: NWConnection) {
        stateAccessQueue.sync {
            if let offerSDP = lastOfferSDP {
                if isLoggingEnabled { logger.info("Sending stored Offer to new client \(String(describing: connection.endpoint))") }
                let offerMessage = SignalingMessage(type: .offer, sessionDescription: offerSDP, candidate: nil)
                 if let data = encodeMessage(offerMessage) {
                      sendData(data, to: connection)
                 }
            }

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
                self.handleReceivedData(data, from: connection)
            }

            if let error = error {
                if self.isLoggingEnabled { self.logger.error("Receive error on connection \(String(describing: connection.endpoint)): \(error.localizedDescription)") }
                self.connectionDidFail(connection: connection)
                return
            }

            if isComplete {
                if self.isLoggingEnabled { self.logger.debug("Receive completed for connection \(String(describing: connection.endpoint))") }
            }

            if connection.state == .ready {
                self.receiveMessage(connection: connection)
            }
        }
    }

    private func handleReceivedData(_ data: Data, from connection: NWConnection) {
        let decoder = JSONDecoder()
        do {
            let message = try decoder.decode(SignalingMessage.self, from: data)
            if self.isLoggingEnabled { self.logger.info("Received message type: \(message.type.rawValue) from \(String(describing: connection.endpoint))") }

            // Use the generic SignalingServerDelegate
            DispatchQueue.main.async {
                switch message.type {
                case .answer:
                    if let sdp = message.sessionDescription {
                        // Use the generic delegate method
                        self.delegate?.signalingServer(didReceiveAnswer: sdp)
                    } else {
                        if self.isLoggingEnabled { self.logger.warning("Received answer message without SDP content from \(String(describing: connection.endpoint))") }
                    }
                case .candidate:
                    if let candidatePayload = message.candidate {
                         // Use the generic delegate method
                        self.delegate?.signalingServer(didReceiveCandidate: candidatePayload.sdp, sdpMid: candidatePayload.sdpMid, sdpMLineIndex: candidatePayload.sdpMLineIndex)
                    } else {
                        if self.isLoggingEnabled { self.logger.warning("Received candidate message without payload from \(String(describing: connection.endpoint))") }
                    }
                case .offer:
                    if self.isLoggingEnabled { self.logger.warning("Received offer message from client \(String(describing: connection.endpoint)). Server typically sends offers.") }
                }
            }
        } catch {
            if self.isLoggingEnabled { self.logger.error("Failed to decode message from \(String(describing: connection.endpoint)): \(error.localizedDescription)") }
        }
    }

    private func sendData(_ data: Data, to connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "context", metadata: [metadata])

        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed({ [weak self] error in
            guard let self = self else { return }
            if let error = error {
                if self.isLoggingEnabled { self.logger.error("Send error to \(String(describing: connection.endpoint)): \(error.localizedDescription)") }
                self.connectionDidFail(connection: connection)
            } else {
                // Successfully sent
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

    private func connectionDidFail(connection: NWConnection) {
        if isLoggingEnabled { logger.warning("Connection failed or closed: \(String(describing: connection.endpoint))") }
        let endpoint = connection.endpoint
        self.connections.removeValue(forKey: endpoint)
        state = .clientDisconnected(endpoint)
        connection.cancel()
    }

    private func connectionDidEnd(connection: NWConnection) {
        if isLoggingEnabled { logger.info("Connection ended: \(String(describing: connection.endpoint))") }
        let endpoint = connection.endpoint
        self.connections.removeValue(forKey: endpoint)
        state = .clientDisconnected(endpoint)
    }
}

// New delegate protocol specifically for WebSocket state changes
protocol WebSocketSignalingServerStateDelegate: AnyObject {
    func webSocketServer(_ server: WebSocketSignalingServer, didChangeState newState: WebSocketServerState)
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
