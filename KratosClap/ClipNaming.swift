import SwiftUI

/// Nom du fichier caméra associé à chaque prise, pour relier le journal aux rushes en post.
/// Format RED : <caméra><bobine>_C<clip>[_<fin>]  ex. A001_C007 ou A001_C007_1018XY
/// Format libre : nom saisi à la main (autres caméras).
enum ClipNaming {
    static let formatKey = "nommageClips"      // 0 = RED, 1 = libre
    static let cameraKey = "cineCamera"        // lettre partagée avec le mode cinéma
    static let reelKey = "clipBobine"
    static let clipKey = "clipNumero"
    static let suffixKey = "clipSuffixe"
    static let freeNameKey = "clipNomLibre"

    static func redName(camera: String, reel: Int, clip: Int, suffix: String) -> String {
        var name = camera + String(format: "%03d_C%03d", reel, clip)
        let end = suffix.trimmingCharacters(in: .whitespaces)
        if !end.isEmpty { name += "_" + end }
        return name
    }

    /// Nom du clip pour la prise en cours, lu dans les réglages enregistrés.
    static func currentName() -> String {
        let defaults = UserDefaults.standard
        let format = defaults.object(forKey: formatKey) as? Int ?? 0
        if format == 1 {
            return (defaults.string(forKey: freeNameKey) ?? "").trimmingCharacters(in: .whitespaces)
        }
        return redName(camera: defaults.string(forKey: cameraKey) ?? "A",
                       reel: defaults.object(forKey: reelKey) as? Int ?? 1,
                       clip: defaults.object(forKey: clipKey) as? Int ?? 1,
                       suffix: defaults.string(forKey: suffixKey) ?? "")
    }

    /// Après une prise : en format RED, le numéro de clip avance de 1.
    static func advance() {
        let defaults = UserDefaults.standard
        guard (defaults.object(forKey: formatKey) as? Int ?? 0) == 0 else { return }
        let clip = defaults.object(forKey: clipKey) as? Int ?? 1
        defaults.set(min(999, clip + 1), forKey: clipKey)
    }
}

/// Ligne « Clip caméra » : nom du fichier + boutons bobine / clip (RED), ou nom libre.
struct ClipNameRow: View {
    @AppStorage(ClipNaming.formatKey) private var format = 0
    @AppStorage(ClipNaming.cameraKey) private var camera = "A"
    @AppStorage(ClipNaming.reelKey) private var reel = 1
    @AppStorage(ClipNaming.clipKey) private var clip = 1
    @AppStorage(ClipNaming.suffixKey) private var suffix = ""
    @AppStorage(ClipNaming.freeNameKey) private var freeName = ""

    var body: some View {
        if format == 0 {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    FieldLabel(text: "CLIP CAMÉRA")
                    Text(ClipNaming.redName(camera: camera, reel: reel, clip: clip, suffix: suffix))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 4)
                // Nouvelle bobine (nouveau mag) : le clip repart à 1
                MiniStepper(label: "BOBINE",
                            onMinus: { if reel > 1 { reel -= 1; clip = 1 } },
                            onPlus: { if reel < 999 { reel += 1; clip = 1 } })
                MiniStepper(label: "CLIP",
                            onMinus: { if clip > 1 { clip -= 1 } },
                            onPlus: { if clip < 999 { clip += 1 } })
            }
            .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                FieldLabel(text: "CLIP CAMÉRA")
                TextField("Nom du fichier", text: $freeName)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            .padding(.vertical, 6)
        }
    }
}

/// Libellé au-dessus de deux boutons − / + (le nombre est déjà visible dans le nom).
struct MiniStepper: View {
    let label: String
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            FieldLabel(text: label)
            HStack(spacing: 6) {
                Button(action: onMinus) {
                    Image(systemName: "minus.circle.fill").font(.title3)
                }
                Button(action: onPlus) {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
        }
        .buttonStyle(.borderless)
    }
}
