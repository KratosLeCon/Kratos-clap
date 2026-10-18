import SwiftUI
import UIKit

/// Liaison entre la partie fixe (barre du haut, bouton CLAP) et le contenu des pages.
final class ClapCoordinator: ObservableObject {
    @Published var clipRequest = 0      // incrémenté = lancer un clap en mode Clip
    @Published var cinemaRequest = 0    // incrémenté = lancer un clap en mode Cinéma
    @Published var showSettings = false
    @Published var showJournal = false
}

/// Conteneur des deux modes : Clip (playback) et Cinéma.
/// La barre du haut et le bouton CLAP sont fixes ; seul le contenu des pages glisse.
/// On passe de l'un à l'autre en glissant depuis le bord de l'écran
/// (bord droit → Cinéma, bord gauche → Clip) ou en touchant le sélecteur en haut.
struct RootView: View {
    @EnvironmentObject private var engine: ClapEngine
    @StateObject private var coordinator = ClapCoordinator()
    @AppStorage("modeCinema") private var cinemaMode = false
    @AppStorage("sessionVerrouillee") private var sessionLocked = false
    @AppStorage("modePlayback") private var playbackMode = false
    // Page affichée, en @State : un changement de @AppStorage n'est pas animé par
    // withAnimation (il arrive par une notification, hors de la transaction), ce qui
    // faisait sauter la page et donnait l'impression qu'elle arrivait du mauvais côté.
    // On anime donc cette copie locale, puis on enregistre le mode dans @AppStorage.
    @State private var pageCinema = UserDefaults.standard.bool(forKey: "modeCinema")
    // @State et non @GestureState : un @GestureState revient à 0 sans animation au lâcher.
    @State private var dragOffset: CGFloat = 0

    // Marque-page : estompé dès que la page bouge, réaffiché avec la nouvelle couleur
    // une fois le changement de page terminé.
    @State private var bookmarkVisible = true
    @State private var bookmarkForCinema = false
    @State private var transitionID = 0

    // Protection contre les changements de page trop rapides ou accidentels
    @State private var dragStart: Date?
    @State private var gestureBlocked = false
    @GestureState private var gestureActive = false   // repasse à false même si iOS annule le geste
    private static let minimumDistance: CGFloat = 0.4   // 40 % de la largeur
    private static let minimumDuration: Double = 0.3    // geste d'au moins 0,3 s
    private static let cooldown: Double = 0.35          // pause après un changement

    private let edgeWidth: CGFloat = 24

    /// Passage de page : courbe douce (départ progressif, arrivée très amortie), sans rebond.
    static let pageDuration: Double = 0.55
    static let pageAnimation = Animation.timingCurve(0.45, 0, 0.15, 1, duration: pageDuration)

