import SwiftUI
import UniformTypeIdentifiers

/// Écran principal, réduit à l'essentiel du tournage :
/// slate, playback, état de la sortie audio et bouton CLAP.
/// Les réglages techniques sont dans SettingsView (engrenage en haut à droite).
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
    @AppStorage("modePlayback") private var playbackMode = false
    @AppStorage("debutMorceau") private var songStart: Double = 0
    @AppStorage("bipPlayback") private var beepInPlayback = true
    @AppStorage("modeCinema") private var cinemaMode = false
    @AppStorage("sessionVerrouillee") private var sessionLocked = false

    @State private var activeClap: ActiveClap?
    @State private var showImporter = false
    @State private var showSettings = false
    @FocusState private var focusedField: Field?

    private enum Field { case artist, title }

    private struct ActiveClap: Identifiable {
        let id = UUID()
        let config: ClapConfig
        let lead: Double
        let offsetMs: Double
        let beep: Bool
    }

    private var playbackReady: Bool { playbackMode && engine.songName != nil }

    var body: some View {
        NavigationStack {
            Form {
                slateSection
                playbackSection
                statusSection
            }
            // Le clavier se ferme quand on fait défiler la page
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Kratos Clap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ModeSwitcher(cinemaMode: $cinemaMode)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    SessionLockButton()
                    Button {
                        focusedField = nil
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                // Bouton « OK » au-dessus du clavier
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField != nil {
                        Spacer()
                        Button("OK") { focusedField = nil }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: startClap) {
                    Text(playbackReady ? "CLAP + PLAYBACK" : "CLAP")
                        .font(.system(size: playbackReady ? 26 : 34, weight: .black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .disabled(engine.isCalibrating)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(engine)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result {
                engine.importSong(from: url)
                songStart = 0
            }
        }
        .fullScreenCover(item: $activeClap) { clap in
            FlashView(config: clap.config, lead: clap.lead,
                      scheduleSound: { flashTime in
                          if let position = clap.config.playbackStart {
                              return engine.scheduleSong(from: position, audibleAt: flashTime,
                                                         manualOffsetMs: clap.offsetMs,
                                                         withBeep: clap.beep)
                          }
                          return engine.scheduleBeep(audibleAt: flashTime, manualOffsetMs: clap.offsetMs)
                      },
                      onFinish: {
                          engine.stopSong()
                          activeClap = nil
                          take += 1
                      })
            .ignoresSafeArea()
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
        }
    }

    // MARK: - Slate

    private var slateSection: some View {
        Section("Slate") {
            TextField("Artiste", text: $artist)
                .focused($focusedField, equals: .artist)
                .submitLabel(.next)
                .onSubmit { focusedField = .title }
            TextField("Titre du morceau", text: $songTitle)
                .focused($focusedField, equals: .title)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
            HStack(spacing: 12) {
                CounterView(label: "SÉQ", value: $sequence)
                Divider()
                CounterView(label: "PRISE", value: $take)
            }
        }
    }

    // MARK: - Playback

    private var playbackSection: some View {
        Section("Playback") {
            Toggle("Mode playback", isOn: $playbackMode)
            if playbackMode {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(engine.songName ?? "Aucun morceau")
                            .lineLimit(1)
                        if engine.songName != nil {
                            Text(Timecode.short(engine.songDuration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(engine.songName == nil ? "Importer" : "Changer") {
                        focusedField = nil
                        showImporter = true
                    }
                    .buttonStyle(.bordered)
                }
                if engine.songName != nil {
                    startPointControls
                }
            }
        }
    }

    private var startPointControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Départ")
                Spacer()
                Text(Timecode.string(clampedStart, fps: fps))
                    .font(.system(.body, design: .monospaced))
            }
            Slider(value: $songStart, in: 0...max(1, engine.songDuration))
            HStack {
                nudgeButton(-5)
                nudgeButton(-1)
                Spacer()
                Button {
                    if engine.isPreviewing {
                        engine.stopSong()
                    } else {
                        engine.previewSong(from: clampedStart)
                    }
                } label: {
                    Image(systemName: engine.isPreviewing ? "stop.fill" : "play.fill")
                        .frame(width: 28)
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                nudgeButton(1)
                nudgeButton(5)
            }
            if engine.isPreviewing {
                HStack {
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        Text("Écoute : " + Timecode.short(engine.previewPosition() ?? 0))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Départ ici") {
                        if let position = engine.previewPosition() { songStart = position }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func nudgeButton(_ delta: Double) -> some View {
        Button(Self.deltaLabel(delta)) {
            songStart = min(max(0, songStart + delta), engine.songDuration)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - État de la sortie (raccourci vers les réglages)

    private var statusSection: some View {
        Section {
            AudioStatusRow(fps: fps) {
                focusedField = nil
                showSettings = true
            }
        }
    }

    // MARK: - Logique

    private var clampedStart: Double {
        min(max(0, songStart), max(0, engine.songDuration - 0.5))
    }

    private func startClap() {
        focusedField = nil
        sessionLocked = true   // le premier clap verrouille la session dans ce mode
        engine.stopSong()
        let playbackStart: Double? = playbackReady ? clampedStart : nil
        var lines = [
            artist.isEmpty ? "ARTISTE" : artist.uppercased(),
            songTitle.uppercased(),
            "SÉQ \(sequence) — PRISE \(take)",
            Self.fpsLabel(fps)
        ]
        if let position = playbackStart {
            lines.append("PLAYBACK \(Timecode.string(position, fps: fps))")
        }
        let config = ClapConfig(fps: fps, whiteFrames: whiteFrames, logoFrames: logoFrames,
                                slateLines: lines.filter { !$0.isEmpty },
                                playbackStart: playbackStart,
                                songDuration: engine.songDuration)
        engine.prepareForClap()
        activeClap = ActiveClap(config: config, lead: leadTime, offsetMs: offsetMs,
                                beep: playbackStart == nil || beepInPlayback)
    }

    static func deltaLabel(_ delta: Double) -> String {
        delta > 0 ? "+\(Int(delta)) s" : "\(Int(delta)) s"
    }

    static func fpsLabel(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value)) i/s" : String(format: "%.3f i/s", value)
    }
}

/// Compteur compact − valeur + (séquence, prise).
struct CounterView: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Button {
                if value > 1 { value -= 1 }
            } label: {
                Image(systemName: "minus.circle.fill").font(.title2)
            }
            Text("\(value)")
                .font(.title3.monospacedDigit().weight(.bold))
                .frame(minWidth: 34)
            Button {
                if value < 999 { value += 1 }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title2)
            }
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity)
    }
}
