import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: ClapEngine

    @AppStorage("fps") private var fps: Double = 25
    @AppStorage("framesBlanches") private var whiteFrames: Double = 2
    @AppStorage("framesLogo") private var logoFrames: Double = 1.5
    @AppStorage("decalageMs") private var offsetMs: Double = 0
    @AppStorage("dureeSlate") private var leadTime: Double = 2
    @AppStorage("artiste") private var artist = ""
    @AppStorage("titre") private var songTitle = ""
    @AppStorage("sequence") private var sequence = 1
    @AppStorage("prise") private var take = 1

    @State private var activeClap: ActiveClap?

    private struct ActiveClap: Identifiable {
        let id = UUID()
        let config: ClapConfig
        let lead: Double
        let offsetMs: Double
    }

    private let fpsOptions: [Double] = [23.976, 24, 25, 29.97, 30, 50, 60]

    var body: some View {
        NavigationStack {
            Form {
                Section("Slate") {
                    TextField("Artiste", text: $artist)
                    TextField("Titre du morceau", text: $songTitle)
                    Stepper("Séquence \(sequence)", value: $sequence, in: 1...999)
                    Stepper("Prise \(take)", value: $take, in: 1...999)
                }

                Section {
                    Picker("Cadence caméra", selection: $fps) {
                        ForEach(fpsOptions, id: \.self) { value in
                            Text(Self.fpsLabel(value)).tag(value)
                        }
                    }
                    Stepper(String(format: "Frames blanches avant le logo : %.0f", whiteFrames),
                            value: $whiteFrames, in: 1...6, step: 1)
                    Stepper(String(format: "Durée du logo : %.1f frame(s)", logoFrames),
                            value: $logoFrames, in: 0.5...4, step: 0.5)
                    Stepper(String(format: "Affichage du slate : %.1f s", leadTime),
                            value: $leadTime, in: 1...5, step: 0.5)
                } header: {
                    Text("Image")
                } footer: {
                    Text("Le logo apparaît en noir juste après les frames blanches (2 → logo sur la 3e). Le point de synchro est la première frame blanche.")
                }

                Section {
                    LabeledContent("Sortie", value: engine.routeName + (engine.routeIsBluetooth ? " (Bluetooth)" : ""))
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
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Audio")
                } footer: {
                    Text("Étalonne depuis la place de l'artiste, volume du plateau, dans le calme. Réétalonne à chaque nouvelle enceinte ou reconnexion.")
                }
            }
            .navigationTitle("Kratos Clap")
            .safeAreaInset(edge: .bottom) {
                Button(action: startClap) {
                    Text("CLAP")
                        .font(.system(size: 34, weight: .black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding()
                .disabled(engine.isCalibrating)
            }
        }
        .fullScreenCover(item: $activeClap) { clap in
            FlashView(config: clap.config, lead: clap.lead,
                      scheduleSound: { flashTime in
                          engine.scheduleBeep(audibleAt: flashTime, manualOffsetMs: clap.offsetMs)
                      },
                      onFinish: {
                          activeClap = nil
                          take += 1
                      })
            .ignoresSafeArea()
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
        }
    }

    private var latencyText: String {
        if let calibrated = engine.calibratedLatencyMs {
            return String(format: "%.0f ms (étalonnée)", calibrated)
        }
        return String(format: "%.0f ms (estimation iOS)", engine.systemLatencyMs)
    }

    private func startClap() {
        let lines = [
            artist.isEmpty ? "ARTISTE" : artist.uppercased(),
            songTitle.uppercased(),
            "SÉQ \(sequence) — PRISE \(take)",
            Self.fpsLabel(fps)
        ].filter { !$0.isEmpty }
        let config = ClapConfig(fps: fps, whiteFrames: whiteFrames,
                                logoFrames: logoFrames, slateLines: lines)
        engine.prepareForClap()
        activeClap = ActiveClap(config: config, lead: leadTime, offsetMs: offsetMs)
    }

    static func fpsLabel(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value)) i/s" : String(format: "%.3f i/s", value)
    }
}
