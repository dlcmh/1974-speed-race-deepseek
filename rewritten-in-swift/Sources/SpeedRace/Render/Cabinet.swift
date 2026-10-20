import Foundation

// Speed Race (1974) — Swift + Metal port.
//
// PORT OF: the 960 x 720 cabinet section of src/gfx.rs — `draw_cabinet`,
// `draw_wall`, `draw_cabinet_chassis`, `draw_marquee`, `draw_left_panel`,
// `draw_speedometer`, `draw_side_car`, `draw_right_panel`, `draw_led_module`,
// `draw_screen` and `draw_control_deck`.
//
// The cabinet is composed at a fixed 960 x 720 virtual resolution (a 4:3
// canvas) and then letterboxed into the window by the Metal renderer. Keeping
// this file pixel-for-pixel faithful to gfx.rs means the Rust screenshots in
// docs/ are usable as visual references.

public enum Cabinet {
    public static let canvasWidth: Float = 960.0
    public static let canvasHeight: Float = 720.0

    // The game screen's position and scale on the 960 x 720 virtual cabinet.
    public static let crtX: Float = 300.0
    public static let crtY: Float = 110.0
    public static let crtScale: Float = 1.5

    /// `draw_cabinet(&game, &target, muted)`.
    public static func draw(_ list: DrawList, game: Game, muted: Bool) {
        drawWall(list)
        drawChassis(list)
        drawMarquee(list)
        drawLeftPanel(list, game: game)
        drawRightPanel(list, game: game)
        drawScreen(list, muted: muted)
        drawControlDeck(list, muted: muted)
    }

    // MARK: - Wall and chassis

    static func drawWall(_ list: DrawList) {
        list.rectangle(0.0, 0.0, canvasWidth, canvasHeight, Palette.wall)
        for i in 0..<18 {
            let x = Float(i) * 64.0 - 60.0
            list.line(x, 0.0, x + 190.0, canvasHeight, 1.0, Palette.wallLine)
        }
        list.rectangle(0.0, 648.0, canvasWidth, 72.0, RGBAColor.rgb(4, 4, 4))
    }

    static func drawChassis(_ list: DrawList) {
        // Drop shadow and the main plywood shell.
        list.rectangle(154.0, 26.0, 680.0, 704.0, RGBAColor.rgba(0, 0, 0, 0.65))
        list.rectangle(140.0, 16.0, 680.0, 700.0, Palette.cabinetDark)
        list.rectangle(146.0, 22.0, 668.0, 688.0, RGBAColor.rgb(31, 25, 20))
        list.rectangleLines(140.0, 16.0, 680.0, 700.0, thickness: 2.0, RGBAColor.rgb(60, 44, 30))

        // Orange side wings, inspired by the original upright's warm laminate.
        for x: Float in [146.0, 684.0] {
            list.rectangle(x, 104.0, 130.0, 552.0, Palette.orangeDark)
            list.rectangle(x + 3.0, 104.0, 124.0, 548.0, Palette.orange)
            list.rectangle(x + 3.0, 104.0, 124.0, 24.0, Palette.orangeLight)
        }

        // Central black face around the monitor.
        list.rectangle(280.0, 96.0, 400.0, 568.0, Palette.cabinetBlack)
        list.rectangle(286.0, 102.0, 388.0, 556.0, RGBAColor.rgb(8, 8, 7))
        list.rectangleLines(280.0, 96.0, 400.0, 568.0, thickness: 2.0, RGBAColor.rgb(46, 33, 23))

        // Bezel lip.
        list.rectangle(294.0, 104.0, 372.0, 552.0, RGBAColor.rgb(2, 3, 2))
        list.rectangleLines(294.0, 104.0, 372.0, 552.0, thickness: 1.0, RGBAColor.rgb(74, 55, 35))

        // Warm light spill from the tube.
        list.rectangle(292.0, 102.0, 376.0, 556.0, RGBAColor.rgba(72, 255, 130, 0.025))

        // Screws.
        for (x, y): (Float, Float) in [
            (298.0, 108.0), (662.0, 108.0), (298.0, 652.0), (662.0, 652.0),
        ] {
            list.circle(x, y, 3.0, RGBAColor.rgb(44, 38, 29))
            list.circle(x, y, 1.2, RGBAColor.rgb(90, 77, 54))
        }
    }

