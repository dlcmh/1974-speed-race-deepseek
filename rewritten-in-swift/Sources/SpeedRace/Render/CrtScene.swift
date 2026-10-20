import Foundation

// Speed Race (1974) — Swift + Metal port.
//
// PORT OF: the 240 x 360 road scene in src/gfx.rs — `draw_game_screen`,
// `draw_sky`, `draw_road`, `draw_roadside`, `draw_cars`, `draw_traffic_car`,
// `draw_player_car`, `draw_car`, `draw_sparks`, `draw_pixel_text`,
// `draw_text_shadow`, the centring helpers, and `draw_seven_digit` /
// `draw_seven_number`.
//
// The cabinet (960 x 720) lives in Cabinet.swift; this file owns only what is
// seen through the phosphor tube. Function names below are the Rust names so
// a diff of the two renderers can be done side by side.

/// The 240 x 360 CRT scene.
public enum CrtScene {
    public static let screenWidth: Float = 240.0
    public static let screenHeight: Float = 360.0

    /// `draw_game_screen(&game)`.
    public static func draw(_ list: DrawList, game: Game, time: Float) {
        drawSky(list, game: game)
        drawRoad(list, game: game)
        drawRoadside(list, game: game)
        drawCars(list, game: game, time: time)
        drawSparks(list, game: game)
        CrtUI.draw(list, game: game, time: time)
        if game.flash > 0.0 {
            list.rectangle(
                0.0, 0.0, screenWidth, screenHeight,
                Palette.phosphorWhite.withAlpha(game.flash * 0.55))
        }
    }

    // MARK: - Sky

    static func drawSky(_ list: DrawList, game: Game) {
        list.rectangle(0.0, 0.0, screenWidth, screenHeight, Palette.sky)

        // Faint green glow above the horizon, like light bleeding through the
        // smoked glass of an old monitor.
        var i = 0
        while i < 24 {
            let fi = Float(i)
            let y = Road.horizonY - fi * 3.0
            let alpha = 0.007 + (24.0 - fi) * 0.00055
            list.rectangle(0.0, y, screenWidth, 3.0, Palette.phosphorDark.withAlpha(alpha * 8.0))
            i += 1
        }

        // A few slow, distant stars keep the top of the screen alive.
        i = 0
        while i < 8 {
            let fi = Float(i)
            let phase = game.distance * 0.0015 + fi * 1.7
            let x = (rustSin(phase) * 0.5 + 0.5) * screenWidth
            let yRaw = fi * 17.0 + game.distance * 0.01
            let y = 8.0 + yRaw.truncatingRemainder(dividingBy: Road.horizonY - 8.0)
            let twinkle = 0.10 + (rustSin(phase * 2.4) * 0.5 + 0.5) * 0.25
            list.rectangle(x, y, 1.0, 1.0, Palette.phosphor.withAlpha(twinkle))
            i += 1
        }

        list.rectangle(0.0, Road.horizonY - 1.0, screenWidth, 2.0, Palette.phosphor.withAlpha(0.16))
    }

    // MARK: - Road

    static let roadSteps = 74

