import SwiftUI
import UIKit

struct ClapConfig {
    var fps: Double
    var whiteFrames: Double       // frames blanches avant le logo (2 → logo sur la 3e)
    var logoFrames: Double        // durée du logo, en frames caméra
    var slateLines: [String]
    var playbackStart: Double?    // position du morceau au flash (nil = pas de playback)
    var songDuration: Double = 0
    var timecodeMode: TimecodeMode = .none  // timecode affiché après le logo (hors playback)
}

/// Résultat d'une prise, transmis au journal.
struct TakeResult {
    let flashDate: Date?     // heure réelle de la 1re frame blanche
    let stopDate: Date
    let rating: Int          // 1 bonne, -1 mauvaise, 0 non notée
    let hadTimecode: Bool    // vrai si la prise s'est terminée par STOP
}

enum TimecodeMode {
    case none        // clap simple : retour au noir puis fermeture
    case timeOfDay   // heure du jour (horloge de l'iPhone)
    case sinceFlash  // temps écoulé depuis la 1re frame blanche
}

/// Écran plein du clap.
/// Principe : on choisit d'abord un rafraîchissement d'écran précis pour le flash,
/// puis on programme le son (bip ou morceau) pour qu'il sorte de l'enceinte exactement
/// à cet instant. Toutes les transitions tombent ensuite sur la grille des rafraîchissements.
/// En mode playback, le timecode du morceau défile ensuite en grand jusqu'à STOP.
final class FlashUIView: UIView {
    private let config: ClapConfig
    private let lead: Double
    private let scheduleSound: (CFTimeInterval) -> Bool
    private let onFinish: (TakeResult) -> Void

    private let slateLabel = UILabel()
    private let logoView = UIImageView()
    private let fallbackLogo = UILabel()
    private let timecodeLabel = UILabel()
    private let infoLabel = UILabel()
    private let stopControl = SwipeStopControl()
    private var flashDate: Date?
    private var displayLink: CADisplayLink?
    private let haptic = UIImpactFeedbackGenerator(style: .heavy)
    private let hasLogo: Bool

    // Plan du flash, calculé au premier rafraîchissement
    private var flashStart: CFTimeInterval?
    private var refreshPeriod: CFTimeInterval = 1.0 / 60
    private var whiteRefreshes = 1
    private var logoRefreshes = 1
    private var endRefreshes = 36
    private var hapticFired = false
    private var finished = false
    private var lastTimecode = ""
    private var wallClockOffset: Double = 0   // CACurrentMediaTime → secondes depuis minuit

    /// Vrai si un timecode défile après le logo (playback ou mode cinéma).
    private var hasRunningTimecode: Bool {
        config.playbackStart != nil || config.timecodeMode != .none
    }

    init(config: ClapConfig, lead: Double,
         scheduleSound: @escaping (CFTimeInterval) -> Bool,
         onFinish: @escaping (TakeResult) -> Void) {
        self.config = config
        self.lead = lead
        self.scheduleSound = scheduleSound
        self.onFinish = onFinish
        let image = UIImage(named: "logo")
        self.hasLogo = image != nil
        super.init(frame: .zero)
        backgroundColor = .black

        slateLabel.text = config.slateLines.joined(separator: "\n")
        slateLabel.numberOfLines = 0
        slateLabel.textAlignment = .center
        slateLabel.textColor = .white
        slateLabel.font = .monospacedSystemFont(ofSize: 44, weight: .heavy)
        slateLabel.adjustsFontSizeToFitWidth = true
        slateLabel.minimumScaleFactor = 0.3

        // Le logo est rendu en silhouette noire à partir de sa transparence (PNG détouré requis).
        logoView.image = image?.withRenderingMode(.alwaysTemplate)
        logoView.tintColor = .black
        logoView.contentMode = .scaleAspectFit
        logoView.isHidden = true

        fallbackLogo.text = "KRATOS"
        fallbackLogo.textColor = .black
        fallbackLogo.textAlignment = .center
        fallbackLogo.font = .systemFont(ofSize: 72, weight: .black)
        fallbackLogo.adjustsFontSizeToFitWidth = true
        fallbackLogo.isHidden = true

        timecodeLabel.textColor = .white
        timecodeLabel.textAlignment = .center
        timecodeLabel.font = .monospacedDigitSystemFont(ofSize: 140, weight: .bold)
        timecodeLabel.adjustsFontSizeToFitWidth = true
        timecodeLabel.minimumScaleFactor = 0.2
        timecodeLabel.isHidden = true

        infoLabel.text = config.slateLines.joined(separator: "  ·  ")
        infoLabel.textColor = UIColor(white: 0.8, alpha: 1)
        infoLabel.textAlignment = .center
        infoLabel.font = .monospacedSystemFont(ofSize: 22, weight: .semibold)
        infoLabel.adjustsFontSizeToFitWidth = true
        infoLabel.minimumScaleFactor = 0.4
        infoLabel.isHidden = true

        // STOP : toucher = prise non notée, glisser à droite = bonne, à gauche = mauvaise
        stopControl.isHidden = !hasRunningTimecode
        stopControl.onResult = { [weak self] rating in self?.finish(rating: rating) }

        addSubview(slateLabel)
        addSubview(logoView)
        addSubview(fallbackLogo)
        addSubview(timecodeLabel)
        addSubview(infoLabel)
        addSubview(stopControl)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Logo large (KRATOS VISUALS) : 85 % de la largeur, proportions conservées
        let width = bounds.width * 0.85
        let height = bounds.height * 0.5
        let logoFrame = CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2,
                               width: width, height: height)
        logoView.frame = logoFrame
        fallbackLogo.frame = logoFrame
        slateLabel.frame = bounds.insetBy(dx: 24, dy: 40)
        // Taille du texte du slate adaptée au nombre de lignes et à la hauteur de l'écran
        let lineCount = CGFloat(max(1, config.slateLines.count))
        let fontSize = min(44, (bounds.height - 100) / lineCount / 1.3)
        slateLabel.font = .monospacedSystemFont(ofSize: max(14, fontSize), weight: .heavy)