    static func panel(
        _ list: DrawList, _ x: Float, _ y: Float, _ w: Float, _ h: Float, fill: RGBAColor,
        border: RGBAColor
    ) {
        list.rectangle(x, y, w, h, fill)
        list.rectangleLines(x, y, w, h, thickness: 1.0, border)
    }

    static func drawMarquee(_ list: DrawList) {
        let x: Float = 208.0
        let y: Float = 26.0
        let w: Float = 544.0
        let h: Float = 64.0

        list.rectangle(x, y, w, h, RGBAColor.rgba(0, 0, 0, 0.55))
        list.rectangle(x + 3.0, y + 3.0, w - 6.0, h - 6.0, RGBAColor.rgb(5, 10, 7))
        list.rectangleLines(x, y, w, h, thickness: 2.0, Palette.orangeDark)
        list.rectangleLines(
            x + 5.0, y + 5.0, w - 10.0, h - 10.0, thickness: 1.0, RGBAColor.rgb(48, 113, 65))

        // Taito badge.
        panel(
            list, x + 14.0, y + 15.0, 72.0, 34.0, fill: RGBAColor.rgb(10, 67, 30),
            border: RGBAColor.rgb(108, 182, 116))
        CrtScene.drawPixelText(
            list, "TAITO", x: x + 20.0, y: y + 26.0, scale: 2.0, color: Palette.phosphorWhite)

        // 1974 badge.
        panel(
            list, x + w - 96.0, y + 15.0, 82.0, 34.0, fill: RGBAColor.rgb(52, 24, 8),
            border: Palette.orangeLight)
        CrtScene.drawPixelText(
            list, "1974", x: x + w - 83.0, y: y + 27.0, scale: 2.0, color: Palette.cream)

        // Marquee wordmark.
        let title = "SPEED RACE"
        let scale: Float = 4.0
        let titleX = x + (w - PixelFont.width(title, scale)) * 0.5
        CrtScene.drawTextShadow(
            list, title, x: titleX, y: y + 18.0, scale: scale, color: Palette.cream,
            shadow: Palette.orangeDark)
        list.rectangle(titleX, y + 51.0, PixelFont.width(title, scale), 2.0, Palette.orange)
    }

    // MARK: - Left panel

