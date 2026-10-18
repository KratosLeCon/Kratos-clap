import SwiftUI

/// Mode cinéma : clap lumineux + bip, sans playback, avec un slate complet
/// (production, caméra, scène, plan, prise, réalisateur, opérateur, date).
/// Après le logo, le timecode défile (heure du jour ou depuis le clap) jusqu'à STOP.
struct CinemaView: View {
    @EnvironmentObject private var engine: ClapEngine

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
    @State private var showSettings = false
    @FocusState private var focusedField: Field?

    private enum Field { case production, director, cameraOperator, scene, plan }

    private struct ActiveClap: Identifiable {
        let id = UUID()
        let config: ClapConfig
        let lead: Double
        let offsetMs: Double
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
                        showSettings = true
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Kratos Cinéma")
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
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField != nil {
                        Spacer()
                        Button("OK") { focusedField = nil }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: startClap) {
                    Text("CLAP")
                        .font(.system(size: 34, weight: .black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .disabled(engine.isCalibrating)
            }
        }
        // Nouvelle scène ou nouveau plan : la prise repart à 1
        .onChange(of: scene) { _ in take = 1 }
        .onChange(of: plan) { _ in take = 1 }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(engine)
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
        let lines = [
            production.isEmpty ? "PRODUCTION" : production.uppercased(),
            "SC \(scene.uppercased())  ·  PL \(plan.uppercased())  ·  PR \(take)",
            "CAM \(camera)",
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
        activeClap = ActiveClap(config: config, lead: leadTime, offsetMs: offsetMs)
    }
}