    static func drawRoad(_ list: DrawList, game: Game) {
        let distance = game.distance
        let steps = roadSteps

        for i in stride(from: steps - 1, through: 0, by: -1) {
            let t0 = Float(i) / Float(steps)
            let t1 = Float(i + 1) / Float(steps)
            // Quadratic spacing puts most polygons near the camera, where they
            // matter for the sensation of speed.
            let z0 = Road.viewDistance * t0 * t0
            let z1 = Road.viewDistance * t1 * t1
            let p0 = Road.project(z0)
            let p1 = Road.project(z1)
            if p0.y - p1.y < 0.02 {
                continue
            }

            let center0 = screenWidth * 0.5 + Road.screenOffset(distance: distance, z: z0) * p0.scale
            let center1 = screenWidth * 0.5 + Road.screenOffset(distance: distance, z: z1) * p1.scale
            let half0 = Road.roadHalfWidth * p0.scale
            let half1 = Road.roadHalfWidth * p1.scale

            // Rust: `((distance + z0) / 58.0).floor() as i32`, then `& 1`.
            let stripe = Int32(rustSaturating: ((distance + z0) / 58.0).rounded(.down)) & 1
            let asphalt = stripe == 0 ? Palette.roadA : Palette.roadB

            // Black/green verge behind the road.
            let verge = stripe == 0 ? RGBAColor.rgb(2, 13, 7) : RGBAColor.rgb(2, 10, 6)
            list.rectangle(0.0, p1.y, screenWidth, p0.y - p1.y + 0.4, verge)

            let l0 = center0 - half0
            let r0 = center0 + half0
            let l1 = center1 - half1
            let r1 = center1 + half1
            list.quad(
                Point2(l0, p0.y), Point2(r0, p0.y), Point2(r1, p1.y), Point2(l1, p1.y), asphalt)

            // Hot shoulders: two thin tapered strips.
            let shoulder0 = max(2.2 * p0.scale, 0.5)
            let shoulder1 = max(2.2 * p1.scale, 0.35)
            let edgeColor = stripe == 0 ? Palette.roadEdge : Palette.roadEdgeHot
            list.quad(
                Point2(l0, p0.y), Point2(l0 + shoulder0, p0.y),
                Point2(l1 + shoulder1, p1.y), Point2(l1, p1.y), edgeColor)
            list.quad(
                Point2(r0 - shoulder0, p0.y), Point2(r0, p0.y),
                Point2(r1, p1.y), Point2(r1 - shoulder1, p1.y), edgeColor)

            // Broken lane dividers, three to make a four-lane highway.
            // Rust: `(distance + z0).rem_euclid(112.0)` — never negative.
            let dashPhase = (distance + z0).truncatingRemainder(dividingBy: 112.0)
            let dashNormalised = dashPhase < 0 ? dashPhase + 112.0 : dashPhase
            if dashNormalised < 52.0 {
                for divider: Float in [0.25, 0.5, 0.75] {
                    let lx0 = l0 + (r0 - l0) * divider
                    let lx1 = l1 + (r1 - l1) * divider
                    let width0 = max(1.15 * p0.scale, 0.35)
                    let width1 = max(1.15 * p1.scale, 0.25)
                    list.quad(
                        Point2(lx0 - width0, p0.y), Point2(lx0 + width0, p0.y),
                        Point2(lx1 + width1, p1.y), Point2(lx1 - width1, p1.y), Palette.laneLine)
                }
            }
        }

        // A soft vanishing line where the asphalt meets the night.
        list.rectangle(0.0, Road.horizonY - 1.0, screenWidth, 1.0, Palette.phosphor.withAlpha(0.25))
    }

    // MARK: - Roadside

    static func drawRoadside(_ list: DrawList, game: Game) {
        let spacing: Float = 155.0
        let start = (game.distance / spacing).rounded(.down) * spacing

        for i in 0..<14 {
            let world = start + Float(i) * spacing
            let z = world - game.distance
            if !(z >= 20.0 && z < Road.viewDistance * 0.92) {
                continue
            }
            let projection = Road.project(z)
            let scale = projection.scale
            let center = screenWidth * 0.5 + Road.screenOffset(distance: game.distance, z: z) * scale
            let half = Road.roadHalfWidth * scale
            let postH = 2.0 + 13.0 * scale
            let postW = max(1.5 * scale, 0.6)
            let dim = Palette.phosphorDim.withAlpha(min(0.25 + scale * 0.7, 0.9))
            let hot = Palette.phosphor.withAlpha(min(0.45 + scale * 0.55, 1.0))

            for side: Float in [-1.0, 1.0] {
                let x = center + side * (half + 5.0 * scale)
                list.rectangle(x, projection.y - postH, postW, postH, dim)
                list.rectangle(
                    x - postW * 0.6, projection.y - postH, postW * 2.2,
                    max(0.8 * scale, 0.5), hot)
            }
        }
    }

    // MARK: - Cars

    enum Actor {
        case player
        case traffic(Int)
    }

    static func drawCars(_ list: DrawList, game: Game, time: Float) {
        if game.phase == .gameOver {
            return
        }

        var actors: [(Float, Actor)] = []
        actors.reserveCapacity(game.traffic.count + 1)
        for (index, car) in game.traffic.enumerated() {
            if car.z > Road.viewDistance + 50.0 || car.z < -80.0 {
                continue
            }
            actors.append((car.z, .traffic(index)))
        }
        actors.append((Game.playerZ, .player))
        // Rust: `sort_by(|a, b| b.0.total_cmp(&a.0))` — far to near.
        actors.sort { $0.0 > $1.0 }

        for (_, actor) in actors {
            switch actor {
            case .traffic(let index):
                drawTrafficCar(list, game: game, index: index)
            case .player:
                drawPlayerCar(list, game: game, time: time)
            }
        }
    }

