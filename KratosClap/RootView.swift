import SwiftUI
import UIKit

/// Conteneur des deux modes : Clip (playback) et Cinéma.
/// On passe de l'un à l'autre en glissant depuis le bord de l'écran
/// (bord droit → Cinéma, bord gauche → Clip) ou en touchant le sélecteur en haut.
struct RootView: View {
    @EnvironmentObject private var engine: ClapEngine
    @AppStorage("modeCinema") private var cinemaMode = false
    @AppStorage("sessionVerrouillee") private var sessionLocked = false
    @GestureState private var dragOffset: CGFloat = 0

    private let edgeWidth: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: cinemaMode ? .leading : .trailing) {
                HStack(spacing: 0) {
                    ContentView()
                        .frame(width: width)
                    CinemaView()
                        .frame(width: width)
                }
                .frame(width: width, alignment: .leading)
                .offset(x: (cinemaMode ? -width : 0) + dragOffset)

                // Bande invisible le long du bord qui capte le glissement.
                // Absente quand la session est verrouillée : aucun changement de mode possible.
                // Liseré de la couleur de l'autre mode, sur le bord où l'on peut glisser :
                // vert à droite en mode Clip (vers Cinéma), rouge à gauche en mode Cinéma (vers Clip).
                if !sessionLocked {
                    EdgeHint(color: cinemaMode ? .red : .green)
                        .padding(.vertical, 90)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if !sessionLocked {
                    Color.clear
                        .frame(width: edgeWidth)
                        .padding(.bottom, 110) // laisse le bouton CLAP libre
                        .contentShape(Rectangle())
                        .gesture(edgeSwipe(width: width))
                }
            }
            .clipped()
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.86), value: cinemaMode)
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.86), value: dragOffset)
            .animation(.easeInOut(duration: 0.25), value: sessionLocked)
        }
        .onChange(of: cinemaMode) { _ in
            engine.stopSong()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }
    }

    private func edgeSwipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragOffset) { value, state, _ in
                // Clip : on ne tire que vers la gauche. Cinéma : que vers la droite.
                state = cinemaMode ? max(0, value.translation.width) : min(0, value.translation.width)
            }
            .onEnded { value in
                let moved = value.translation.width
                let predicted = value.predictedEndTranslation.width
                if !cinemaMode && (moved < -width * 0.3 || predicted < -width * 0.5) {
                    cinemaMode = true
                } else if cinemaMode && (moved > width * 0.3 || predicted > width * 0.5) {
                    cinemaMode = false
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
            label("CLIP", active: !cinemaMode) { cinemaMode = false }
                .opacity(sessionLocked && cinemaMode ? 0.35 : 1)
            label("CINÉMA", active: cinemaMode) { cinemaMode = true }
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

/// Liseré lumineux le long du bord de l'écran, qui indique qu'on peut glisser vers l'autre mode.
struct EdgeHint: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: [color.opacity(0), color, color, color.opacity(0)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 3)
            .shadow(color: color.opacity(0.8), radius: 6)
    }
}
