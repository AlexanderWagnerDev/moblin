import AVFoundation
import Foundation

protocol SrtStreamDelegate: AnyObject {
    func srtStreamConnected()
    func srtStreamDisconnected()
    func srtStreamOutput(packet: Data)
}

private enum ReadyState: UInt8 {
    case initialized
    case publishing
}

class SrtStream {
    private let writer: MpegTsWriter
    weak var srtStreamDelegate: SrtStreamDelegate?
    private let processor: Processor
    private var srtSender: SrtSender?

    init(processor: Processor, timecodesEnabled: Bool, delegate: SrtStreamDelegate) {
        self.processor = processor
        writer = MpegTsWriter(timecodesEnabled: timecodesEnabled)
        srtStreamDelegate = delegate
        writer.delegate = self
    }

    func open(streamId: String, latency: UInt16) {
        srtSender = SrtSender(streamId: streamId, latency: latency)
        srtSender?.delegate = self
        srtSender?.start()
    }

    func close() {
        srtSender?.stop()
        srtSender = nil
    }

    func inputPacket(packet: Data) {
        srtSender?.input(packet: packet)
    }

    func getPerformanceData() -> SrtPerformanceData? {
        return srtSender?.getPerformanceData()
    }

    private func write(data: Data) {
        data.withUnsafeBytes { buffer in
            write(buffer: buffer)
        }
    }

    private func write(buffer: UnsafeRawBufferPointer) {
        guard let srtSender else {
            return
        }
        let now = ContinuousClock.now
        for offset in stride(from: 0, to: buffer.count, by: payloadSize) {
            let length = min(payloadSize, buffer.count - offset)
            let payload = UnsafeRawBufferPointer(rebasing: buffer[offset ..< offset + length])
            let packet = srtSender.newDataPacket(payload: payload)
            srtSender.enqueue(packet: packet, now: now)
        }
        srtSender.send(now: now)
    }
}

extension SrtStream: MpegTsWriterDelegate {
    func writer(_: MpegTsWriter, doOutput data: Data) {
        srtlaClientQueue.async {
            self.write(data: data)
        }
    }
}

extension SrtStream: SrtSenderDelegate {
    func srtSenderConnected() {
        processorControlQueue.async {
            self.processor.startEncoding(self.writer)
            self.writer.startRunning()
            self.srtStreamDelegate?.srtStreamConnected()
        }
    }

    func srtSenderDisconnected() {
        processorControlQueue.async {
            self.writer.stopRunning()
            self.processor.stopEncoding(self.writer)
            self.srtStreamDelegate?.srtStreamDisconnected()
        }
    }

    func srtSenderOutput(packet: Data) {
        srtStreamDelegate?.srtStreamOutput(packet: packet)
    }
}
