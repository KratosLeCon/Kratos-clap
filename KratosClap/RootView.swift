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

    private let edgeWidth: CGFloat = 24
    static let pageAnimation = Animation.spring(response: 0.35, dampingFraction: 0.9)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // Zone disponible au-dessus du bouton CLAP (~110 pt en bas)
            let availableHeight = max(100, geometry.size.height - 110)
            ZStack(alignment: cinemaMode ? .leading : .trailing) {
                HStack(spacing: 0) {
                    ContentView()
                        .frame(width: width)
                    CinemaView()
                        .frame(width: width)
                }
                // Marque-page fixé à la jonction des deux pages : il suit le glissement
                // avec les pages, sans animation propre. Sa couleur indique l'autre mode
                // et ne change qu'une fois le passage validé.
                .overlay(alignment: .center) {
                    if !sessionLocked {
                        PageBookmark(color: cinemaMode ? .red : .green,
                                     height: availableHeight * 0.7)
                            .offset(y: -55) // centré dans la zone au-dessus du bouton CLAP
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: width, alignment: .leading)
                .offset(x: (cinemaMode ? -width : 0) + dragOffset)

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
        .onChange(of: cinemaMode) { _ in
            engine.stopSong()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }
    }

    private func edgeSwipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Pendant le geste : les pages suivent le doigt, sans aucune animation.
                // Clip : on ne tire que vers la gauche. Cinéma : que vers la droite.
                let translation = value.translation.width
                dragOffset = cinemaMode ? max(0, translation) : min(0, translation)
            }
            .onEnded { value in
                let moved = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let switchMode = cinemaMode
                    ? (moved > width * 0.3 || predicted > width * 0.5)
                    : (moved < -width * 0.3 || predicted < -width * 0.5)
                // Une seule animation, qui part de la position actuelle du doigt :
                // changement de mode et retour du décalage à 0 dans la même transaction.
                withAnimation(Self.pageAnimation) {
                    if switchMode { cinemaMode.toggle() }
                    dragOffset = 0
                }
            }
    }
}

/// Sélecteur affiché en haut de chaque mode : « CLIP • CINÉMA ».
/// Désactivé quand la session est verrouillée (le mode inactif est alors estompé).
struct ModeSwitcher: View {
    @Binding var cinemaMode: Bool
    @AppStorage("sessionVerrouillee") private var sessionLocked = false

    var body: some View {
        HStack(spacing: 14) {
            label("CLIP", active: !cinemaMode) {
                withAnimation(RootView.pageAnimation) { cinemaMode = false }
            }
                .opacity(sessionLocked && cinemaMode ? 0.35 : 1)
            label("CINÉMA", active: cinemaMode) {
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
