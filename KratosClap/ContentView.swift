import SwiftUI
import UniformTypeIdentifiers

/// Page Clip : Projet → Prise → Playback → Sortie audio.
/// Même ordre et mêmes libellés que la page Cinéma.
/// La barre du haut et le bouton CLAP sont communs aux deux pages (RootView).
struct ContentView: View {
    @EnvironmentObject private var engine: ClapEngine
    @EnvironmentObject private var log: TakeLogStore
    @EnvironmentObject private var coordinator: ClapCoordinator

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
    @AppStorage("sessionVerrouillee") private var sessionLocked = false
    @AppStorage(ClipNaming.cameraKey) private var camera = "A"

    @State private var activeClap: ActiveClap?
    @State private var showImporter = false
    @FocusState private var focusedField: Field?

    private enum Field { case artist, title }

    private struct ActiveClap: Identifiable {
        let id = UUID()
        let config: ClapConfig
        let lead: Double
        let offsetMs: Double
        let beep: Bool
        let entry: TakeEntry
    }

    private var playbackReady: Bool { playbackMode && engine.songName != nil }

    var body: some View {
        NavigationStack {
            PageScroll {
                projectCard
                takeCard
                playbackCard
                audioCard
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField != nil {
                        Spacer()
                        Button("OK") { focusedField = nil }
                    }
                }
            }
        }
        .onChange(of: coordinator.clipRequest) { _ in startClap() }
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
                      onFinish: { result in
                          engine.stopSong()
                          log.record(clap.entry, result: result)
                          ClipNaming.advance()
                          activeClap = nil
                          take += 1
                      })
            .ignoresSafeArea()
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
        }
    }

    // MARK: - Projet

    private var projectCard: some View {
        Card("Projet") {
            HStack(spacing: 12) {
                LabeledField(label: "ARTISTE", placeholder: "Nom de l'artiste", text: $artist,
                                 focus: $focusedField, field: .artist)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .title }
                FieldSeparator()
                LabeledField(label: "TITRE", placeholder: "Titre du morceau", text: $songTitle,
                                 focus: $focusedField, field: .title)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
            }
        }
    }

    // MARK: - Prise

    private var takeCard: some View {
        Card("Prise") {
            CameraPicker()
            Divider()
            HStack(spacing: 12) {
                CounterView(label: "SÉQUENCE", value: $sequence)
                FieldSeparator()
                CounterView(label: "PRISE", value: $take)
            }
            Divider()
            ClipNameRow()
        }
    }

    // MARK: - Playback

    private var playbackCard: some View {
        Card("Playback") {
            Toggle("Mode playback", isOn: $playbackMode)
                .padding(.vertical, 6)
            if playbackMode {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
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
                    .controlSize(.small)
                }
                .padding(.vertical, 6)
                if engine.songName != nil {
                    Divider()
                    startPointControls
                }
            }
        }
    }

    private var startPointControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    FieldLabel(text: "DÉPART")
                    Text(Timecode.string(clampedStart, fps: fps))
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                }
                Slider(value: $songStart, in: 0...max(1, engine.songDuration))
            }
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
                .controlSize(.small)
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
        .padding(.vertical, 6)
    }

    private func nudgeButton(_ delta: Double) -> some View {
        Button(Self.deltaLabel(delta)) {
            songStart = min(max(0, songStart + delta), engine.songDuration)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Sortie audio

    private var audioCard: some View {
        Card("Sortie audio") {
            AudioStatusRow(fps: fps) {
                focusedField = nil
                coordinator.showSettings = true
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
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
        let clipName = ClipNaming.currentName()
        var lines = [
            artist.isEmpty ? "ARTISTE" : artist.uppercased(),
            songTitle.uppercased(),
            "SÉQ \(sequence)  ·  PR \(take)",
            clipName.isEmpty ? "CAM \(camera)" : "CAM \(camera)  ·  \(clipName)",
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
        var entry = TakeEntry(mode: "CLIP", production: artist, title: songTitle,
                              scene: "\(sequence)", take: take, camera: camera, fps: fps,
                              playbackStart: playbackStart)
        entry.clipName = clipName.isEmpty ? nil : clipName
        activeClap = ActiveClap(config: config, lead: leadTime, offsetMs: offsetMs,
                                beep: playbackStart == nil || beepInPlayback, entry: entry)
    }

    static func deltaLabel(_ delta: Double) -> String {
        delta > 0 ? "+\(Int(delta)) s" : "\(Int(delta)) s"
    }

    static func fpsLabel(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value)) i/s" : String(format: "%.3f i/s", value)
    }
}
