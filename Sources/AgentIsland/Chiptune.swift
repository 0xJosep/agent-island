import AVFoundation

final class Chiptune {
    static let shared = Chiptune()

    static let victory: [(Double, Double)] = [
        (523.25, 0.07), (659.25, 0.07), (783.99, 0.07), (1046.50, 0.18),
    ]
    static let attention: [(Double, Double)] = [
        (659.25, 0.09), (0, 0.05), (880.00, 0.16),
    ]
    static let alarm: [(Double, Double)] = [
        (440.00, 0.08), (0, 0.04), (440.00, 0.08), (0, 0.04), (587.33, 0.16),
    ]

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = Float(Settings.shared.soundVolume)
        try? engine.start()
    }

    func play(_ notes: [(Double, Double)], amplitude: Float = 0.14) {
        guard Settings.shared.soundsEnabled else { return }
        engine.mainMixerNode.outputVolume = Float(Settings.shared.soundVolume)
        if !engine.isRunning {
            try? engine.start()
        }
        guard engine.isRunning else { return }

        let sampleRate = format.sampleRate
        let totalDuration = notes.reduce(0) { $0 + $1.1 }
        let frameCount = AVAudioFrameCount(totalDuration * sampleRate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let samples = buffer.floatChannelData![0]
        var index = 0
        for (freq, duration) in notes {
            let frames = Int(duration * sampleRate)
            for i in 0..<frames where index < Int(frameCount) {
                if freq <= 0 {
                    samples[index] = 0
                } else {
                    let t = Double(i) / sampleRate
                    let phase = (t * freq).truncatingRemainder(dividingBy: 1)
                    let square: Float = phase < 0.5 ? 1 : -1
                    let envelope = Float(exp(-2.5 * t / duration))
                    samples[index] = square * amplitude * envelope
                }
                index += 1
            }
        }

        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying {
            player.play()
        }
    }
}