    static func drawTrafficCar(_ list: DrawList, game: Game, index: Int) {
        let car = game.traffic[index]
        let projection = Road.project(car.z)
        if projection.scale < 0.035 {
            return
        }
        let screenX =
            screenWidth * 0.5
            + Road.screenOffset(distance: game.distance, z: car.z) * projection.scale
            + car.lateral * Road.roadHalfWidth * projection.scale
        let bases: (Float, Float)
        switch car.kind {
        case 0: bases = (21.0, 27.0)
        case 1: bases = (23.0, 30.0)
        default: bases = (24.0, 33.0)
        }
        let scale = projection.scale
        let width = bases.0 * scale
        let height = bases.1 * scale
        let body: RGBAColor
        switch car.variant {
        case 0: body = Palette.carMid
        case 1: body = Palette.carWhite
        default: body = RGBAColor.rgb(72, 177, 102)
        }
        let wobble = rustSin(car.wobblePhase) * 0.6 * scale
        drawCar(
            list, x: screenX + wobble, bottomY: projection.y + 1.0, width: width, height: height,
            body: body, player: false, kind: car.kind, angle: 0.0, lean: 0.0)
    }

    static func drawPlayerCar(_ list: DrawList, game: Game, time: Float) {
        let projection = Road.project(Game.playerZ)
        let x = screenWidth * 0.5 + game.lateral * Road.roadHalfWidth * projection.scale
        // Rust: `(get_time() * 18.0) as i32 % 2 == 0` while invulnerable.
        let blink =
            game.invulnerable > 0.0 && Int32(rustSaturating: time * 18.0) % 2 == 0
        if blink {
            return
        }

        var angle: Float = 0.0
        var lift: Float = 0.0
        if game.phase == .crashed {
            // Rust: `1.0 - (crash_timer / 1.45).clamp(0.0, 1.0)`.
            let progress = 1.0 - min(max(game.crashTimer / 1.45, 0.0), 1.0)
            angle = progress * Float.rustTau * 1.35
            lift = min(progress * 12.0, 8.0)
        }

        drawCar(
            list, x: x, bottomY: projection.y + 2.0 - lift, width: 28.0, height: 39.0,
            body: Palette.carWhite, player: true,
            kind: game.phase == .crashed ? 1 : 0, angle: angle, lean: game.lean)
    }

