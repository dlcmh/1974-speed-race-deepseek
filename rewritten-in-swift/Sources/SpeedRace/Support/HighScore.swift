import Foundation

// Speed Race (1974) — Swift + Metal port.
//
// PORT OF: load_high_score / save_high_score in src/main.rs.
//
// The canonical game persists the best score to `~/.speed_race_1974_highscore`.
// The port deliberately uses its own file so the two implementations cannot
// overwrite each other's scores (docs/DIVERGENCES.md D-0004).
//
// Same tiny read/write as the Rust version: no file locking, no settings, and a
// missing or malformed file simply reads as zero.

public enum HighScore {
    /// `~/.speed_race_1974_swift_highscore`.
    public static var path: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".speed_race_1974_swift_highscore")
    }

    /// Reads the stored best score, clamped to the same maximum as Rust.
    public static func load() -> UInt32 {
        guard
            let text = try? String(contentsOf: path, encoding: .utf8),
            let value = UInt32(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return 0
        }
        return min(value, 9_999_999)
    }

    /// Writes the best score; failures are ignored, exactly like the Rust code.
    public static func save(_ score: UInt32) {
        try? "\(score)\n".write(to: path, atomically: true, encoding: .utf8)
    }
}
