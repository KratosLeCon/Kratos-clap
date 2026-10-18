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


    var body: some View {
        NavigationStack {
            PageScroll {
                projectCard
                takeCard
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

    // MARK: - Projet (en haut, comme sur la page Clip)

    private var projectCard: some View {
        Card("Projet") {
            HStack(spacing: 12) {
                LabeledField(label: "PRODUCTION", placeholder: "Nom du projet", text: $production,
                                 focus: $focusedField, field: .production)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .director }
                FieldSeparator()
                VStack(alignment: .leading, spacing: 2) {
                    FieldLabel(text: "DATE")
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(.vertical, 6)
            }
            Divider()
            HStack(spacing: 12) {
                LabeledField(label: "RÉALISATEUR", placeholder: "Nom", text: $director,
                                 focus: $focusedField, field: .director)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .cameraOperator }
                FieldSeparator()
                LabeledField(label: "OPÉRATEUR", placeholder: "Nom", text: $cameraOperator,
                                 focus: $focusedField, field: .cameraOperator)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
            }
        }
    }

    // MARK: - Prise (même disposition que la page Clip)

    private var takeCard: some View {
        Card("Prise") {
            CameraPicker()
            Divider()
            HStack(spacing: 12) {
                LabeledField(label: "SCÈNE", placeholder: "—", text: $scene,
                                 focus: $focusedField, field: .scene,
                             centered: true, capitals: true)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                FieldSeparator()
                LabeledField(label: "PLAN", placeholder: "—", text: $plan,
                                 focus: $focusedField, field: .plan,
                             centered: true, capitals: true)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                FieldSeparator()
                CounterView(label: "PRISE", value: $take)
            }
            Divider()
            ClipNameRow()
        }
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
