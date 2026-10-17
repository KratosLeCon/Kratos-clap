import AVFoundation
import Combine
import QuartzCore

/// Moteur audio du clap : session audio, bip programmé à l'heure près,
/// suivi de la sortie (haut-parleur, Bluetooth…) et étalonnages enregistrés par sortie.
final class ClapEngine: ObservableObject {
    @Published private(set) var routeName = "—"
    @Published private(set) var routeIsBluetooth = false
    @Published private(set) var calibratedLatencyMs: Double?
    @Published private(set) var systemLatencyMs: Double = 0
    @Published private(set) var isCalibrating = false
    @Published var statusMessage: String?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var beepBuffer: AVAudioPCMBuffer?
    private var routeKey = ""
    private var calibrations: [String: Double]
    private var observers: [NSObjectProtocol] = []
    private static let storageKey = "calibrationsParSortie"

    init() {
        calibrations = (UserDefaults.standard.dictionary(forKey: Self.storageKey) as? [String: Double]) ?? [:]
        configureSession()
        engine.attach(player)
        rebuildEngine()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.refreshRoute()
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                            object: engine, queue: .main) { [weak self] _ in
            guard let self = self, !self.isCalibrating else { return }
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
        var rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if rate <= 0 { rate = 48_000 }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
        engine.connect(player, to: engine.mainMixerNode, format: format)
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

    // MARK: - Clap

    /// S'assure que le moteur audio tourne avant un clap.
    func prepareForClap() {
        if !engine.isRunning { rebuildEngine() }
        if engine.isRunning && !player.isPlaying { player.play() }
    }

    /// Programme le bip pour qu'il sorte de l'enceinte exactement à `flashTime`,
    /// qui est l'instant d'un rafraîchissement d'écran (horloge CACurrentMediaTime).
    /// Le son est calé à l'échantillon près sur l'image, et non l'inverse.
    /// Renvoie false si l'instant demandé est trop proche pour être programmé.
    func scheduleBeep(audibleAt flashTime: CFTimeInterval, manualOffsetMs: Double) -> Bool {
        prepareForClap()
        guard let buffer = beepBuffer, engine.isRunning else { return false }
        let latencyMs = (calibratedLatencyMs ?? AVAudioSession.sharedInstance().outputLatency * 1000)
            + manualOffsetMs
        let startSeconds = flashTime - latencyMs / 1000
        guard startSeconds > CACurrentMediaTime() + 0.05 else { return false }
        player.scheduleBuffer(buffer,
                              at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: startSeconds)),
                              options: [], completionHandler: nil)
        return true
    }

    // MARK: - Étalonnage

    @MainActor
    func calibrate() async {
        guard !isCalibrating else { return }
        isCalibrating = true
        statusMessage = "Mesure en cours… silence sur le plateau."
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