    static func drawLeftPanel(_ list: DrawList, game: Game) {
        let x: Float = 152.0
        let y: Float = 112.0

        // Period side art: a diagonal speed flash behind the instruments.
        for i in 0..<4 {
            let offset = Float(i) * 18.0
            list.line(
                x + 8.0, y + 462.0 + offset, x + 112.0, y + 402.0 + offset, 2.0,
                RGBAColor.rgba(70, 25, 7, 0.4))
        }

        // Taito badge.
        panel(
            list, x + 8.0, y + 8.0, 76.0, 28.0, fill: RGBAColor.rgb(8, 57, 26),
            border: RGBAColor.rgb(83, 154, 88))
        CrtScene.drawPixelText(
            list, "TAITO", x: x + 14.0, y: y + 18.0, scale: 1.5, color: Palette.phosphorWhite)

        CrtScene.drawPixelText(
            list, "SPEED", x: x + 38.0, y: y + 46.0, scale: 2.0, color: Palette.cream)
        CrtScene.drawPixelText(
            list, "RACE", x: x + 44.0, y: y + 66.0, scale: 2.0, color: Palette.cream)
        list.rectangle(x + 30.0, y + 86.0, 70.0, 1.0, Palette.orangeDark)

        // Analog speedometer.
        drawSpeedometer(
            list, cx: x + 64.0, cy: y + 158.0, radius: 48.0, speed: game.speed,
            throttle: game.controls.throttle)

        // Pedal lamps.
        panel(
            list, x + 10.0, y + 250.0, 108.0, 58.0, fill: RGBAColor.rgb(25, 11, 5),
            border: Palette.orangeDark)
        CrtScene.drawPixelText(
            list, "GAS", x: x + 18.0, y: y + 260.0, scale: 1.5, color: Palette.cream)
        CrtScene.drawPixelText(
            list, "BRAKE", x: x + 18.0, y: y + 282.0, scale: 1.5, color: Palette.cream)
        let gasOn = game.controls.throttle > 0.15
        let brakeOn = game.controls.brake > 0.15
        list.circle(
            x + 102.0, y + 265.0, 5.0, gasOn ? Palette.ledGreen : RGBAColor.rgb(12, 38, 21))
        list.circle(
            x + 102.0, y + 287.0, 5.0, brakeOn ? Palette.ledAmber : RGBAColor.rgb(42, 31, 10))
        if gasOn {
            list.circle(x + 102.0, y + 265.0, 8.0, RGBAColor.rgba(91, 255, 132, 0.14))
        }

        // Checkered racing strip.
        let checkY = y + 326.0
        for row in 0..<2 {
            for column in 0..<8 {
                let color = (row + column) % 2 == 0 ? Palette.cream : RGBAColor.rgb(37, 24, 15)
                list.rectangle(
                    x + 10.0 + Float(column) * 13.0, checkY + Float(row) * 12.0, 13.0, 12.0, color)
            }
        }

        // Stylised #12 side profile.
        drawSideCar(list, cx: x + 64.0, y: y + 410.0)

        CrtScene.drawPixelText(
            list, "100 YEN", x: x + 30.0, y: y + 512.0, scale: 1.0,
            color: Palette.cream.withAlpha(0.7))
    }

    static func drawSpeedometer(
        _ list: DrawList, cx: Float, cy: Float, radius: Float, speed: Float, throttle: Float
    ) {
        list.circle(cx, cy, radius + 5.0, RGBAColor.rgb(58, 31, 14))
        list.circle(cx, cy, radius, RGBAColor.rgb(9, 21, 12))
        list.circleLines(cx, cy, radius, 2.0, Palette.cream)
        list.circleLines(cx, cy, radius - 5.0, 1.0, RGBAColor.rgb(50, 111, 64))

        let startAngle = Float(135.0) * Float.pi / 180.0
        let sweep = Float(270.0) * Float.pi / 180.0
        for tick in 0...12 {
            let angle = startAngle + sweep * Float(tick) / 12.0
            let major = tick % 2 == 0
            let inner = major ? radius - 13.0 : radius - 9.0
            let outer = radius - 5.0
            let sinA = rustSin(angle)
            let cosA = rustCos(angle)
            list.line(
                cx + cosA * inner, cy + sinA * inner, cx + cosA * outer, cy + sinA * outer,
                major ? 2.0 : 1.0, major ? Palette.phosphorWhite : Palette.phosphorDim)
        }

        let ratio = min(max(speed / Game.maxSpeed, 0.0), 1.0)
        let needleAngle = startAngle + sweep * ratio
        let sinA = rustSin(needleAngle)
        let cosA = rustCos(needleAngle)
        list.line(
            cx, cy, cx + cosA * (radius - 14.0), cy + sinA * (radius - 14.0), 3.0,
            RGBAColor.rgb(92, 31, 8))
        list.line(
            cx, cy, cx + cosA * (radius - 15.0), cy + sinA * (radius - 15.0), 1.4, Palette.cream)
        list.circle(cx, cy, 4.0, Palette.cream)
        list.circle(cx, cy, 2.0, Palette.orangeDark)

        let speedText = CrtUI.pad(UInt32(rustSaturating: speed), width: 3)
        let x = cx - PixelFont.width(speedText, 2.0) * 0.5
        CrtScene.drawPixelText(
            list, speedText, x: x, y: cy + radius + 11.0, scale: 2.0, color: Palette.phosphorWhite)
        CrtScene.drawPixelText(
            list, "KM/H", x: cx - PixelFont.width("KM/H", 1.0) * 0.5, y: cy + radius + 30.0,
            scale: 1.0, color: Palette.phosphorDim)

        if throttle > 0.1 {
            list.rectangle(cx - 14.0, cy - 12.0, 28.0, 3.0, RGBAColor.rgba(91, 255, 132, 0.18))
        }
    }

