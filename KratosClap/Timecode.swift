import Foundation

enum Timecode {
    /// Timecode HH:MM:SS:FF d'une position dans le morceau, tel qu'il apparaîtra
    /// dans une timeline où le morceau commence à 00:00:00:00.
    /// En 23.976 / 29.97, les frames sont comptées sur la base 24 / 30 (non drop-frame).
    static func string(_ seconds: Double, fps: Double) -> String {
        let base = max(1, Int(fps.rounded()))
        let totalFrames = Int((max(0, seconds) * fps).rounded(.down))
        let frames = totalFrames % base
        let totalSeconds = totalFrames / base
        return String(format: "%02d:%02d:%02d:%02d",
                      totalSeconds / 3600, (totalSeconds / 60) % 60, totalSeconds % 60, frames)
    }

    /// Format court pour l'interface : 1:23.4
    static func short(_ seconds: Double) -> String {
        let s = max(0, seconds)
        let minutes = Int(s) / 60
        let rest = s - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, rest)
    }
}
