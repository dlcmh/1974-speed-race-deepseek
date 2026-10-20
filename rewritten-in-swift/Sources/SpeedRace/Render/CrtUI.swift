import Foundation

// Speed Race (1974) — Swift + Metal port.
//
// PORT OF: `draw_crt_ui`, `draw_attract`, `draw_countdown`, `draw_race_notice`
// and `draw_game_over` in src/gfx.rs.
//
// These are the overlays painted inside the 240 x 360 tube. All text goes
// through `CrtScene.drawPixelText`, exactly like the Rust renderer, so the
// low internal resolution stays chunky.
//
// Time-dependent pulses use the same expression as Rust (`get_time()`), with
// `time` passed in so the renderer is deterministic and testable.

public enum CrtUI {
    static func draw(_ list: DrawList, game: Game, time: Float) {
        switch game.phase {
        case .attract: drawAttract(list, game: game)
        case .countdown: drawCountdown(list, game: game)
        case .gameOver: drawGameOver(list, game: game, time: time)
        case .racing, .crashed: drawRaceNotice(list, game: game, time: time)
        }

        if game.paused {
            list.rectangle(
                0.0, 0.0, CrtScene.screenWidth, CrtScene.screenHeight, RGBAColor.rgba(0, 0, 0, 0.66))
            let pulse = 0.7 + 0.3 * abs(rustSin(time * 2.5))
            CrtScene.centeredTextShadow(
                list, "PAUSED", y: 142.0, scale: 5.0, color: Palette.phosphorWhite.withAlpha(pulse),
                shadow: Palette.void)
            CrtScene.centeredText(list, "P OR ESC TO RESUME", y: 198.0, scale: 1.0, color: Palette.phosphor)
            CrtScene.centeredText(list, "Q TO QUIT", y: 212.0, scale: 1.0, color: Palette.phosphorDim)
        }
    }

    static func drawAttract(_ list: DrawList, game: Game) {
        list.rectangle(0.0, 44.0, CrtScene.screenWidth, 158.0, RGBAColor.rgba(0, 0, 0, 0.62))
        list.rectangle(0.0, 44.0, CrtScene.screenWidth, 1.0, Palette.phosphor.withAlpha(0.35))
        list.rectangle(0.0, 201.0, CrtScene.screenWidth, 1.0, Palette.phosphor.withAlpha(0.2))

        CrtScene.centeredText(list, "TAITO", y: 54.0, scale: 1.0, color: Palette.phosphor)
        CrtScene.centeredTextShadow(
            list, "SPEED", y: 76.0, scale: 6.0, color: Palette.phosphorWhite,
            shadow: Palette.phosphorDark)
        CrtScene.centeredTextShadow(
            list, "RACE", y: 126.0, scale: 6.0, color: Palette.phosphorWhite,
            shadow: Palette.phosphorDark)
        CrtScene.centeredText(list, "1974", y: 178.0, scale: 1.0, color: Palette.phosphorDim)

        let pulse = 0.62 + 0.38 * abs(rustSin(game.demoClock * 4.0))
        CrtScene.centeredTextShadow(
            list, "PRESS ENTER TO START", y: 224.0, scale: 2.0, color: Palette.cream.withAlpha(pulse),
            shadow: Palette.void)
        CrtScene.centeredText(
            list, "A/D OR ARROWS STEER   W/UP GAS", y: 251.0, scale: 1.0, color: Palette.phosphor)
        CrtScene.centeredText(
            list, "AVOID TRAFFIC - BEAT THE CLOCK", y: 262.0, scale: 1.0, color: Palette.phosphorDim)

        // Rust: `format!("HI SCORE {:06}", game.best)` — six digits, zero padded.
        let best = "HI SCORE " + pad(game.best, width: 6)
        CrtScene.drawPixelText(list, best, x: 8.0, y: 8.0, scale: 1.0, color: Palette.phosphor)
        CrtScene.drawPixelText(
            list, "90 SEC", x: CrtScene.screenWidth - PixelFont.width("90 SEC", 1.0) - 8.0, y: 8.0,
            scale: 1.0, color: Palette.phosphor)
    }

    static func drawCountdown(_ list: DrawList, game: Game) {
        guard let number = game.countdownNumber() else {
            return
        }
        let text = String(number)
        list.rectangle(0.0, 112.0, CrtScene.screenWidth, 96.0, RGBAColor.rgba(0, 0, 0, 0.4))
        CrtScene.centeredText(list, "GET READY", y: 100.0, scale: 1.0, color: Palette.phosphor)
        CrtScene.centeredTextShadow(
            list, text, y: 122.0, scale: 11.0, color: Palette.phosphorWhite,
            shadow: Palette.phosphorDark)
        CrtScene.centeredText(
            list, "THE CLOCK STARTS ON GO", y: 208.0, scale: 1.0, color: Palette.phosphorDim)
        CrtScene.centeredText(list, "HOLD GAS TO LAUNCH", y: 220.0, scale: 1.0, color: Palette.phosphor)
    }