    /// `draw_car` — every panel is a `draw_rectangle_ex` rotated about the
    /// car's centre, with the same part offsets as Rust.
    static func drawCar(
        _ list: DrawList, x: Float, bottomY: Float, width: Float, height: Float,
        body: RGBAColor, player: Bool, kind: UInt8, angle: Float, lean: Float
    ) {
        if width < 4.0 || height < 5.0 {
            list.rectangle(x - width * 0.5, bottomY - height, width, height, body)
            return
        }

        let cx = x
        let cy = bottomY - height * 0.5
        let w = width
        let h = height

        // Ground shadow stays flat while the car spins.
        list.ellipse(
            cx, bottomY - h * 0.02, w * 0.50, h * 0.08, rotation: 0.0, RGBAColor.rgba(0, 0, 0, 0.5))

        let sinAngle = rustSin(angle)
        let cosAngle = rustCos(angle)
        func part(_ dx: Float, _ dy: Float, _ pw: Float, _ ph: Float, _ color: RGBAColor) {
            let px = cx + dx * cosAngle - dy * sinAngle
            let py = cy + dx * sinAngle + dy * cosAngle
            list.rotatedRectangle(
                centerX: px, centerY: py, width: pw, height: ph, rotation: angle, color)
        }

        let leanPx = lean * w * 0.06

        // Wheels and a dark silhouette.
        part(-w * 0.42, h * 0.16, w * 0.17, h * 0.31, Palette.tire)
        part(w * 0.42, h * 0.16, w * 0.17, h * 0.31, Palette.tire)
        part(0.0, h * 0.03, w * 0.96, h * 0.78, RGBAColor.rgb(1, 10, 4))

        // Main body.
        part(0.0, h * 0.10, w * 0.88, h * 0.62, body)
        part(0.0, h * 0.02, w * 0.79, h * 0.42, body)

        // Cabin, rear glass and roof.
        let roofW = kind == 2 ? w * 0.72 : w * 0.61
        part(leanPx, -h * 0.20, roofW, h * 0.28, body)
        part(leanPx, -h * 0.22, roofW * 0.76, h * 0.14, Palette.carGlass)
        part(leanPx, -h * 0.30, roofW * 0.92, h * 0.045, Palette.carWhite)

        if kind == 2 {
            // Box van: tall rear doors and a central seam.
            part(0.0, h * 0.10, w * 0.74, h * 0.42, Palette.carWhite.withAlpha(0.30))
            part(0.0, h * 0.10, w * 0.045, h * 0.42, Palette.carDark)
        } else {
            // Boot lid panel.
            part(0.0, h * 0.20, w * 0.68, h * 0.17, Palette.carDark.withAlpha(0.55))
        }

        // Bumper and rear lamps.
        part(0.0, h * 0.40, w * 0.94, h * 0.045, RGBAColor.rgb(2, 18, 8))
        part(-w * 0.29, h * 0.29, w * 0.17, h * 0.055, Palette.phosphorWhite)
        part(w * 0.29, h * 0.29, w * 0.17, h * 0.055, Palette.phosphorWhite)

        if player {
            // Racing roundel and a spoiler give the hero car a period silhouette.
            part(0.0, -h * 0.35, w * 0.77, h * 0.045, body)
            part(-w * 0.37, -h * 0.33, w * 0.05, h * 0.10, Palette.carDark)
            part(w * 0.37, -h * 0.33, w * 0.05, h * 0.10, Palette.carDark)
            part(0.0, h * 0.14, w * 0.28, h * 0.12, Palette.carGlass.withAlpha(0.55))
            list.circle(cx + leanPx, cy + h * 0.14, max(w * 0.055, 0.8), Palette.phosphorWhite)
        } else {
            // White flashes on the corners help distant traffic read.
            part(-w * 0.32, -h * 0.12, w * 0.10, h * 0.12, Palette.carWhite.withAlpha(0.5))
            part(w * 0.32, -h * 0.12, w * 0.10, h * 0.12, Palette.carWhite.withAlpha(0.5))
        }
    }

    // MARK: - Sparks

    static func drawSparks(_ list: DrawList, game: Game) {
        for spark in game.sparks {
            let alpha = min(max(spark.life / spark.maxLife, 0.0), 1.0)
            let size = max(spark.size * (0.35 + alpha), 0.7)
            list.rectangle(
                spark.x - size * 0.5, spark.y - size * 0.5, size, size,
                Palette.spark.withAlpha(alpha))
        }
    }

    // MARK: - Text

    /// `draw_pixel_text` — run-length rasteriser over the 5 x 7 glyph rows.
    public static func drawPixelText(
        _ list: DrawList, _ text: String, x: Float, y: Float, scale: Float, color: RGBAColor
    ) {
        var cursor = x
        for character in text {
            if let rows = PixelFont.glyph(character) {
                for (row, bits) in rows.enumerated() {
                    var col = 0
                    while col < 5 {
                        let bit: UInt8 = 1 << UInt8(4 - col)
                        if bits & bit == 0 {
                            col += 1
                            continue
                        }
                        let start = col
                        while col < 5 && bits & (1 << UInt8(4 - col)) != 0 {
                            col += 1
                        }
                        list.rectangle(
                            cursor + Float(start) * scale, y + Float(row) * scale,
                            Float(col - start) * scale, scale, color)
                    }
                }
            }
            cursor += 6.0 * scale
        }
    }

    static func drawTextShadow(
        _ list: DrawList, _ text: String, x: Float, y: Float, scale: Float, color: RGBAColor,
        shadow: RGBAColor
    ) {
        drawPixelText(list, text, x: x + scale, y: y + scale, scale: scale, color: shadow)
        drawPixelText(list, text, x: x, y: y, scale: scale, color: color)
    }

    static func centeredText(
        _ list: DrawList, _ text: String, y: Float, scale: Float, color: RGBAColor
    ) {
        let x = (screenWidth - PixelFont.width(text, scale)) * 0.5
        drawPixelText(list, text, x: x, y: y, scale: scale, color: color)
    }

    static func centeredTextShadow(
        _ list: DrawList, _ text: String, y: Float, scale: Float, color: RGBAColor,
        shadow: RGBAColor
    ) {
        let x = (screenWidth - PixelFont.width(text, scale)) * 0.5
        drawTextShadow(list, text, x: x, y: y, scale: scale, color: color, shadow: shadow)
    }
}
