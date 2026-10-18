import AVFoundation
import Combine
import QuartzCore

/// Moteur audio de l'app : session audio, bip programmé à l'heure près,
/// lecture du morceau (playback), suivi de la sortie (haut-parleur, Bluetooth…)
/// et étalonnages enregistrés par sortie.
final class ClapEngine: ObservableObject {
    @Published private(set) var routeName = "—"
    @Published private(set) var routeIsBluetooth = false
    @Published private(set) var calibratedLatencyMs: Double?
    @Published private(set) var systemLatencyMs: Double = 0
    @Published private(set) var isCalibrating = false
    @Published var statusMessage: String?

    // Playback
    @Published private(set) var songName: String?
    @Published private(set) var songDuration: Double = 0
    @Published private(set) var isPreviewing = false

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()      // bip
    private let songPlayer = AVAudioPlayerNode()  // morceau
    private var beepBuffer: AVAudioPCMBuffer?
    private var songFile: AVAudioFile?
    private var previewStart: Double = 0
    private var routeKey = ""
    private var calibrations: [String: Double]
    private var observers: [NSObjectProtocol] = []
    private static let storageKey = "calibrationsParSortie"

    init() {
        calibrations = (UserDefaults.standard.dictionary(forKey: Self.storageKey) as? [String: Double]) ?? [:]
        configureSession()
        engine.attach(player)
        engine.attach(songPlayer)
        rebuildEngine()
        restoreSong()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.refreshRoute()
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                            object: engine, queue: .main) { [weak self] _ in
            guard let self = self, !self.isCalibrating else { return }
            self.isPreviewing = false
            self.rebuildEngine()
        })
        refreshRoute()
    }

    // MARK: - Session audio

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .allowBluetoothA2DP SANS .allowBluetooth : l'enceinte reste en qualité normale (A2DP)
            // et le micro utilisé est celui de l'iPhone. Avec .allowBluetooth, iOS basculerait
            // l'enceinte en mode « kit mains libres » (HFP) et la mesure serait fausse.
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.allowBluetoothA2DP, .defaultToSpeaker])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            statusMessage = "Session audio : \(error.localizedDescription)"
        }
    }

    private func rebuildEngine() {
        engine.stop()
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(songPlayer)
        var rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if rate <= 0 { rate = 48_000 }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        // Le mixeur convertit au besoin la fréquence du morceau (44,1 kHz → 48 kHz…)
        engine.connect(songPlayer, to: engine.mainMixerNode,
                       format: songFile?.processingFormat ?? format)
        beepBuffer = Signals.beep(format: format)
        do {
            engine.prepare()
            try engine.start()
            player.play()
        } catch {
            statusMessage = "Moteur audio : \(error.localizedDescription)"
        }
    }

    // MARK: - Sortie audio

    func refreshRoute() {
        let session = AVAudioSession.sharedInstance()
        let output = session.currentRoute.outputs.first
        let bluetoothPorts: [AVAudioSession.Port] = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP]
        routeName = output?.portName ?? "Aucune sortie"
        routeIsBluetooth = output.map { bluetoothPorts.contains($0.portType) } ?? false
        routeKey = "\(output?.portType.rawValue ?? "?")|\(routeName)"
        calibratedLatencyMs = calibrations[routeKey]
        systemLatencyMs = session.outputLatency * 1000
    }

    /// Délai entre « son programmé » et « son entendu », décalage manuel compris.
    private func latencySeconds(manualOffsetMs: Double) -> Double {
        let ms = (calibratedLatencyMs ?? AVAudioSession.sharedInstance().outputLatency * 1000)
            + manualOffsetMs
        return ms / 1000
    }

    // MARK: - Clap

    /// S'assure que le moteur audio tourne avant un clap.
    func prepareForClap() {
        if !engine.isRunning { rebuildEngine() }
        if engine.isRunning && !player.isPlaying { player.play() }
    }

    /// Programme le bip pour qu'il sorte de l'enceinte exactement à `flashTime`,
    /// qui est l'instant d'un rafraîchissement d'écran (horloge CACurrentMediaTime).
    /// Renvoie false si l'instant demandé est trop proche pour être programmé.
    func scheduleBeep(audibleAt flashTime: CFTimeInterval, manualOffsetMs: Double) -> Bool {
        prepareForClap()
        guard let buffer = beepBuffer, engine.isRunning else { return false }
        let startSeconds = flashTime - latencySeconds(manualOffsetMs: manualOffsetMs)
        guard startSeconds > CACurrentMediaTime() + 0.05 else { return false }
        player.scheduleBuffer(buffer,
                              at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: startSeconds)),
                              options: [], completionHandler: nil)
        return true
    }

    // MARK: - Playback

    /// Programme le morceau pour que la position `position` soit entendue exactement à `flashTime`.
    /// Le flash (1re frame blanche) correspond donc pile à cette position du morceau.
    func scheduleSong(from position: Double, audibleAt flashTime: CFTimeInterval,
                      manualOffsetMs: Double, withBeep: Bool) -> Bool {
        prepareForClap()
        guard let file = songFile, engine.isRunning else { return false }
        let startSeconds = flashTime - latencySeconds(manualOffsetMs: manualOffsetMs)
        guard startSeconds > CACurrentMediaTime() + 0.05 else { return false }

        let rate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(max(0, position) * rate)
        guard startFrame < file.length else { return false }
        let when = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: startSeconds))

        songPlayer.stop()
        isPreviewing = false
        songPlayer.scheduleSegment(file, startingFrame: startFrame,
                                   frameCount: AVAudioFrameCount(file.length - startFrame),
                                   at: when, completionHandler: nil)
        songPlayer.play()
        if withBeep, let buffer = beepBuffer {
            player.scheduleBuffer(buffer, at: when, options: [], completionHandler: nil)
        }
        return true
    }

    func stopSong() {
        songPlayer.stop()
        isPreviewing = false
    }

    /// Pré-écoute immédiate depuis une position, pour trouver le point de départ.
    func previewSong(from position: Double) {
        prepareForClap()
        guard let file = songFile, engine.isRunning else { return }
        let rate = file.processingFormat.sampleRate
        let start = min(max(0, position), songDuration)
        let startFrame = AVAudioFramePosition(start * rate)
        guard startFrame < file.length else { return }
        songPlayer.stop()
        songPlayer.scheduleSegment(file, startingFrame: startFrame,
                                   frameCount: AVAudioFrameCount(file.length - startFrame),
                                   at: nil, completionHandler: nil)
        songPlayer.play()
        previewStart = start
        isPreviewing = true
    }

    /// Position actuellement ENTENDUE pendant la pré-écoute (latence de sortie déduite).
    func previewPosition() -> Double? {
        guard isPreviewing,
              let nodeTime = songPlayer.lastRenderTime,
              let playerTime = songPlayer.playerTime(forNodeTime: nodeTime) else { return nil }
        let rendered = previewStart + Double(playerTime.sampleTime) / playerTime.sampleRate
        return max(0, min(songDuration, rendered - latencySeconds(manualOffsetMs: 0)))
    }

    // MARK: - Import du morceau

    func importSong(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let manager = FileManager.default
            let folder = try Self.songFolder()
            let existing = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in existing { try? manager.removeItem(at: file) }
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            try manager.copyItem(at: url, to: destination)
            try loadSong(at: destination)
            statusMessage = "Morceau importé : \(url.lastPathComponent)"
        } catch {
            statusMessage = "Import impossible : \(error.localizedDescription)"
        }
    }

    private static func songFolder() throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        let folder = documents.appendingPathComponent("Playback", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func loadSong(at url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        songPlayer.stop()
        isPreviewing = false
        songFile = file
        songName = url.deletingPathExtension().lastPathComponent
        songDuration = Double(file.length) / file.processingFormat.sampleRate
        rebuildEngine()
    }

    /// Recharge au démarrage le dernier morceau importé.
    private func restoreSong() {
        guard let folder = try? Self.songFolder(),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil),
              let first = files.first else { return }
        try? loadSong(at: first)
    }

    // MARK: - Étalonnage

    @MainActor
    func calibrate() async {
        guard !isCalibrating else { return }
        isCalibrating = true
        statusMessage = "Mesure en cours… silence sur le plateau."
        stopSong()
        engine.stop()
        do {
            let result = try await Calibrator().run()
            calibrations[routeKey] = result.latencyMs
            UserDefaults.standard.set(calibrations, forKey: Self.storageKey)
            statusMessage = String(format: "Étalonné : %.0f ms (écart entre mesures : %.0f ms, %d/%d valides)",
                                   result.latencyMs, result.spreadMs, result.valid, result.total)
        } catch {
            statusMessage = error.localizedDescription
        }
        isCalibrating = false
        rebuildEngine()
        refreshRoute()
    }

    func resetCalibration() {
        calibrations[routeKey] = nil
        UserDefaults.standard.set(calibrations, forKey: Self.storageKey)
        statusMessage = "Étalonnage effacé pour cette sortie."
        refreshRoute()
    }
}
