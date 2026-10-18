import Foundation
import Combine

/// Une prise du journal.
struct TakeEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var mode: String                 // "CLIP" ou "CINÉMA"
    var date = Date()                // instant de la 1re frame blanche
    var production: String           // artiste (clip) ou production (cinéma)
    var title = ""                   // titre du morceau (clip)
    var scene: String                // séquence (clip) ou scène (cinéma)
    var shot = ""                    // plan (cinéma)
    var take: Int
    var camera = ""
    var director = ""
    var cameraOperator = ""
    var fps: Double
    var playbackStart: Double?       // position du morceau au flash (clip + playback)
    var flashTimecode = ""           // heure du jour au flash, en timecode
    var stopTimecode = ""            // heure du jour au STOP
    var duration: Double?            // secondes entre flash et STOP
    var rating = 0                   // 1 bonne, -1 mauvaise, 0 non notée
    var note = ""
}

/// Journal des prises, enregistré dans l'app (Documents/journal-prises.json).
final class TakeLogStore: ObservableObject {
    @Published private(set) var entries: [TakeEntry] = []
    private let fileURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("journal-prises.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([TakeEntry].self, from: data) {
            entries = decoded
        }
    }

    /// Complète la prise avec les heures et la note, puis l'ajoute au journal.
    func record(_ template: TakeEntry, result: TakeResult) {
        var entry = template
        let flash = result.flashDate ?? result.stopDate
        entry.date = flash
        entry.flashTimecode = Self.timeOfDayTimecode(flash, fps: entry.fps)
        if result.hadTimecode {
            entry.stopTimecode = Self.timeOfDayTimecode(result.stopDate, fps: entry.fps)
            entry.duration = max(0, result.stopDate.timeIntervalSince(flash))
        }
        entry.rating = result.rating
        entries.append(entry)
        save()
    }

    func setRating(_ id: UUID, _ rating: Int) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].rating = rating
        save()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func timeOfDayTimecode(_ date: Date, fps: Double) -> String {
        let seconds = date.timeIntervalSince(Calendar.current.startOfDay(for: date))
        return Timecode.string(seconds, fps: fps)
    }

    // MARK: - Export CSV

    /// Écrit le journal en CSV (virgules, UTF-8) et renvoie l'adresse du fichier.
    /// Les colonnes Scene / Shot / Take / Camera # / Good Take / Comments reprennent
    /// les noms des métadonnées de DaVinci Resolve.
    func exportCSV() -> URL? {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        let header = ["Date", "Heure", "Mode", "Production / Artiste", "Titre",
                      "Scene", "Shot", "Take", "Camera #", "Qualite", "Good Take", "Comments",
                      "TC flash", "TC stop", "Duree (s)", "Depart playback",
                      "Realisateur", "Operateur", "Cadence"]
        var lines = [header.map(Self.quoted).joined(separator: ",")]

        for entry in entries {
            let quality = entry.rating == 1 ? "BONNE" : (entry.rating == -1 ? "MAUVAISE" : "")
            let fields: [String] = [
                dayFormatter.string(from: entry.date),
                timeFormatter.string(from: entry.date),
                entry.mode,
                entry.production,
                entry.title,
                entry.scene,
                entry.shot,
                "\(entry.take)",
                entry.camera,
                quality,
                entry.rating == 1 ? "1" : "",
                entry.note,
                entry.flashTimecode,
                entry.stopTimecode,
                entry.duration.map { String(format: "%.1f", $0) } ?? "",
                entry.playbackStart.map { Timecode.string($0, fps: entry.fps) } ?? "",
                entry.director,
                entry.cameraOperator,
                ContentView.fpsLabel(entry.fps)
            ]
            lines.append(fields.map(Self.quoted).joined(separator: ","))
        }

        let name = "Journal-KratosClap-\(dayFormatter.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try lines.joined(separator: "\r\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
