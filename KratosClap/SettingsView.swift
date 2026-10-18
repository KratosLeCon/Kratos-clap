import SwiftUI

/// Page des réglages techniques, ouverte par l'engrenage :
/// cadence caméra, latence et étalonnage, durées du clap, options du playback.
struct SettingsView: View {
    @EnvironmentObject private var engine: ClapEngine
    @Environment(\.dismiss) private var dismiss

    @AppStorage("fps") private var fps: Double = 25
    @AppStorage("framesBlanches") private var whiteFrames: Double = 2
    @AppStorage("framesLogo") private var logoFrames: Double = 1.5
    @AppStorage("decalageMs") private var offsetMs: Double = 0
    @AppStorage("dureeSlate") private var leadTime: Double = 2
    @AppStorage("bipPlayback") private var beepInPlayback = true
    @AppStorage("cineTimecode") private var cinemaTimecode = 0

    private let fpsOptions: [Double] = [23.976, 24, 25, 29.97, 30, 50, 60]

    var body: some View {
        NavigationStack {
            Form {
                Section("Caméra") {
                    Picker("Cadence", selection: $fps) {
                        ForEach(fpsOptions, id: \.self) { value in
                            Text(ContentView.fpsLabel(value)).tag(value)
                        }
                    }
                }

                Section {
                    LabeledContent("Sortie",
                                   value: engine.routeName + (engine.routeIsBluetooth ? " (Bluetooth)" : ""))
                    LabeledContent("Latence utilisée", value: latencyText)
                    Button {
                        Task { await engine.calibrate() }
                    } label: {
                        HStack {
                            Text(engine.isCalibrating ? "Mesure en cours…" : "Étalonner cette sortie")
                            if engine.isCalibrating {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(engine.isCalibrating)
                    if engine.calibratedLatencyMs != nil {
                        Button("Effacer l'étalonnage", role: .destructive) { engine.resetCalibration() }
                    }
                    VStack(alignment: .leading) {
                        Text(String(format: "Décalage manuel : %+.0f ms", offsetMs))
                        Slider(value: $offsetMs, in: -100...100, step: 1)
                    }
                    if let message = engine.statusMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Audio et latence")
                } footer: {
                    Text("Étalonne depuis la place de l'artiste, volume du plateau, dans le calme. Réétalonne à chaque nouvelle enceinte ou reconnexion. Décalage positif = flash plus tard.")
                }

                Section {
                    Stepper(String(format: "Frames blanches avant le logo : %.0f", whiteFrames),
                            value: $whiteFrames, in: 1...6, step: 1)
                    Stepper(String(format: "Durée du logo : %.1f frame(s)", logoFrames),
                            value: $logoFrames, in: 0.5...4, step: 0.5)
                    Stepper(String(format: "Affichage du slate : %.1f s", leadTime),
                            value: $leadTime, in: 1...5, step: 0.5)
                } header: {
                    Text("Clap")
                } footer: {
                    Text("Le logo apparaît en noir juste après les frames blanches (2 → logo sur la 3e). Le point de synchro est la première frame blanche.")
                }

                Section("Playback") {
                    Toggle("Bip au départ du playback", isOn: $beepInPlayback)
                }

                Section {
                    Picker("Timecode affiché", selection: $cinemaTimecode) {
                        Text("Heure du jour").tag(0)
                        Text("Depuis le clap").tag(1)
                    }
                } header: {
                    Text("Mode cinéma")
                } footer: {
                    Text("Heure du jour : à utiliser avec la caméra réglée en timecode « Time of Day », horloge calée sur celle de l'iPhone. Depuis le clap : 00:00:00:00 sur la première frame blanche.")
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private var latencyText: String {
        if let calibrated = engine.calibratedLatencyMs {
            return String(format: "%.0f ms (étalonnée)", calibrated)
        }
        return String(format: "%.0f ms (estimation iOS)", engine.systemLatencyMs)
    }
}