        let timecodeHeight = bounds.height * 0.4
        timecodeLabel.frame = CGRect(x: 16, y: (bounds.height - timecodeHeight) / 2,
                                     width: bounds.width - 32, height: timecodeHeight)
        infoLabel.frame = CGRect(x: 16, y: safeAreaInsets.top + 16,
                                 width: bounds.width - 32, height: 34)
        let controlSize = CGSize(width: min(bounds.width - 40, 380), height: 64)
        stopControl.frame = CGRect(x: (bounds.width - controlSize.width) / 2,
                                   y: bounds.height - safeAreaInsets.bottom - controlSize.height - 20,
                                   width: controlSize.width, height: controlSize.height)
    }

    func start() {
        haptic.prepare()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        // 120 Hz sur les modèles ProMotion, 60 Hz sinon (iPhone 16 standard)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func finish(rating: Int = 0) {
        guard !finished else { return }
        finished = true
        stop()
        onFinish(TakeResult(flashDate: flashDate, stopDate: Date(),
                            rating: rating, hadTimecode: hasRunningTimecode))
    }

    /// Choisit le rafraîchissement du flash et programme le son dessus.
    private func planFlash(_ link: CADisplayLink) {
        var period = link.targetTimestamp - link.timestamp
        if period < 0.004 { period = link.duration }
        if period < 0.004 { period = 1.0 / 60 }
        refreshPeriod = period

        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now)
        wallClockOffset = now.timeIntervalSince(midnight) - CACurrentMediaTime()

        // Premier rafraîchissement après le délai d'affichage du slate
        let wanted = CACurrentMediaTime() + lead
        let steps = max(1, ((wanted - link.targetTimestamp) / period).rounded(.up))
        var start = link.targetTimestamp + steps * period

        // Si le son ne peut pas partir assez tôt (latence très longue), on recule le flash
        // d'un nombre entier de rafraîchissements pour rester sur la grille.
        let shift = (0.5 / period).rounded(.up) * period
        var attempts = 0
        while !scheduleSound(start) && attempts < 3 {
            start += shift
            attempts += 1
        }
        flashStart = start
        flashDate = Date(timeIntervalSinceNow: start - CACurrentMediaTime())

        // Durées converties en nombre entier de rafraîchissements (arrondi au plus proche)
        let frame = 1.0 / config.fps
        whiteRefreshes = max(1, Int((config.whiteFrames * frame / period).rounded()))
        logoRefreshes = max(1, Int((config.logoFrames * frame / period).rounded()))
        endRefreshes = max(1, Int((0.6 / period).rounded()))
    }

    @objc private func tick(_ link: CADisplayLink) {
        if flashStart == nil { planFlash(link) }
        guard let start = flashStart, !finished else { return }

        // Numéro du rafraîchissement par rapport au flash (0 = première image blanche).
        // targetTimestamp = moment où l'image en préparation sera réellement affichée.
        let index = Int(((link.targetTimestamp - start) / refreshPeriod).rounded())
        let hasTimecode = hasRunningTimecode

        if index < 0 {
            show(background: .black, slate: true, logo: false, timecode: false, stop: hasTimecode)
        } else if index < whiteRefreshes {
            if !hapticFired { haptic.impactOccurred(); hapticFired = true }
            show(background: .white, slate: false, logo: false, timecode: false, stop: false)
        } else if index < whiteRefreshes + logoRefreshes {
            show(background: .white, slate: false, logo: true, timecode: false, stop: false)
        } else if hasTimecode {
            // Le timecode s'affiche dès que le logo disparaît, jusqu'à STOP.
            let sinceFlash = Double(index) * refreshPeriod
            let seconds: Double
            if let songStart = config.playbackStart {
                // Position du morceau entendue au moment où cette image s'affiche
                seconds = songStart + sinceFlash
                if seconds >= config.songDuration { finish(); return }
            } else if config.timecodeMode == .timeOfDay {
                seconds = (start + sinceFlash + wallClockOffset).truncatingRemainder(dividingBy: 86_400)
            } else {
                seconds = sinceFlash
            }
            let text = Timecode.string(seconds, fps: config.fps)
            if text != lastTimecode {
                timecodeLabel.text = text
                lastTimecode = text
            }
            show(background: .black, slate: false, logo: false, timecode: true, stop: true)
        } else if index < whiteRefreshes + logoRefreshes + endRefreshes {
            show(background: .black, slate: false, logo: false, timecode: false, stop: false)
        } else {
            finish()
        }
    }

    private func show(background: UIColor, slate: Bool, logo: Bool, timecode: Bool, stop: Bool) {
        if backgroundColor != background { backgroundColor = background }
        slateLabel.isHidden = !slate
        logoView.isHidden = !(logo && hasLogo)
        fallbackLogo.isHidden = !(logo && !hasLogo)
        timecodeLabel.isHidden = !timecode
        infoLabel.isHidden = !timecode
        stopControl.isHidden = !stop
    }
}

