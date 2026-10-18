mod audio;
mod game;
mod gfx;
mod input;
mod rng;
mod road;

use std::fs;
use std::path::PathBuf;

use macroquad::prelude::*;

use audio::ArcadeAudio;
use game::{Event, Game, Phase};
use input::Input;

const CANVAS_W: f32 = 960.0;
const CANVAS_H: f32 = 720.0;

fn window_conf() -> Conf {
    Conf {
        window_title: "SPEED RACE - Taito 1974".to_owned(),
        window_width: 960,
        window_height: 720,
        window_resizable: true,
        high_dpi: true,
        sample_count: 1,
        ..Default::default()
    }
}

#[macroquad::main(window_conf)]
async fn main() {
    let target = render_target(gfx::SCREEN_W as u32, gfx::SCREEN_H as u32);
    target.texture.set_filter(FilterMode::Nearest);

    let mut game = Game::new(load_high_score());
    let mut audio = ArcadeAudio::load().await;
    let mut input = Input::new();
    let mut fullscreen = false;

    loop {
        let state = input.poll();

        if state.fullscreen {
            fullscreen = !fullscreen;
            set_fullscreen(fullscreen);
        }
        if state.screenshot {
            save_screenshot("speed-race-screenshot.png");
        }
        if state.mute {
            audio.toggle_mute();
        }
        if state.quit {
            break;
        }
        if state.pause {
            game.toggle_pause();
        }

        if state.start && matches!(game.phase, Phase::Attract | Phase::GameOver) {
            audio.stop_engine();
            game.start_race();
        }

        let dt = get_frame_time().min(0.05);
        game.update(state.controls, dt);

        for event in game.take_events() {
            match event {
                Event::CountdownBeep => audio.countdown(),
                Event::Go => audio.go(),
                Event::Overtake => audio.pass(),
                Event::Crash => {
                    audio.stop_engine();
                    audio.crash();
                }
                Event::Extend => audio.extend(),
                Event::GameOver => {
                    audio.stop_engine();
                    audio.game_over();
                }
            }
        }

        if game.best_dirty {
            save_high_score(game.best);
            game.best_dirty = false;
        }

        let engine_active = !game.paused && matches!(game.phase, Phase::Countdown | Phase::Racing);
        audio.sync_engine(engine_active, game.speed, game.controls.throttle, dt);

        // 1. Paint the low-resolution road into its phosphor tube.
        let mut game_camera =
            Camera2D::from_display_rect(Rect::new(0.0, 0.0, gfx::SCREEN_W, gfx::SCREEN_H));
        game_camera.render_target = Some(target.clone());
        if game.shake > 0.0 {
            let t = get_time() as f32 * 37.0;
            game_camera.offset = vec2(
                t.sin() * game.shake * 2.4,
                (t * 1.37).cos() * game.shake * 1.8,
            );
        }
        set_camera(&game_camera);
        clear_background(gfx::VOID);
        gfx::draw_game_screen(&game);

        // 2. Compose the cabinet on a stable 960 x 720 canvas, letterboxed
        //    into whatever window size the player has chosen.
        set_default_camera();
        clear_background(BLACK);
        set_canvas_camera();
        gfx::draw_cabinet(&game, &target.texture, audio.muted);

        next_frame().await;
    }

    if game.best_dirty {
        save_high_score(game.best);
    }
}

fn set_canvas_camera() {
    let dpi = screen_dpi_scale();
    let scale = (screen_width() / CANVAS_W).min(screen_height() / CANVAS_H);
    // Camera viewports are expressed in physical framebuffer pixels even
    // though screen_width() reports logical points on a Retina display.
    let width = (CANVAS_W * scale * dpi).round() as i32;
    let height = (CANVAS_H * scale * dpi).round() as i32;
    let x = ((screen_width() * dpi - width as f32) * 0.5).round() as i32;
    let y = ((screen_height() * dpi - height as f32) * 0.5).round() as i32;

    let mut camera = Camera2D::from_display_rect(Rect::new(0.0, 0.0, CANVAS_W, CANVAS_H));
    // A Camera2D drawing straight to the window has an inverted Y axis in
    // macroquad. Render targets do not, which is why the cabinet camera needs
    // its vertical zoom flipped while the CRT camera does not.
    camera.zoom.y = -camera.zoom.y;
    camera.viewport = Some((x, y, width, height));
    set_camera(&camera);
}

fn save_screenshot(path: &str) {
    get_screen_data().export_png(path);
}

fn high_score_path() -> PathBuf {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
    home.join(".speed_race_1974_highscore")
}

fn load_high_score() -> u32 {
    fs::read_to_string(high_score_path())
        .ok()
        .and_then(|text| text.trim().parse::<u32>().ok())
        .unwrap_or(0)
        .min(9_999_999)
}

fn save_high_score(score: u32) {
    let _ = fs::write(high_score_path(), format!("{score}\n"));
}
