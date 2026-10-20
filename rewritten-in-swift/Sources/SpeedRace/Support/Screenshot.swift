import Foundation

// Speed Race (1974) — Swift + Metal port.
//
// PORT OF: save_screenshot in src/main.rs (F12).
//
// The canonical game writes `speed-race-screenshot.png` next to the game from
// the raw framebuffer, and its ADR-0007 says the readback must never be row
// flipped: a flip there hid an upside-down live window. The port's readback is
// already top-row-first, so this writes the pixels unchanged and uses a
// distinct filename so the two implementations cannot overwrite each other
// (docs/DIVERGENCES.md D-0004).

public enum Screenshot {
    public static let fileName = "speed-race-swift-screenshot.png"

    /// Writes straight-alpha RGBA pixels next to the current directory.
    @discardableResult
    public static func save(
        width: Int, height: Int, pixels: [UInt8], directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL? {
        let data = PNGEncoder.encodeRGBA(width: width, height: height, pixels: pixels)
        let url = directory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