    private static let clipRed = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1)
    private static let cinemaGreen = UIColor(red: 0.2, green: 0.74, blue: 0.35, alpha: 1)

    private var clipButtonLabel: String {
        playbackMode && engine.songName != nil ? "CLAP + PLAYBACK" : "CLAP"
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let position = (pageCinema ? -width : 0) + dragOffset
            // 0 = page Clip affichée, 1 = page Cinéma affichée
            let progress = min(1, max(0, -position / max(1, width)))

            // Les pages occupent tout l'écran ; la barre du haut et le bouton CLAP
            // flottent par-dessus, sans fond, pour un ensemble d'un seul tenant.
            ZStack {
                pages(width: width, position: position, progress: progress)
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    clapButton(progress: progress)
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .environmentObject(coordinator)
        .sheet(isPresented: $coordinator.showSettings) {
            SettingsView().environmentObject(engine)
        }
        .sheet(isPresented: $coordinator.showJournal) {
            JournalView()
        }
        .onAppear {
            pageCinema = cinemaMode
            bookmarkForCinema = cinemaMode
        }
        .onChange(of: gestureActive) { active in
            // Geste annulé par iOS (appel, notification…) sans passer par onEnded :
            // on remet tout en place pour que le glissement reste utilisable.
            guard !active, dragStart != nil else { return }
            dragStart = nil
            gestureBlocked = false
            withAnimation(Self.pageAnimation) { dragOffset = 0 }
            showBookmarkAfterTransition(for: pageCinema)
        }
        // Changement demandé par le sélecteur CLIP · CINÉMA : on anime la page
        .onChange(of: cinemaMode) { newMode in
            guard newMode != pageCinema else { return }
            withAnimation(Self.pageAnimation) { pageCinema = newMode }
        }
        // Toute arrivée sur une nouvelle page, quel que soit le déclencheur
        .onChange(of: pageCinema) { newMode in
            if cinemaMode != newMode { cinemaMode = newMode }
            // Aucun nouveau changement possible avant la fin du passage + une courte pause
            PageTurnGate.occupy(Self.pageDuration + Self.cooldown)
            engine.stopSong()
            dismissKeyboard()
            hideBookmark()
            showBookmarkAfterTransition(for: newMode)
        }
    }

    // MARK: - Barre du haut (fixe)

    private var topBar: some View {
        HStack(spacing: 18) {
            Button {
                dismissKeyboard()
                coordinator.showJournal = true
            } label: {
                Image(systemName: "list.bullet.rectangle")
            }
            Spacer()
            ModeSwitcher(cinemaMode: $cinemaMode)
            Spacer()
            SessionLockButton()
            Button {
                dismissKeyboard()
                coordinator.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
        .font(.title3)
        .padding(.horizontal, 20)
        .frame(height: 48)
    }

    // MARK: - Pages (seule partie qui glisse)

    private func pages(width: CGFloat, position: CGFloat, progress: CGFloat) -> some View {
        GeometryReader { area in
            ZStack(alignment: pageCinema ? .leading : .trailing) {
                HStack(spacing: 0) {
                    // La page qui s'en va s'estompe, la nouvelle apparaît
                    ContentView()
                        .frame(width: width)
                        .opacity(1 - 0.85 * progress)
                    CinemaView()
                        .frame(width: width)
                        .opacity(0.15 + 0.85 * progress)
                }
                // Marque-page fixé à la jonction des deux pages : 70 % de la hauteur
                // disponible entre la barre du haut et le bouton CLAP, centré dans cette zone.
                .overlay(alignment: .center) {
                    if !sessionLocked {
                        let usable = max(100, area.size.height - PageLayout.topInset - PageLayout.bottomInset)
                        PageBookmark(color: bookmarkForCinema ? .red : .green,
                                     height: usable * 0.7)
                            .offset(y: (PageLayout.topInset - PageLayout.bottomInset) / 2)
                            .opacity(bookmarkVisible ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: width, alignment: .leading)
                .offset(x: position)

                // Bande invisible le long du bord qui capte le glissement.
                // Absente quand la session est verrouillée : aucun changement de mode possible.
                if !sessionLocked {
                    Color.clear
                        .frame(width: edgeWidth)
                        .padding(.top, PageLayout.topInset)
                        .padding(.bottom, PageLayout.bottomInset)
                        .contentShape(Rectangle())
                        .gesture(edgeSwipe(width: width))
                }
            }
            .frame(width: width, height: area.size.height)
            .clipped()
        }
    }

    // MARK: - Bouton CLAP (fixe)

    /// Se teinte progressivement du rouge (Clip) au vert (Cinéma) pendant le glissement,
    /// et son texte passe en fondu de celui de la page de départ à celui de la page d'arrivée.
    private func clapButton(progress: CGFloat) -> some View {
        let tint = Color(uiColor: Self.blend(Self.clipRed, Self.cinemaGreen, progress))
        return Button {
            guard !PageTurnGate.isBusy, dragOffset == 0 else { return }
            if pageCinema {
                coordinator.cinemaRequest += 1
            } else {
                coordinator.clipRequest += 1
            }
        } label: {
            ZStack {
                Text(clipButtonLabel)
                    .font(.system(size: clipButtonLabel == "CLAP" ? 34 : 26, weight: .black))
                    .opacity(1 - progress)
                Text("CLAP")
                    .font(.system(size: 34, weight: .black))
                    .opacity(progress)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            // Forme en gélule, comme le bouton d'origine
            .background(tint, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .disabled(engine.isCalibrating)
        .opacity(engine.isCalibrating ? 0.5 : 1)
    }

    private static func blend(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: 1)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    // MARK: - Geste

    private func edgeSwipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($gestureActive) { _, state, _ in state = true }
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.time
                    // Geste commencé pendant un passage de page : ignoré en entier
                    gestureBlocked = PageTurnGate.isBusy
                }
                guard !gestureBlocked else { return }
                if bookmarkVisible { hideBookmark() }
                // Pendant le geste : les pages suivent le doigt, sans aucune animation.
                // Clip : on ne tire que vers la gauche. Cinéma : que vers la droite.
                let translation = value.translation.width
                dragOffset = pageCinema ? max(0, translation) : min(0, translation)
            }
            .onEnded { value in
                let started = dragStart ?? value.time
                dragStart = nil
                if gestureBlocked {
                    gestureBlocked = false
                    return
                }
                // Seul un geste délibéré tourne la page : assez long (40 % de la largeur)
                // ET assez lent (au moins 0,3 s). L'élan du doigt n'est pas pris en compte.
                let moved = value.translation.width
                let duration = value.time.timeIntervalSince(started)
                let farEnough = pageCinema
                    ? moved > width * Self.minimumDistance
                    : moved < -width * Self.minimumDistance
                let switchMode = farEnough && duration >= Self.minimumDuration
                // Une seule animation, qui part de la position actuelle du doigt :
                // changement de page et retour du décalage à 0 dans la même transaction.
                withAnimation(Self.pageAnimation) {
                    if switchMode { pageCinema.toggle() }
                    dragOffset = 0
                }
                // Geste annulé : le marque-page revient une fois la page remise en place
                if !switchMode { showBookmarkAfterTransition(for: pageCinema) }
            }
    }

    private func hideBookmark() {
        transitionID += 1   // annule un réaffichage en attente
        withAnimation(.easeOut(duration: 0.15)) { bookmarkVisible = false }
    }

    private func showBookmarkAfterTransition(for mode: Bool) {
        transitionID += 1
        let id = transitionID
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pageDuration) {
            guard id == transitionID else { return }
            bookmarkForCinema = mode   // la couleur change pendant qu'il est invisible
            withAnimation(.easeIn(duration: 0.25)) { bookmarkVisible = true }
        }
    }
}

/// Verrou temporaire partagé : bloque tout changement de page pendant un passage
/// et la courte pause qui suit (geste sur le bord comme sélecteur du haut).
enum PageTurnGate {
    private static var busyUntil = Date.distantPast
    static var isBusy: Bool { Date() < busyUntil }
    static func occupy(_ seconds: Double) { busyUntil = Date().addingTimeInterval(seconds) }
}

/// Sélecteur affiché en haut de chaque mode : « CLIP • CINÉMA ».
/// Désactivé quand la session est verrouillée (le mode inactif est alors estompé).
struct ModeSwitcher: View {
    @Binding var cinemaMode: Bool
    @AppStorage("sessionVerrouillee") private var sessionLocked = false

    var body: some View {
        HStack(spacing: 14) {
            label("CLIP", active: !cinemaMode) {
                guard !PageTurnGate.isBusy else { return }
                withAnimation(RootView.pageAnimation) { cinemaMode = false }
            }
                .opacity(sessionLocked && cinemaMode ? 0.35 : 1)
            label("CINÉMA", active: cinemaMode) {
                guard !PageTurnGate.isBusy else { return }
                withAnimation(RootView.pageAnimation) { cinemaMode = true }
            }
                .opacity(sessionLocked && !cinemaMode ? 0.35 : 1)
        }
        .disabled(sessionLocked)
        .animation(.easeInOut(duration: 0.2), value: sessionLocked)
    }

    private func label(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(text)
                    .font(.subheadline.weight(active ? .heavy : .medium))
                    .foregroundStyle(active ? Color.primary : Color.secondary)
                Capsule()
                    .fill(active ? (text == "CLIP" ? Color.red : Color.green) : Color.clear)
                    .frame(width: 22, height: 3)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Ligne d'état de la sortie audio, raccourci vers les réglages.
struct AudioStatusRow: View {
    @EnvironmentObject private var engine: ClapEngine
    let fps: Double
    let action: () -> Void

    private var needsCalibration: Bool {
        engine.routeIsBluetooth && engine.calibratedLatencyMs == nil
    }

    private var detail: String {
        if let calibrated = engine.calibratedLatencyMs {
            return String(format: "Latence étalonnée : %.0f ms", calibrated)
        }
        if engine.routeIsBluetooth {
            return "Bluetooth non étalonné : touche pour étalonner"
        }
        return String(format: "Latence estimée : %.0f ms", engine.systemLatencyMs)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: needsCalibration ? "exclamationmark.triangle.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(needsCalibration ? Color.orange : Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ContentView.fpsLabel(fps))  ·  \(engine.routeName)")
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Verrou de session, à côté de l'engrenage.
/// Fermé : l'app reste dans le mode en cours (le premier clap le ferme automatiquement).
/// Ouvert : changement de mode possible. Pas de message, juste l'icône.
struct SessionLockButton: View {
    @AppStorage("sessionVerrouillee") private var sessionLocked = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            sessionLocked.toggle()
        } label: {
            Image(systemName: sessionLocked ? "lock.fill" : "lock.open")
                .frame(width: 24)
        }
    }
}

/// Marque-page entre les deux pages : languette pleine, sans halo.
/// Centrée sur la jonction, seule la moitié dépasse au bord de l'écran.
struct PageBookmark: View {
    let color: Color
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: 12, height: height)
            // Pas d'animation de couleur : elle bascule d'un coup quand le mode change.
            .animation(nil, value: color)
    }
}
