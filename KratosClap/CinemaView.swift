import SwiftUI

/// Mode cinéma : clap lumineux + bip, sans playback, avec un slate complet
/// (production, caméra, scène, plan, prise, réalisateur, opérateur, date).
/// Après le logo, le timecode défile (heure du jour ou depuis le clap) jusqu'à STOP.
struct CinemaView: View {
    @EnvironmentObject private var engine: ClapEngine
    @EnvironmentObject private var log: TakeLogStore
    @EnvironmentObject private var coordinator: ClapCoordinator

    // Réglages partagés avec le mode Clip
    @AppStorage("fps") private var fps: Double = 25
    @AppStorage("framesBlanches") private var whiteFrames: Double = 2
    @AppStorage("framesLogo") private var logoFrames: Double = 1.5
    @AppStorage("decalageMs") private var offsetMs: Double = 0
    @AppStorage("dureeSlate") private var leadTime: Double = 2
    @AppStorage("modeCinema") private var cinemaMode = false
    @AppStorage("sessionVerrouillee") private var sessionLocked = false
    @AppStorage("cineTimecode") private var cinemaTimecode = 0

    // Slate cinéma
    @AppStorage("cineProduction") private var production = ""
    @AppStorage("cineCamera") private var camera = "A"
    @AppStorage("cineScene") private var scene = "1"
    @AppStorage("cinePlan") private var plan = "1"
    @AppStorage("cinePrise") private var take = 1
    @AppStorage("cineRealisateur") private var director = ""
    @AppStorage("cineOperateur") private var cameraOperator = ""
    @State private var date = Date()

    @State private var activeClap: ActiveClap?
    @FocusState private var focusedField: Field?

    private enum Field { case production, director, cameraOperator, scene, plan }

    private struct ActiveClap: Identifiable {
        let id = UUID()
        let config: ClapConfig
        let lead: Double
        let offsetMs: Double
        let entry: TakeEntry
    }

    private let cameras = ["A", "B", "C", "D"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    Picker("Caméra", selection: $camera) {
                        ForEach(cameras, id: \.self) { Text("CAM \($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        slateField("SCÈNE", text: $scene, field: .scene)
                        Divider()
                        slateField("PLAN", text: $plan, field: .plan)
                        Divider()
                        CounterView(label: "PRISE", value: $take)
                    }
                    ClipNameRow(showCameraPicker: false)
                }

                Section("Projet") {
                    TextField("Production / projet", text: $production)
                        .focused($focusedField, equals: .production)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .director }
                    TextField("Réalisateur", text: $director)
                        .focused($focusedField, equals: .director)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .cameraOperator }
                    TextField("Opérateur caméra", text: $cameraOperator)
                        .focused($focusedField, equals: .cameraOperator)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section {
                    AudioStatusRow(fps: fps) {
                        focusedField = nil
                        coordinator.showSettings = true
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // Barre du haut et bouton CLAP sont communs aux deux pages (RootView)
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
        .onChange(of: coordinator.cinemaRequest) { _ in startClap() }
        // Nouvelle scène ou nouveau plan : la prise repart à 1
        .onChange(of: scene) { _ in take = 1 }
        .onChange(of: plan) { _ in take = 1 }
        .fullScreenCover(item: $activeClap) { clap in
            FlashView(config: clap.config, lead: clap.lead,
                      scheduleSound: { flashTime in
                          engine.scheduleBeep(audibleAt: flashTime, manualOffsetMs: clap.offsetMs)
                      },
                      onFinish: { result in
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

    private func slateField(_ label: String, text: Binding<String>, field: Field) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            TextField("—", text: text)
                .focused($focusedField, equals: field)
                .multilineTextAlignment(.center)
                .font(.title3.weight(.bold))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
        }
        .frame(maxWidth: .infinity)
    }

    private func startClap() {
        focusedField = nil
        sessionLocked = true   // le premier clap verrouille la session dans ce mode
        engine.stopSong()
        let clipName = ClipNaming.currentName()
        let lines = [
            production.isEmpty ? "PRODUCTION" : production.uppercased(),
            "SC \(scene.uppercased())  ·  PL \(plan.uppercased())  ·  PR \(take)",
            clipName.isEmpty ? "CAM \(camera)" : "CAM \(camera)  ·  \(clipName)",
            director.isEmpty ? "" : "RÉAL. \(director.uppercased())",
            cameraOperator.isEmpty ? "" : "OPÉ. \(cameraOperator.uppercased())",
            "\(date.formatted(date: .numeric, time: .omitted))  ·  \(ContentView.fpsLabel(fps))"
        ]
        let config = ClapConfig(fps: fps, whiteFrames: whiteFrames, logoFrames: logoFrames,
                                slateLines: lines.filter { !$0.isEmpty },
                                playbackStart: nil,
                                songDuration: 0,
                                timecodeMode: cinemaTimecode == 0 ? .timeOfDay : .sinceFlash)
        engine.prepareForClap()
        var entry = TakeEntry(mode: "CINÉMA", production: production,
                              scene: scene.uppercased(), shot: plan.uppercased(), take: take,
                              camera: camera, director: director, cameraOperator: cameraOperator,
                              fps: fps)
        entry.clipName = clipName.isEmpty ? nil : clipName
        activeClap = ActiveClap(config: config, lead: leadTime, offsetMs: offsetMs, entry: entry)
    }
}
