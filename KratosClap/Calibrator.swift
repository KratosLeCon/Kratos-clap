import AVFoundation
import Accelerate

struct CalibrationResult {
    let latencyMs: Double
    let spreadMs: Double
    let valid: Int
    let total: Int
}

enum CalibrationError: LocalizedError {
    case micDenied
    case noSignal
    case engine(String)

    var errorDescription: String? {
        switch self {
        case .micDenied:
            return "Accès au micro refusé. Autorise-le dans Réglages > Kratos Clap."
        case .noSignal:
            return "Signal non détecté. Monte le volume, rapproche l'iPhone de l'enceinte et réessaie dans le calme."
        case .engine(let message):
            return "Erreur audio : \(message)"
        }
    }
}

/// Mesure la latence réelle de la sortie audio :
/// joue des chirps à des instants précis, les réécoute au micro de l'iPhone,
/// et retrouve leur arrivée par corrélation croisée.
final class Calibrator {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let lock = NSLock()
    private var recorded: [Float] = []
    private var firstSampleHost: UInt64?

    func run(chirpCount: Int = 7) async throws -> CalibrationResult {
        guard await Self.requestMicrophone() else { throw CalibrationError.micDenied }

        let session = AVAudioSession.sharedInstance()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw CalibrationError.engine("micro indisponible") }
        let inputRate = inputFormat.sampleRate

        var outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if outputRate <= 0 { outputRate = 48_000 }
        guard let playFormat = AVAudioFormat(standardFormatWithSampleRate: outputRate, channels: 1),
              let chirpBuffer = Signals.buffer(from: Signals.chirp(sampleRate: outputRate), format: playFormat)
        else { throw CalibrationError.engine("format audio") }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playFormat)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            self?.append(buffer, at: time)
        }
        engine.prepare()
        do { try engine.start() } catch { throw CalibrationError.engine(error.localizedDescription) }
        player.play()
        defer {
            input.removeTap(onBus: 0)
            player.stop()
            engine.stop()
        }

        try await Task.sleep(nanoseconds: 400_000_000)

        // Un chirp en plus au début : il sert à « réveiller » l'enceinte et n'est pas mesuré.
        let spacing = 0.8
        let firstAt = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.3)
        var scheduled: [UInt64] = []
        for i in 0..<(chirpCount + 1) {
            let host = firstAt + AVAudioTime.hostTime(forSeconds: spacing * Double(i))
            player.scheduleBuffer(chirpBuffer, at: AVAudioTime(hostTime: host),
                                  options: [], completionHandler: nil)
            scheduled.append(host)
        }
        let waitSeconds = 0.3 + spacing * Double(chirpCount + 1) + 0.8
        try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))

        lock.lock()
        let samples = recorded
        let firstHost = firstSampleHost
        lock.unlock()
        guard let recordingStartHost = firstHost else { throw CalibrationError.noSignal }

        let template = Signals.chirp(sampleRate: inputRate)
        let recordingStart = AVAudioTime.seconds(forHostTime: recordingStartHost)
        let inputLatency = session.inputLatency
        let searchWindow = Int(0.7 * inputRate) // latence maximale détectable : ~700 ms

        var delaysMs: [Double] = []
        for host in scheduled.dropFirst() {
            let sentAt = AVAudioTime.seconds(forHostTime: host)
            let startIndex = Int((sentAt - recordingStart) * inputRate)
            guard startIndex >= 0, startIndex + searchWindow + template.count <= samples.count else { continue }
            guard let (offset, sharpness) = Self.correlate(samples, from: startIndex,
                                                           length: searchWindow, template: template),
                  sharpness > 5 else { continue }
            let heardAt = recordingStart + Double(startIndex + offset) / inputRate - inputLatency
            delaysMs.append((heardAt - sentAt) * 1000)
        }

        guard delaysMs.count >= 3 else { throw CalibrationError.noSignal }
        delaysMs.sort()
        return CalibrationResult(latencyMs: delaysMs[delaysMs.count / 2],
                                 spreadMs: delaysMs.last! - delaysMs.first!,
                                 valid: delaysMs.count,
                                 total: chirpCount)
    }

    private func append(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        lock.lock()
        if firstSampleHost == nil && time.isHostTimeValid { firstSampleHost = time.hostTime }
        if firstSampleHost != nil {
            recorded.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
        }
        lock.unlock()
    }

    /// Corrélation croisée (vDSP) : renvoie la position du pic et sa netteté (pic / moyenne).
    static func correlate(_ signal: [Float], from start: Int, length: Int,
                          template: [Float]) -> (Int, Float)? {
        var result = [Float](repeating: 0, count: length)
        signal.withUnsafeBufferPointer { signalPointer in
            template.withUnsafeBufferPointer { templatePointer in
                vDSP_conv(signalPointer.baseAddress! + start, 1,
                          templatePointer.baseAddress!, 1,
                          &result, 1,
                          vDSP_Length(length), vDSP_Length(template.count))
            }
        }
        let magnitudes = result.map { abs($0) }
        var peak: Float = 0
        var peakIndex: vDSP_Length = 0
        vDSP_maxvi(magnitudes, 1, &peak, &peakIndex, vDSP_Length(length))
        var mean: Float = 0
        vDSP_meamgv(result, 1, &mean, vDSP_Length(length))
        guard mean > 0 else { return nil }
        return (Int(peakIndex), peak / mean)
    }

    static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
