import AVFoundation
import Foundation

class MirlStream {
    var client: MirlClient?
    private let mixer: Mixer

    init(mixer: Mixer) {
        self.mixer = mixer
        client = MirlClient()
    }

    func start() {
        netStreamLockQueue.async {
            self.client?.start()
            self.mixer.startEncoding(self)
            self.mixer.startRunning()
        }
    }

    func stop() {
        netStreamLockQueue.async {
            self.client?.stop()
            self.client = nil
            self.mixer.stopRunning()
            self.mixer.stopEncoding()
        }
    }
}

extension MirlStream: VideoEncoderDelegate {
    func videoEncoderOutputFormat(_: VideoEncoder, _ formatDescription: CMFormatDescription) {
        client?.writeVideoFormat(formatDescription: formatDescription)
    }

    func videoEncoderOutputSampleBuffer(_: VideoEncoder, _ sampleBuffer: CMSampleBuffer) {
        client?.writeVideo(sampleBuffer: sampleBuffer)
    }
}

extension MirlStream: AudioCodecDelegate {
    func audioCodecOutputFormat(_ audioFormat: AVAudioFormat) {
        client?.writeAudioFormat(audioFormat: audioFormat)
    }

    func audioCodecOutputBuffer(_ buffer: AVAudioBuffer, _ presentationTimeStamp: CMTime) {
        client?.writeAudio(buffer: buffer, presentationTimeStamp: presentationTimeStamp)
    }
}
