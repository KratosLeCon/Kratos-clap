import SwiftUI
import UIKit

struct ClapConfig {
    var fps: Double
    var whiteFrames: Double   // frames blanches avant le logo (2 → logo sur la 3e)
    var logoFrames: Double    // durée du logo, en frames caméra
    var slateLines: [String]
}

/// Écran plein du clap.
/// Principe : on choisit d'abord un rafraîchissement d'écran précis pour le flash,
/// puis on programme le bip pour qu'il sorte de l'enceinte exactement à cet instant.
/// Toutes les transitions tombent ensuite sur la grille des rafraîchissements.
final class FlashUIView: UIView {
    private let config: ClapConfig
    private let lead: Double
    private let scheduleSound: (CFTimeInterval) -> Bool
    private let onFinish: () -> Void

    private let slateLabel = UILabel()
    private let logoView = UIImageView()
    private let fallbackLogo = UILabel()
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

    init(config: ClapConfig, lead: Double,
         scheduleSound: @escaping (CFTimeInterval) -> Bool,
         onFinish: @escaping () -> Void) {
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

        addSubview(slateLabel)
        addSubview(logoView)
        addSubview(fallbackLogo)
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

    /// Choisit le rafraîchissement du flash et programme le son dessus.
    private func planFlash(_ link: CADisplayLink) {
        var period = link.targetTimestamp - link.timestamp
        if period < 0.004 { period = link.duration }
        if period < 0.004 { period = 1.0 / 60 }
        refreshPeriod = period

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

        // Durées converties en nombre entier de rafraîchissements (arrondi au plus proche)
        let frame = 1.0 / config.fps
        whiteRefreshes = max(1, Int((config.whiteFrames * frame / period).rounded()))
        logoRefreshes = max(1, Int((config.logoFrames * frame / period).rounded()))
        endRefreshes = max(1, Int((0.6 / period).rounded()))
    }

    @objc private func tick(_ link: CADisplayLink) {
        if flashStart == nil { planFlash(link) }
        guard let start = flashStart else { return }

        // Numéro du rafraîchissement par rapport au flash (0 = première image blanche).
        // targetTimestamp = moment où l'image en préparation sera réellement affichée.
        let index = Int(((link.targetTimestamp - start) / refreshPeriod).rounded())

        if index < 0 {
            show(background: .black, slate: true, logo: false)
        } else if index < whiteRefreshes {
            if !hapticFired { haptic.impactOccurred(); hapticFired = true }
            show(background: .white, slate: false, logo: false)
        } else if index < whiteRefreshes + logoRefreshes {
            show(background: .white, slate: false, logo: true)
        } else if index < whiteRefreshes + logoRefreshes + endRefreshes {
            show(background: .black, slate: false, logo: false)
        } else if !finished {
            finished = true
            stop()
            onFinish()
        }
    }

    private func show(background: UIColor, slate: Bool, logo: Bool) {
        if backgroundColor != background { backgroundColor = background }
        slateLabel.isHidden = !slate
        logoView.isHidden = !(logo && hasLogo)
        fallbackLogo.isHidden = !(logo && !hasLogo)
    }
}

struct FlashView: UIViewRepresentable {
    let config: ClapConfig
    let lead: Double
    let scheduleSound: (CFTimeInterval) -> Bool
    let onFinish: () -> Void

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
