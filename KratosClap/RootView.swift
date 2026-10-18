import SwiftUI
import UIKit

/// Conteneur des deux modes : Clip (playback) et Cinéma.
/// On passe de l'un à l'autre en glissant depuis le bord de l'écran
/// (bord droit → Cinéma, bord gauche → Clip) ou en touchant le sélecteur en haut.
struct RootView: View {
    @EnvironmentObject private var engine: ClapEngine
    @AppStorage("modeCinema") private var cinemaMode = false
    @AppStorage("sessionVerrouillee") private var sessionLocked = false
    // @State et non @GestureState : un @GestureState revient à 0 sans animation au lâcher,
    // ce qui faisait « sauter » les pages (et le marque-page) avant l'animation de fin.
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

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // Zone disponible au-dessus du bouton CLAP (~110 pt en bas)
            let availableHeight = max(100, geometry.size.height - 110)
            let position = (cinemaMode ? -width : 0) + dragOffset
            // 0 = page Clip affichée, 1 = page Cinéma affichée
            let progress = min(1, max(0, -position / max(1, width)))

            ZStack(alignment: cinemaMode ? .leading : .trailing) {
                HStack(spacing: 0) {
                    // La page qui s'en va s'estompe, la nouvelle apparaît
                    ContentView()
                        .frame(width: width)
                        .opacity(1 - 0.85 * progress)
                    CinemaView()
                        .frame(width: width)
                        .opacity(0.15 + 0.85 * progress)
                }
                // Marque-page fixé à la jonction des deux pages
                .overlay(alignment: .center) {
                    if !sessionLocked {
                        PageBookmark(color: bookmarkForCinema ? .red : .green,
                                     height: availableHeight * 0.7)
                            .offset(y: -55) // centré dans la zone au-dessus du bouton CLAP
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
                        .padding(.bottom, 110) // laisse le bouton CLAP libre
                        .contentShape(Rectangle())
                        .gesture(edgeSwipe(width: width))
                }
            }
            .clipped()
        }
        .onAppear { bookmarkForCinema = cinemaMode }
        .onChange(of: gestureActive) { active in
            // Geste annulé par iOS (appel, notification…) sans passer par onEnded :
            // on remet tout en place pour que le glissement reste utilisable.
            guard !active, dragStart != nil else { return }
            dragStart = nil
            gestureBlocked = false
            withAnimation(Self.pageAnimation) { dragOffset = 0 }
            showBookmarkAfterTransition(for: cinemaMode)
        }
        .onChange(of: cinemaMode) { newMode in
            // Aucun nouveau changement possible avant la fin du passage + une courte pause
            PageTurnGate.occupy(Self.pageDuration + Self.cooldown)
            engine.stopSong()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
            hideBookmark()
            showBookmarkAfterTransition(for: newMode)
        }
    }

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
                dragOffset = cinemaMode ? max(0, translation) : min(0, translation)
            }
            .onEnded { value in
                let started = dragStart ?? value.time
                dragStart = nil
                if gestureBlocked {
                    gestureBlocked = false
                    return
                }
                // Seul un geste délibéré tourne la page : assez long (40 % de la largeur)
                // ET assez lent (au moins 0,3 s). Un coup rapide sur le bord, même ample,
                // ramène la page en place. L'élan du doigt n'est plus pris en compte.
                let moved = value.translation.width
                let duration = value.time.timeIntervalSince(started)
                let farEnough = cinemaMode
                    ? moved > width * Self.minimumDistance
                    : moved < -width * Self.minimumDistance
                let switchMode = farEnough && duration >= Self.minimumDuration
                // Une seule animation, qui part de la position actuelle du doigt :
                // changement de mode et retour du décalage à 0 dans la même transaction.
                withAnimation(Self.pageAnimation) {
                    if switchMode { cinemaMode.toggle() }
                    dragOffset = 0
                }
                // Geste annulé : le marque-page revient avec sa couleur une fois la page remise en place
                if !switchMode { showBookmarkAfterTransition(for: cinemaMode) }
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
