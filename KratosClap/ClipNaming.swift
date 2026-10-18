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

/// Ligne « Clip » du slate : bobine et numéro de clip (RED), ou nom libre.
struct ClipNameRow: View {
    let showCameraPicker: Bool

    @AppStorage(ClipNaming.formatKey) private var format = 0
    @AppStorage(ClipNaming.cameraKey) private var camera = "A"
    @AppStorage(ClipNaming.reelKey) private var reel = 1
    @AppStorage(ClipNaming.clipKey) private var clip = 1
    @AppStorage(ClipNaming.suffixKey) private var suffix = ""
    @AppStorage(ClipNaming.freeNameKey) private var freeName = ""

    var body: some View {
        if format == 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Clip caméra")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(ClipNaming.redName(camera: camera, reel: reel, clip: clip, suffix: suffix))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                HStack(spacing: 12) {
                    if showCameraPicker {
                        Menu {
                            ForEach(["A", "B", "C", "D"], id: \.self) { letter in
                                Button("CAM \(letter)") { camera = letter }
                            }
                        } label: {
                            Text("CAM \(camera)")
                                .font(.caption.weight(.bold))
                        }
                        Divider()
                    }
                    // Nouvelle bobine (nouveau mag) : le clip repart à 1
                    CounterView(label: "BOBINE", value: Binding(get: { reel },
                                                                set: { reel = $0; clip = 1 }))
                    Divider()
                    CounterView(label: "CLIP", value: $clip)
                }
            }
            .padding(.vertical, 2)
        } else {
            TextField("Nom du clip caméra", text: $freeName)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
    }
}
