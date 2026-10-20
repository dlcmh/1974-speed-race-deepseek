import Foundation
import SpeedRace

// Placeholder suite so the runner compiles before the draw-list parity checks
// land. Replaced by DrawListTests.swift in the next step.
let rosterTests: [TestCase] = [
    TestCase("roster::pixel_font_covers_every_string_the_game_draws") {
        let strings = [
            "HI SCORE 000000", "90 SEC", "TAITO", "SPEED", "RACE", "1974",
            "PRESS ENTER TO START", "A/D OR ARROWS STEER   W/UP GAS",
            "AVOID TRAFFIC - BEAT THE CLOCK", "GET READY", "THE CLOCK STARTS ON GO",
            "HOLD GAS TO LAUNCH", "GO!", "CRASH!", "TRACK RESTARTED",
            "TIME EXTENDED +20", "KM/H", "PAUSED", "P OR ESC TO RESUME",
            "Q TO QUIT", "TIME UP", "FINAL SCORE", "NEW RECORD!", "BEST 000000",
            "ENTER  RACE AGAIN", "TAITO  1974", "GAS", "BRAKE", "100 YEN", "12",
            "FREE", "PLAY", "SOUND OFF",
            "STEER  A/D OR ARROWS     GAS  W/UP     BRAKE  S/DOWN",
            "P PAUSE   M MUTE   F FULLSCREEN   Q QUIT",
            "P PAUSE   M UNMUTE   F FULLSCREEN   Q QUIT",
        ]
        for text in strings {
            for character in text where character != " " {
                // The Rust font has no space glyph and `draw_pixel_text` simply
                // advances the cursor for it; only visible glyphs are checked.
                try expect(
                    PixelFont.glyph(character) != nil,
                    "missing glyph for '\(character)' in \"\(text)\"")
            }
        }
    }
]