    static func drawRaceNotice(_ list: DrawList, game: Game, time: Float) {
        if let notice = game.notice {
            let alpha = min(max(notice.timer * 2.0, 0.0), 1.0)
            switch notice.text {
            case .go:
                CrtScene.centeredTextShadow(
                    list, "GO!", y: 126.0, scale: 8.0, color: Palette.cream.withAlpha(alpha),
                    shadow: Palette.void)
            case .crash:
                let flash: Float =
                    Int32(rustSaturating: time * 22.0) % 2 == 0 ? 1.0 : 0.55
                CrtScene.centeredTextShadow(
                    list, "CRASH!", y: 132.0, scale: 5.0,
                    color: Palette.phosphorWhite.withAlpha(alpha * flash), shadow: Palette.void)
            case .trackRestarted, .timeExtended:
                let text = notice.text.text
                let width = PixelFont.width(text, 2.0) + 16.0
                list.rectangle(
                    (CrtScene.screenWidth - width) * 0.5, 82.0, width, 24.0,
                    RGBAColor.rgba(0, 8, 2, 0.75))
                list.rectangleLines(
                    (CrtScene.screenWidth - width) * 0.5, 82.0, width, 24.0, thickness: 1.0,
                    Palette.phosphor.withAlpha(0.5))
                CrtScene.centeredText(list, text, y: 91.0, scale: 2.0, color: Palette.cream.withAlpha(alpha))
            }
        }

        // A small speed/gear strip at the top of the tube keeps vital
        // information in the player's field of view without turning the road
        // into a HUD.
        let speed = pad(UInt32(rustSaturating: game.speed), width: 3)
        CrtScene.drawPixelText(
            list, speed, x: 7.0, y: 7.0, scale: 1.0, color: Palette.phosphorWhite)
        CrtScene.drawPixelText(list, "KM/H", x: 27.0, y: 7.0, scale: 1.0, color: Palette.phosphor)
        let time = pad(game.displayTime(), width: 3)
        CrtScene.drawPixelText(
            list, time, x: CrtScene.screenWidth - PixelFont.width(time, 1.0) - 7.0, y: 7.0,
            scale: 1.0, color: Palette.phosphorWhite)
    }

    static func drawGameOver(_ list: DrawList, game: Game, time: Float) {
        list.rectangle(
            0.0, 0.0, CrtScene.screenWidth, CrtScene.screenHeight, RGBAColor.rgba(0, 0, 0, 0.76))
        list.rectangle(12.0, 54.0, CrtScene.screenWidth - 24.0, 246.0, RGBAColor.rgba(0, 9, 3, 0.72))
        list.rectangleLines(
            12.0, 54.0, CrtScene.screenWidth - 24.0, 246.0, thickness: 1.0,
            Palette.phosphor.withAlpha(0.45))

        CrtScene.centeredTextShadow(
            list, "TIME UP", y: 72.0, scale: 5.0, color: Palette.phosphorWhite,
            shadow: Palette.phosphorDark)
        CrtScene.centeredText(list, "FINAL SCORE", y: 132.0, scale: 1.0, color: Palette.phosphor)

        let score = pad(min(game.score, 999_999), width: 6)
        CrtScene.centeredTextShadow(list, score, y: 146.0, scale: 4.0, color: Palette.cream, shadow: Palette.void)

        let stats =
            "PASSED " + pad(min(game.carsPassed, 99), width: 2) + "   TOP "
            + pad(UInt32(rustSaturating: game.topSpeed), width: 3) + " KM/H"
        CrtScene.centeredText(list, stats, y: 190.0, scale: 1.0, color: Palette.phosphor)

        if game.newBest {
            if rustSin(time * 4.0) > -0.15 {
                CrtScene.centeredText(list, "NEW RECORD!", y: 206.0, scale: 2.0, color: Palette.ledAmber)
            }
        } else {
            let best = "BEST " + pad(min(game.best, 999_999), width: 6)
            CrtScene.centeredText(list, best, y: 206.0, scale: 1.0, color: Palette.phosphor)
        }

        CrtScene.centeredText(list, "ENTER  RACE AGAIN", y: 238.0, scale: 2.0, color: Palette.phosphorWhite)
        CrtScene.centeredText(list, "TAITO  1974", y: 272.0, scale: 1.0, color: Palette.phosphor)
    }

    /// Rust's `format!("{:0N}", value)` for an unsigned integer: zero-padded
    /// decimal, *not* truncated (values wider than N print in full), which is
    /// what the Rust formatting macros do.
    static func pad(_ value: UInt32, width: Int) -> String {
        let digits = String(value)
        if digits.count >= width {
            return digits
        }
        return String(repeating: "0", count: width - digits.count) + digits
    }
}
