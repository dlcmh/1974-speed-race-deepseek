import AppKit
import MetalKit
import SpeedRace

// Speed Race (1974) — Swift + Metal port.
//
// The playable surface. Adopted from the working Pac-Man port
// (docs/METAL-VS-PACMAN.md): `MTKView` supplies the drawable and the render
// pass descriptor, and the view is the first responder for keyboard input.
//
// Frame pipeline, matching src/main.rs:
//   input poll -> game.update -> drain events -> render -> present.

@MainActor
final class GameView: MTKView, MTKViewDelegate {
    private let game: Game
    private let renderer: MetalRenderer
    private let input = Input()
    private let audio = ArcadeAudio()
    private let crt = DrawList(aaScale: 1.0)
    private let cabinet = DrawList(aaScale: 1.0)

    private var startTime = CACurrentMediaTime()
    private var lastFrame = CACurrentMediaTime()
    private var muted: Bool { audio.muted }
    private var fullscreen = false
    private var secondsSinceStart: Float = 0

    init(frame: CGRect, device: MTLDevice) throws {
        game = Game(best: HighScore.load())
        renderer = try MetalRenderer(device: device)
        super.init(frame: frame, device: device)

        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        framebufferOnly = true
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60
        delegate = self
        wantsLayer = true
    }

    required init(coder: NSCoder) { fatalError("not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        input.keyDown(event.keyCode)
    }

    override func keyUp(with event: NSEvent) {
        input.keyUp(event.keyCode)
    }

    override func flagsChanged(with event: NSEvent) {
        // Modifier keys are not gameplay input.
    }

    /// Releases the game when the window loses focus so a held key cannot stick.
    override func resignFirstResponder() -> Bool {
        input.clear()
        return true
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(now - lastFrame, 0.05))
        lastFrame = now
        secondsSinceStart = Float(now - startTime)

        let state = input.poll()

        if state.quit {
            NSApplication.shared.terminate(nil)
            return
        }
        if state.fullscreen {
            fullscreen.toggle()
            window?.toggleFullScreen(nil)
        }
        if state.mute {
            audio.toggleMute()
        }
        if state.pause {
            game.togglePause()
        }
        if state.start && (game.phase == .attract || game.phase == .gameOver) {
            audio.stopEngine()
            game.startRace()
        }

        game.update(controls: state.controls, dt: dt)

        // Event to sound mapping, identical to src/main.rs.
        for event in game.takeEvents() {
            switch event {
            case .countdownBeep: audio.countdown()
            case .go: audio.go()
            case .overtake: audio.pass()
            case .crash:
                audio.stopEngine()
                audio.crash()
            case .extend: audio.extend()
            case .gameOver:
                audio.stopEngine()
                audio.gameOver()
            }
        }

        let engineActive = !game.paused && (game.phase == .countdown || game.phase == .racing)
        audio.syncEngine(
            active: engineActive, speed: game.speed, throttle: game.controls.throttle)

        if game.bestDirty {
            HighScore.save(game.best)
            game.bestDirty = false
        }

        crt.begin()
        CrtScene.draw(crt, game: game, time: secondsSinceStart)
        cabinet.begin()
        Cabinet.draw(cabinet, game: game, muted: muted)

        guard let drawable = view.currentDrawable else { return }
        let size = view.drawableSize
        let scale = min(Float(size.width) / 960, Float(size.height) / 720)
        let width = Float(960) * scale
        let height = Float(720) * scale
        let viewport = CGRect(
            x: CGFloat((Float(size.width) - width) * 0.5),
            y: CGFloat((Float(size.height) - height) * 0.5),
            width: CGFloat(width), height: CGFloat(height))

        do {
            if state.screenshot {
                if let pixels = try renderer.render(
                    crt: crt, cabinet: cabinet, drawable: nil, viewport: nil)
                {
                    Screenshot.save(
                        width: pixels.width, height: pixels.height, pixels: pixels.pixels)
                }
            }
            try renderer.render(
                crt: crt, cabinet: cabinet, drawable: drawable, viewport: viewport)
        } catch {
            NSLog("Speed Race render error: %@", String(describing: error))
        }
    }
}
