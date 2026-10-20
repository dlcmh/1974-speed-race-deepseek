import Foundation

// Speed Race (1974) — Swift + Metal port.
//
// PORT OF: `draw_seven_digit` and `draw_seven_number` in src/gfx.rs.
//
// The LED scoreboard is the original cabinet's most important feedback, so the
// segment geometry is copied unmodified: each lit segment also paints a 2 px
// halo in the LED green used by the launch glow.

public enum SevenSegment {
    /// `draw_seven_digit`.
    public static func drawDigit(
        _ list: DrawList, x: Float, y: Float, w: Float, h: Float, thickness: Float,
        digit: UInt8, litColor: RGBAColor
    ) {
        let mask = PixelFont.digitSegments[Int(digit % 10)]
        let t = thickness
        let half = h * 0.5
        let segments: [(Float, Float, Float, Float)] = [
            (x + t, y, w - 2.0 * t, t),  // 0 top
            (x + w - t, y + t, t, half - 1.5 * t),  // 1 upper right
            (x + w - t, y + half + 0.5 * t, t, half - 1.5 * t),  // 2 lower right
            (x + t, y + h - t, w - 2.0 * t, t),  // 3 bottom
            (x, y + half + 0.5 * t, t, half - 1.5 * t),  // 4 lower left
            (x, y + t, t, half - 1.5 * t),  // 5 upper left
            (x + t, y + half - 0.5 * t, w - 2.0 * t, t),  // 6 middle
        ]

        for (index, segment) in segments.enumerated() {
            let (sx, sy, sw, sh) = segment
            let isLit = mask & (1 << UInt8(index)) != 0
            if isLit {
                list.rectangle(
                    sx - 2.0, sy - 2.0, sw + 4.0, sh + 4.0, Palette.ledGreen.withAlpha(0.075))
            }
            list.rectangle(sx, sy, sw, sh, isLit ? litColor : RGBAColor.rgb(12, 45, 25))
        }
    }

    /// `draw_seven_number` — most significant digit first, with `gap` between.
    ///
    /// Rust computes each digit's divisor with `10u32.pow(digits - 1 - i)`.
    /// Walking a single divisor down from the highest place value gives the
    /// same digits for every supported width (1...10) and cannot trap.
    public static func drawNumber(
        _ list: DrawList, value: UInt32, digits: Int, x: Float, y: Float, digitWidth: Float,
        digitHeight: Float, thickness: Float, gap: Float, color: RGBAColor
    ) {
        guard digits > 0 else { return }
        var divisor: UInt32 = 1
        for _ in 0..<(digits - 1) {
            divisor = divisor &* 10
        }
        for i in 0..<digits {
            let digit = UInt8((value / divisor) % 10)
            drawDigit(
                list, x: x + Float(i) * (digitWidth + gap), y: y, w: digitWidth, h: digitHeight,
                thickness: thickness, digit: digit, litColor: color)
            divisor /= 10
        }
    }
}