struct FlashView: UIViewRepresentable {
    let config: ClapConfig
    let lead: Double
    let scheduleSound: (CFTimeInterval) -> Bool
    let onFinish: (TakeResult) -> Void

    final class Coordinator { var previousBrightness: CGFloat = 0.5 }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> FlashUIView {
        context.coordinator.previousBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 1.0
        let view = FlashUIView(config: config, lead: lead,
                               scheduleSound: scheduleSound, onFinish: onFinish)
        view.start()
        return view
    }

    func updateUIView(_ uiView: FlashUIView, context: Context) {}

    static func dismantleUIView(_ uiView: FlashUIView, coordinator: Coordinator) {
        uiView.stop()
        UIScreen.main.brightness = coordinator.previousBrightness
    }
}

/// Bouton STOP qui se glisse :
/// toucher = arrêt (prise non notée), glisser à droite = BONNE, à gauche = MAUVAISE.
final class SwipeStopControl: UIView {
    var onResult: ((Int) -> Void)?

    private let label = UILabel()
    private let threshold: CGFloat = 80
    private var crossed = 0
    private var done = false
    private let feedback = UISelectionFeedbackGenerator()

    private static let restColor = UIColor(white: 0.2, alpha: 1)
    private static let goodColor = UIColor(red: 0.13, green: 0.65, blue: 0.3, alpha: 1)
    private static let badColor = UIColor(red: 0.8, green: 0.15, blue: 0.15, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Self.restColor
        layer.cornerRadius = 18
        label.textAlignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 20, weight: .heavy)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        addSubview(label)
        resetText()
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 14, dy: 0)
    }

    private func resetText() {
        label.text = "✗ ◀     ■ STOP     ▶ ✓"
    }

    private func send(_ rating: Int) {
        guard !done else { return }
        done = true
        onResult?(rating)
    }

    @objc private func tap() { send(0) }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        let x = gesture.translation(in: self).x
        switch gesture.state {
        case .began:
            feedback.prepare()
        case .changed:
            transform = CGAffineTransform(translationX: x * 0.6, y: 0)
            let progress = min(1, abs(x) / threshold)
            backgroundColor = Self.blend(Self.restColor, x >= 0 ? Self.goodColor : Self.badColor, progress)
            let state = abs(x) >= threshold ? (x > 0 ? 1 : -1) : 0
            if state != crossed {
                crossed = state
                if state != 0 { feedback.selectionChanged() }
            }
            if state == 1 {
                label.text = "BONNE PRISE ✓"
            } else if state == -1 {
                label.text = "✗ MAUVAISE PRISE"
            } else {
                label.text = x > 0 ? "BONNE ▶" : "◀ MAUVAISE"
            }
        case .ended where crossed != 0:
            send(crossed)
        case .ended, .cancelled, .failed:
            crossed = 0
            resetText()
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7,
                           initialSpringVelocity: 0, options: []) {
                self.transform = .identity
                self.backgroundColor = Self.restColor
            }
        default:
            break
        }
    }

    private static func blend(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: 1)
    }
}
