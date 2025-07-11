import Foundation
import Network

enum RtmpSocketReadyState {
    case uninitialized
    case versionSent
    case ackSent
    case handshakeDone
    case closed
}

protocol RtmpSocketDelegate: AnyObject {
    func socketDataReceived(_ socket: RtmpSocket, data: Data) -> Data
    func socketReadyStateChanged(_ socket: RtmpSocket, readyState: RtmpSocketReadyState)
    func socketUpdateStats(_ socket: RtmpSocket, totalBytesOut: Int64)
    func socketDispatch(_ socket: RtmpSocket, event: RtmpEvent)
}

final class RtmpSocket {
    var maximumChunkSizeFromServer = RtmpChunk.defaultSize
    var maximumChunkSizeToServer = RtmpChunk.defaultSize
    private var readyState: RtmpSocketReadyState = .uninitialized
    var secure = false {
        didSet {
            if secure {
                tlsOptions = .init()
            } else {
                tlsOptions = nil
            }
        }
    }

    private var inputBuffer = Data()
    weak var delegate: (any RtmpSocketDelegate)?
    private(set) var totalBytesIn: Atomic<Int64> = .init(0)
    private(set) var totalBytesOut: Atomic<Int64> = .init(0)
    private(set) var connected = false {
        didSet {
            if connected {
                write(data: handshake.createC0C1Packet())
                setReadyState(state: .versionSent)
            } else {
                setReadyState(state: .closed)
            }
        }
    }

    private var handshake = RtmpHandshake()
    private var connection: NWConnection? {
        didSet {
            oldValue?.viabilityUpdateHandler = nil
            oldValue?.stateUpdateHandler = nil
            oldValue?.forceCancel()
            if connection == nil {
                connected = false
            }
        }
    }

    private var tlsOptions: NWProtocolTLS.Options?
    private var timeoutHandler: DispatchWorkItem?

    func connect(host: String, port: Int) {
        handshake = RtmpHandshake()
        setReadyState(state: .uninitialized)
        maximumChunkSizeToServer = RtmpChunk.defaultSize
        maximumChunkSizeFromServer = RtmpChunk.defaultSize
        totalBytesIn.mutate { $0 = 0 }
        totalBytesOut.mutate { $0 = 0 }
        inputBuffer.removeAll(keepingCapacity: false)
        connection = NWConnection(
            to: .hostPort(host: .init(host), port: .init(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port))),
            using: .init(tls: tlsOptions)
        )
        if let connection {
            connection.viabilityUpdateHandler = viabilityDidChange
            connection.stateUpdateHandler = stateDidChange
            connection.start(queue: processorControlQueue)
            receive(on: connection)
        }
        timeoutHandler = DispatchWorkItem { [weak self] in
            guard let self, self.timeoutHandler?.isCancelled == false else {
                return
            }
            self.handleConnectTimeout()
        }
        processorControlQueue.asyncAfter(deadline: .now() + .seconds(10), execute: timeoutHandler!)
    }

    func close(isDisconnected: Bool = false) {
        if let connection {
            // To make sure all data (FCUnpublish, deleteStream and closeStream) has been written?
            connection.send(
                content: nil,
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed { _ in
                    self.connection = nil
                }
            )
        } else {
            connection = nil
        }
        if isDisconnected {
            let data: AsObject
            if readyState == .handshakeDone {
                data = RtmpConnectionCode.connectClosed.eventData()
            } else {
                data = RtmpConnectionCode.connectFailed.eventData()
            }
            delegate?.socketDispatch(self, event: RtmpEvent(type: .rtmpStatus, data: data))
        }
        timeoutHandler?.cancel()
    }

    func write(chunk: RtmpChunk) -> Int {
        for data in chunk.split(maximumSize: maximumChunkSizeToServer) {
            write(data: data)
        }
        return chunk.message!.length
    }

    private func setReadyState(state: RtmpSocketReadyState) {
        guard readyState != state else {
            return
        }
        logger.info("rtmp: Setting socket state \(readyState) -> \(state)")
        readyState = state
        delegate?.socketReadyStateChanged(self, readyState: readyState)
    }

    private func write(data: Data) {
        connection?.send(content: data, completion: .contentProcessed { error in
            guard self.connected else {
                return
            }
            if error != nil {
                self.close(isDisconnected: true)
                return
            }
            self.totalBytesOut.mutate { $0 += Int64(data.count) }
            self.delegate?.socketUpdateStats(self, totalBytesOut: self.totalBytesOut.value)
        })
    }

    private func viabilityDidChange(to viability: Bool) {
        logger.info("rtmp: Connection viability changed to \(viability)")
        if !viability {
            close(isDisconnected: true)
        }
    }

    private func stateDidChange(to state: NWConnection.State) {
        switch state {
        case .ready:
            logger.info("rtmp: Connection is ready.")
            timeoutHandler?.cancel()
            connected = true
        case let .waiting(error):
            logger.info("rtmp: Connection waiting: \(error)")
        case .setup:
            logger.debug("rtmp: Connection is setting up.")
        case .preparing:
            logger.debug("rtmp: Connection is preparing.")
        case let .failed(error):
            logger.info("rtmp: Connection failed: \(error)")
            close(isDisconnected: true)
        case .cancelled:
            logger.info("rtmp: Connection cancelled.")
            close(isDisconnected: true)
        @unknown default:
            logger.error("rtmp: Unknown connection state.")
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 0, maximumLength: 255) { [weak self] data, _, _, _ in
            guard let self, let data, self.connected else {
                return
            }
            self.inputBuffer.append(data)
            self.totalBytesIn.mutate { $0 += Int64(data.count) }
            self.processInput()
            self.receive(on: connection)
        }
    }

    private func processInput() {
        switch readyState {
        case .versionSent:
            processInputVersionSent()
        case .ackSent:
            processInputAckSent()
        case .handshakeDone:
            processInputHandshakeDone()
        default:
            break
        }
    }

    private func processInputVersionSent() {
        guard inputBuffer.count >= RtmpHandshake.sigSize + 1 else {
            return
        }
        write(data: handshake.createC2Packet(inputBuffer))
        inputBuffer.removeSubrange(0 ... RtmpHandshake.sigSize)
        setReadyState(state: .ackSent)
        processInput()
    }

    private func processInputAckSent() {
        guard inputBuffer.count >= RtmpHandshake.sigSize else {
            return
        }
        inputBuffer.removeAll()
        setReadyState(state: .handshakeDone)
    }

    private func processInputHandshakeDone() {
        guard !inputBuffer.isEmpty, let delegate else {
            return
        }
        inputBuffer = delegate.socketDataReceived(self, data: inputBuffer)
    }

    private func handleConnectTimeout() {
        logger.info("rtmp: Connect timeout")
        close(isDisconnected: true)
    }
}