    static func drawSideCar(_ list: DrawList, cx: Float, y: Float) {
        // Wheels.
        list.circle(cx - 30.0, y + 19.0, 12.0, RGBAColor.rgb(13, 10, 8))
        list.circle(cx + 32.0, y + 19.0, 12.0, RGBAColor.rgb(13, 10, 8))
        list.circle(cx - 30.0, y + 19.0, 5.0, RGBAColor.rgb(83, 66, 45))
        list.circle(cx + 32.0, y + 19.0, 5.0, RGBAColor.rgb(83, 66, 45))

        // Low, long 1970s racer.
        list.rectangle(cx - 48.0, y - 2.0, 96.0, 17.0, Palette.cream)
        list.rectangle(cx - 31.0, y - 14.0, 43.0, 15.0, Palette.cream)
        list.rectangle(cx - 25.0, y - 11.0, 25.0, 9.0, RGBAColor.rgb(34, 82, 51))
        list.rectangle(cx - 48.0, y + 4.0, 96.0, 5.0, Palette.orangeDark)
        list.rectangle(cx - 51.0, y + 10.0, 9.0, 5.0, RGBAColor.rgb(24, 16, 11))
        list.rectangle(cx + 43.0, y + 10.0, 10.0, 5.0, RGBAColor.rgb(24, 16, 11))
        list.circle(cx + 6.0, y + 4.0, 7.0, RGBAColor.rgb(245, 241, 221))
        CrtScene.drawPixelText(
            list, "12", x: cx - 1.0, y: y, scale: 1.0, color: RGBAColor.rgb(29, 33, 26))
    }

    // MARK: - Right panel (LED scoreboard)

