import SwiftUI

/// Journal des prises : liste par jour, notation par glissement, export CSV.
struct JournalView: View {
    @EnvironmentObject private var log: TakeLogStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    @State private var exportURL: URL?
    @State private var renaming: TakeEntry?
    @State private var newClipName = ""

    var body: some View {
        NavigationStack {
            Group {
                if log.entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Aucune prise pour l'instant")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(days, id: \.self) { day in
                            Section(day) {
                                ForEach(entries(on: day)) { entry in
                                    TakeRow(entry: entry)
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                log.setRating(entry.id, 1)
                                            } label: {
                                                Label("Bonne", systemImage: "checkmark")
                                            }
                                            .tint(.green)
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button {
                                                log.setRating(entry.id, -1)
                                            } label: {
                                                Label("Mauvaise", systemImage: "xmark")
                                            }
                                            .tint(.red)
                                            Button(role: .destructive) {
                                                log.delete(entry.id)
                                            } label: {
                                                Label("Supprimer", systemImage: "trash")
                                            }
                                        }
                                        .contextMenu {
                                            Button("Bonne prise") { log.setRating(entry.id, 1) }
                                            Button("Mauvaise prise") { log.setRating(entry.id, -1) }
                                            Button("Non notée") { log.setRating(entry.id, 0) }
                                            Button("Renommer le clip…") {
                                                newClipName = entry.clipName ?? ""
                                                renaming = entry
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Journal des prises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("OK") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let url = exportURL, !log.entries.isEmpty {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    Menu {
                        Button("Vider le journal", role: .destructive) { confirmClear = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Supprimer toutes les prises du journal ?",
                                isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Vider le journal", role: .destructive) { log.clear() }
            }
            .alert("Nom du clip caméra",
                   isPresented: Binding(get: { renaming != nil },
                                        set: { if !$0 { renaming = nil } })) {
                TextField("A001_C007", text: $newClipName)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Annuler", role: .cancel) { renaming = nil }
                Button("OK") {
                    if let entry = renaming { log.setClipName(entry.id, newClipName) }
                    renaming = nil
                }
            }
            .onAppear { exportURL = log.exportCSV() }
            .onChange(of: log.entries) { _ in exportURL = log.exportCSV() }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        date.formatted(date: .complete, time: .omitted)
    }

    /// Jours du plus récent au plus ancien.
    private var days: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in log.entries.reversed() {
            let label = dayLabel(entry.date)
            if !seen.contains(label) {
                seen.insert(label)
                result.append(label)
            }
        }
        return result
    }

    /// Prises d'un jour, de la plus récente à la plus ancienne.
    private func entries(on day: String) -> [TakeEntry] {
        log.entries.reversed().filter { dayLabel($0.date) == day }
    }
}

struct TakeRow: View {
    let entry: TakeEntry

    private var ratingColor: Color {
        switch entry.rating {
        case 1: return .green
        case -1: return .red
        default: return Color(white: 0.5)
        }
    }

    private var title: String {
        if entry.mode == "CINÉMA" {
            return "SC \(entry.scene) · PL \(entry.shot) · PR \(entry.take) · CAM \(entry.camera)"
        }
        let artist = entry.production.isEmpty ? "Artiste" : entry.production
        return "\(artist) · SÉQ \(entry.scene) · PR \(entry.take)"
    }

    private var subtitle: String {
        var text = "\(entry.date.formatted(date: .omitted, time: .shortened)) · TC \(entry.flashTimecode)"
        if let clip = entry.clipName {
            text = clip + " · " + text
        }
        if let duration = entry.duration {
            text += " · " + Timecode.short(duration)
        }
        if let start = entry.playbackStart {
            text += " · ♪ " + Timecode.short(start)
        }
        return text
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(ratingColor)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(entry.mode)
                .font(.caption2.weight(.bold))
                .foregroundStyle(entry.mode == "CLIP" ? Color.red : Color.green)
        }
    }
}
