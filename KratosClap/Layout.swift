import SwiftUI

/// Mise en page commune aux deux pages (Clip et Cinéma) :
/// même ordre de cartes, mêmes libellés, mêmes contrôles.
enum PageLayout {
    static let topInset: CGFloat = 56      // place de la barre du haut (fixe, transparente)
    static let bottomInset: CGFloat = 96   // place du bouton CLAP (fixe)
}

/// Page défilante seulement si nécessaire (clavier ouvert) : tout tient sur un écran.
struct PageScroll<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, PageLayout.topInset)
            .padding(.bottom, PageLayout.bottomInset)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

/// Carte avec titre, à la manière d'une section de réglages, mais plus compacte.
struct Card<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// Libellé court en petites capitales, au-dessus d'un champ ou d'un compteur.
struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Champ texte avec libellé au-dessus (projet, scène, plan…).
struct LabeledField<Field: Hashable>: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Field?>.Binding
    let field: Field
    var centered = false
    var capitals = false

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 2) {
            FieldLabel(text: label)
            TextField(placeholder, text: $text)
                .focused(focus, equals: field)
                .multilineTextAlignment(centered ? .center : .leading)
                .font(centered ? .title3.weight(.bold) : .body)
                .textInputAutocapitalization(capitals ? .characters : .words)
                .autocorrectionDisabled(capitals)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .padding(.vertical, 6)
    }
}

/// Compteur : libellé au-dessus, − valeur + en dessous (séquence, scène, prise).
struct CounterView: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        VStack(spacing: 2) {
            FieldLabel(text: label)
            HStack(spacing: 6) {
                Button {
                    if value > 1 { value -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill").font(.title3)
                }
                Text("\(value)")
                    .font(.title3.monospacedDigit().weight(.bold))
                    .lineLimit(1)
                    .frame(minWidth: 30)
                Button {
                    if value < 999 { value += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// Choix de la caméra A/B/C/D, partagé par les deux pages et par le nom de clip.
struct CameraPicker: View {
    @AppStorage(ClipNaming.cameraKey) private var camera = "A"

    var body: some View {
        Picker("Caméra", selection: $camera) {
            ForEach(["A", "B", "C", "D"], id: \.self) { letter in
                Text("CAM \(letter)").tag(letter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 8)
    }
}

/// Séparateur vertical court entre deux champs d'une même ligne.
struct FieldSeparator: View {
    var body: some View {
        Divider().frame(height: 34)
    }
}
