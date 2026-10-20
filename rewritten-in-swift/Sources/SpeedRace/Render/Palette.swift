import Foundation

// Speed Race (1974) — Swift + Metal port.
//
// PORT OF: the palette, 5 x 7 bitmap font and seven-segment tables at the
// top of src/gfx.rs.
//
// These are data, not behaviour: every value is copied from the Rust source.
// If you change a colour or a glyph here you are changing the canonical game
// artwork, so the Rust reference must change in the same commit (see
// docs/INVESTIGATION-parity.md "What parity means").

/// Palette from gfx.rs. Names match the Rust constants so a diff reader can
/// grep either language and find its twin.
public enum Palette {
    public static let void = RGBAColor.rgb(3, 8, 5)
    public static let sky = RGBAColor.rgb(2, 7, 4)
    public static let roadA = RGBAColor.rgb(5, 24, 12)
    public static let roadB = RGBAColor.rgb(7, 30, 15)
    public static let roadEdge = RGBAColor.rgb(56, 194, 104)
    public static let roadEdgeHot = RGBAColor.rgb(157, 255, 183)
    public static let laneLine = RGBAColor.rgb(43, 133, 72)
    public static let phosphor = RGBAColor.rgb(116, 255, 151)
    public static let phosphorWhite = RGBAColor.rgb(215, 255, 224)
    public static let phosphorDim = RGBAColor.rgb(30, 96, 50)
    public static let phosphorDark = RGBAColor.rgb(12, 49, 24)
    public static let spark = RGBAColor.rgb(210, 255, 210)
    public static let carWhite = RGBAColor.rgb(196, 255, 210)
    public static let carMid = RGBAColor.rgb(110, 220, 140)
    public static let carDark = RGBAColor.rgb(27, 92, 48)
    public static let carGlass = RGBAColor.rgb(2, 20, 9)
    public static let tire = RGBAColor.rgb(1, 7, 3)

    public static let wall = RGBAColor.rgb(7, 7, 7)
    public static let wallLine = RGBAColor.rgb(15, 14, 12)
    public static let cabinetDark = RGBAColor.rgb(23, 19, 15)
    public static let cabinetBlack = RGBAColor.rgb(6, 6, 5)
    public static let orange = RGBAColor.rgb(187, 86, 32)
    public static let orangeDark = RGBAColor.rgb(119, 51, 20)
    public static let orangeLight = RGBAColor.rgb(218, 112, 45)
    public static let cream = RGBAColor.rgb(243, 222, 171)
    public static let ledGreen = RGBAColor.rgb(91, 255, 132)
    public static let ledAmber = RGBAColor.rgb(242, 183, 62)
}

/// The compact 5 x 7 bitmap font from gfx.rs `glyph()`.
///
/// Each glyph is seven rows of five bits, MSB = leftmost column. Rust builds
/// this with a `match`; Swift uses a switch with identical patterns
/// (underscores are Rust's `0`).
public enum PixelFont {
    /// Width of `text` at `scale`, matching `text_width`.
    ///
    /// Rust counts `.chars()`, i.e. Unicode scalar values. Every string the
    /// game draws is ASCII, but the port follows `unicodeScalars.count` so
    /// the rule is identical for any future text.
    public static func width(_ text: String, _ scale: Float) -> Float {
        let count = Float(text.unicodeScalars.count)
        if count == 0 {
            return 0.0
        }
        return count * 6.0 * scale - scale
    }

    public static func glyph(_ character: Character) -> [UInt8]? {
        switch character.uppercased().first ?? character {
        case "A": return [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001]
        case "B": return [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110]
        case "C": return [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110]
        case "D": return [0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110]
        case "E": return [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111]
        case "F": return [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000]
        case "G": return [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111]
        case "H": return [0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001]
        case "I": return [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b11111]
        case "J": return [0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100]
        case "K": return [0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001]
        case "L": return [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111]
        case "M": return [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001]
        case "N": return [0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001]
        case "O": return [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]
        case "P": return [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000]
        case "Q": return [0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101]
        case "R": return [0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001]
        case "S": return [0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110]
        case "T": return [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100]
        case "U": return [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]
        case "V": return [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100]
        case "W": return [0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b10101, 0b01010]
        case "X": return [0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001]
        case "Y": return [0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100]
        case "Z": return [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111]
        case "0": return [0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110]
        case "1": return [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110]
        case "2": return [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111]
        case "3": return [0b11111, 0b00010, 0b00100, 0b00010, 0b00001, 0b10001, 0b01110]
        case "4": return [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010]
        case "5": return [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110]
        case "6": return [0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110]
        case "7": return [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000]
        case "8": return [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110]
        case "9": return [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100]
        case ":": return [0b00000, 0b00100, 0b00100, 0b00000, 0b00100, 0b00100, 0b00000]
        case ".": return [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00100, 0b00100]
        case ",": return [0b00000, 0b00000, 0b00000, 0b00000, 0b00100, 0b00100, 0b01000]
        case "-": return [0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000]
        case "!": return [0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00000, 0b00100]
        case "?": return [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b00000, 0b00100]
        case "/": return [0b00001, 0b00010, 0b00010, 0b00100, 0b01000, 0b01000, 0b10000]
        case "+": return [0b00000, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00000]
        case "=": return [0b00000, 0b00000, 0b11111, 0b00000, 0b11111, 0b00000, 0b00000]
        case "'": return [0b00100, 0b00100, 0b01000, 0b00000, 0b00000, 0b00000, 0b00000]
        default: return nil
        }
    }

    /// Seven-segment masks for 0...9, bits 0...6 = segments in gfx.rs order
    /// (top, upper-right, lower-right, bottom, lower-left, upper-left, middle).
    public static let digitSegments: [UInt8] = [
        0b0111111, 0b0000110, 0b1011011, 0b1001111, 0b1100110,
        0b1101101, 0b1111101, 0b0000111, 0b1111111, 0b1101111,
    ]
}