    static func drawRightPanel(_ list: DrawList, game: Game) {
        let x: Float = 690.0
        let y: Float = 122.0
        let w: Float = 112.0
        let h: Float = 362.0

        list.rectangle(x - 5.0, y - 5.0, w + 10.0, h + 10.0, Palette.orangeDark)
        list.rectangle(x, y, w, h, RGBAColor.rgb(5, 8, 5))
        list.rectangleLines(x, y, w, h, thickness: 2.0, RGBAColor.rgb(12, 12, 8))
        list.rectangleLines(
            x + 5.0, y + 5.0, w - 10.0, h - 10.0, thickness: 1.0, RGBAColor.rgb(70, 54, 31))

        drawLedModule(
            list, x: x + 8.0, y: y + 10.0, w: w - 16.0, h: 58.0, label: "SCORE", value: game.score,
            digits: 6, digitW: 12.0, digitH: 22.0, thickness: 2.0)
        drawLedModule(
            list, x: x + 8.0, y: y + 78.0, w: w - 16.0, h: 77.0, label: "TIME",
            value: game.displayTime(), digits: 3, digitW: 20.0, digitH: 30.0, thickness: 3.0)
        drawLedModule(
            list, x: x + 8.0, y: y + 165.0, w: w - 16.0, h: 59.0, label: "EXTEND",
            value: game.nextExtend, digits: 6, digitW: 10.0, digitH: 16.0, thickness: 1.6)
        drawLedModule(
            list, x: x + 8.0, y: y + 234.0, w: w - 16.0, h: 58.0, label: "HI SCORE",
            value: game.best,
            digits: 6, digitW: 10.0, digitH: 16.0, thickness: 1.6)

        list.rectangle(x + 8.0, y + 303.0, w - 16.0, 1.0, RGBAColor.rgb(66, 49, 27))
        CrtScene.drawPixelText(
            list, "TAITO", x: x + 35.0, y: y + 317.0, scale: 1.5,
            color: Palette.cream.withAlpha(0.75))
        CrtScene.drawPixelText(
            list, "1974", x: x + 39.0, y: y + 336.0, scale: 1.0, color: Palette.cream.withAlpha(0.4)
        )

        // Lower side art and coin door.
        let cy = y + 400.0
        list.rectangle(x + 8.0, cy, w - 16.0, 80.0, RGBAColor.rgb(38, 16, 7))
        list.rectangleLines(x + 8.0, cy, w - 16.0, 80.0, thickness: 1.0, Palette.orangeLight)
        CrtScene.drawPixelText(
            list, "FREE", x: x + 36.0, y: cy + 12.0, scale: 1.5, color: Palette.cream)
        CrtScene.drawPixelText(
            list, "PLAY", x: x + 36.0, y: cy + 28.0, scale: 1.5, color: Palette.cream)
        list.rectangle(x + 32.0, cy + 50.0, 48.0, 7.0, RGBAColor.rgb(9, 8, 6))
        list.rectangle(x + 35.0, cy + 52.0, 42.0, 2.0, RGBAColor.rgb(110, 83, 46))
        list.circle(x + 56.0, cy + 68.0, 3.0, Palette.ledGreen)
    }

    static func drawLedModule(
        _ list: DrawList, x: Float, y: Float, w: Float, h: Float, label: String, value: UInt32,
        digits: Int, digitW: Float, digitH: Float, thickness: Float
    ) {
        list.rectangle(x, y, w, h, RGBAColor.rgb(2, 10, 5))
        list.rectangleLines(x, y, w, h, thickness: 1.0, RGBAColor.rgb(46, 66, 30))

        // Yellow label strip, like the original cabinet's scoreboard.
        list.rectangle(x + 2.0, y + 2.0, w - 4.0, 15.0, RGBAColor.rgb(216, 160, 48))
        list.rectangle(x + 2.0, y + 2.0, w - 4.0, 2.0, RGBAColor.rgb(255, 220, 123))
        CrtScene.drawPixelText(
            list, label, x: x + 5.0, y: y + 6.0, scale: 1.0, color: RGBAColor.rgb(22, 24, 8))

        // Rust: `(w - 8.0 - digit_w * digits) / max(digits - 1, 1) as f32`;
        // `max(total, ...)`-style guards keep a one-digit module sane.
        let gaps = Float(max(digits - 1, 1))
        let gap = (w - 8.0 - digitW * Float(digits)) / gaps
        let total = Float(digits) * digitW + Float(digits - 1) * gap
        let startX = x + (w - total) * 0.5
        let digitY = y + 23.0 + (h - 28.0 - digitH) * 0.35
        SevenSegment.drawNumber(
            list, value: value, digits: digits, x: startX, y: digitY, digitWidth: digitW,
            digitHeight: digitH, thickness: thickness, gap: gap, color: Palette.ledGreen)
    }

    // MARK: - CRT bezel and glass

