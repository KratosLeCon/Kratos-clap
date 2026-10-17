import AVFoundation

/// Génération des sons : le bip du clap et le chirp d'étalonnage.
enum Signals {

    /// Bip de 80 ms à 1 kHz, attaque franche (pic net sur la forme d'onde), fin adoucie.
    static func beep(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let count = Int(rate * 0.08)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(count)
        let fade = Int(rate * 0.005)
        for i in 0..<count {
            var amplitude: Float = 0.9
            let remaining = count - i
            if remaining < fade { amplitude *= Float(remaining) / Float(fade) }
            channel[i] = amplitude * sinf(2 * Float.pi * 1000 * Float(i) / Float(rate))
        }
        return buffer
    }

    /// Balayage de fréquence (chirp) de 100 ms, de 1 kHz à 6 kHz.
    /// Facile à retrouver dans un enregistrement bruité par corrélation croisée.
    static func chirp(sampleRate: Double, duration: Double = 0.1,
                      f0: Double = 1000, f1: Double = 6000) -> [Float] {
        let count = Int(sampleRate * duration)
        let sweep = (f1 - f0) / duration
        let fade = Int(sampleRate * 0.003)
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            var amplitude = 0.8
            if i < fade { amplitude *= Double(i) / Double(fade) }
            if count - i < fade { amplitude *= Double(count - i) / Double(fade) }
            samples[i] = Float(amplitude * sin(2 * Double.pi * (f0 * t + 0.5 * sweep * t * t)))
        }
        return samples
    }

    static func buffer(from samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for i in 0..<samples.count { channel[i] = samples[i] }
        return buffer
    }
}