    static func drawScreen(_ list: DrawList, muted: Bool) {
        let crtWidth = CrtScene.screenWidth * crtScale
        let crtHeight = CrtScene.screenHeight * crtScale

        // Green halo spilling from the phosphor.
        list.rectangle(crtX - 12.0, crtY - 12.0, 384.0, 564.0, RGBAColor.rgba(48, 220, 96, 0.035))
        list.rectangle(crtX - 6.0, crtY - 6.0, 372.0, 552.0, RGBAColor.rgba(55, 255, 110, 0.05))
        list.rectangle(crtX - 2.0, crtY - 2.0, 364.0, 544.0, RGBAColor.rgba(100, 255, 150, 0.09))

        // The Rust build draws the render-target texture with `flip_y: true`.
        // Here the offscreen texture is sampled upright, so no flip appears in
        // the draw list (docs/DECISIONS.md P-0006).
        list.texture(x: crtX, y: crtY, width: crtWidth, height: crtHeight)

        // Scanlines and a slight tube vignette.
        var y = crtY + 1.0
        while y < crtY + crtHeight {
            list.rectangle(crtX, y, crtWidth, 1.0, RGBAColor.rgba(0, 0, 0, 0.18))
            y += 3.0
        }
        for i in 0..<12 {
            let a = 0.012 + Float(i) * 0.005
            list.rectangle(crtX, crtY + Float(i), crtWidth, 1.0, RGBAColor.rgba(0, 0, 0, a * 4.0))
            list.rectangle(
                crtX, crtY + crtHeight - Float(i), crtWidth, 1.0, RGBAColor.rgba(0, 0, 0, a * 4.0))
            list.rectangle(crtX + Float(i), crtY, 1.0, crtHeight, RGBAColor.rgba(0, 0, 0, a * 3.0))
            list.rectangle(
                crtX + crtWidth - Float(i), crtY, 1.0, crtHeight, RGBAColor.rgba(0, 0, 0, a * 3.0))
        }

        // A restrained sweep of reflection across the glass.
        list.quad(
            Point2(crtX + 185.0, crtY), Point2(crtX + 250.0, crtY),
            Point2(crtX + 115.0, crtY + crtHeight), Point2(crtX + 50.0, crtY + crtHeight),
            RGBAColor.rgba(220, 255, 230, 0.018))

        if muted {
            let label = "SOUND OFF"
            let w = PixelFont.width(label, 1.0) + 8.0
            list.rectangle(
                crtX + crtWidth - w - 8.0, crtY + 8.0, w, 14.0, RGBAColor.rgba(0, 0, 0, 0.7))
            CrtScene.drawPixelText(
                list, label, x: crtX + crtWidth - w - 4.0, y: crtY + 12.0, scale: 1.0,
                color: Palette.phosphorDim)
        }

        // Tiny title plaque under the monitor.
        list.rectangle(crtX + 100.0, crtY + crtHeight + 7.0, 160.0, 1.0, Palette.orangeDark)
    }

    // MARK: - Control deck

    static func drawControlDeck(_ list: DrawList, muted: Bool) {
        let x: Float = 146.0
        let y: Float = 660.0
        let w: Float = 668.0
        let h: Float = 48.0
        list.rectangle(x, y, w, h, RGBAColor.rgb(16, 13, 10))
        list.rectangleLines(x, y, w, h, thickness: 2.0, RGBAColor.rgb(66, 44, 26))
        list.rectangle(x + 5.0, y + 5.0, w - 10.0, 1.0, Palette.orangeDark)

        let lineOne = "STEER  A/D OR ARROWS     GAS  W/UP     BRAKE  S/DOWN"
        let lineTwo =
            muted
            ? "P PAUSE   M UNMUTE   F FULLSCREEN   Q QUIT"
            : "P PAUSE   M MUTE   F FULLSCREEN   Q QUIT"
        CrtScene.drawPixelText(
            list, lineOne, x: x + (w - PixelFont.width(lineOne, 2.0)) * 0.5, y: y + 10.0,
            scale: 2.0,
            color: Palette.cream)
        CrtScene.drawPixelText(
            list, lineTwo, x: x + (w - PixelFont.width(lineTwo, 1.5)) * 0.5, y: y + 31.0,
            scale: 1.5,
            color: Palette.cream.withAlpha(0.55))
    }
}
