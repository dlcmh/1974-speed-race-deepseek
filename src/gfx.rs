//! All drawing: the 1974 cabinet, its glowing LED panel, and the phosphor
//! green road seen through the CRT.

use macroquad::prelude::*;

use crate::game::{Game, MAX_SPEED, PLAYER_Z, Phase};
use crate::road::{HORIZON_Y, ROAD_HALF_WIDTH, VIEW_DISTANCE, project, screen_offset};

pub const SCREEN_W: f32 = 240.0;
pub const SCREEN_H: f32 = 360.0;

// The game screen's position and scale on the 960 x 720 virtual cabinet.
const CRT_X: f32 = 300.0;
const CRT_Y: f32 = 110.0;
const CRT_SCALE: f32 = 1.5;

const fn rgb(r: u8, g: u8, b: u8) -> Color {
    Color {
        r: r as f32 / 255.0,
        g: g as f32 / 255.0,
        b: b as f32 / 255.0,
        a: 1.0,
    }
}

const fn rgba(r: u8, g: u8, b: u8, a: f32) -> Color {
    Color {
        r: r as f32 / 255.0,
        g: g as f32 / 255.0,
        b: b as f32 / 255.0,
        a,
    }
}

fn with_alpha(color: Color, a: f32) -> Color {
    Color { a, ..color }
}

// -------------------------------------------------------------------------
// Palette
// -------------------------------------------------------------------------

pub const VOID: Color = rgb(3, 8, 5);
const SKY: Color = rgb(2, 7, 4);
const ROAD_A: Color = rgb(5, 24, 12);
const ROAD_B: Color = rgb(7, 30, 15);
const ROAD_EDGE: Color = rgb(56, 194, 104);
const ROAD_EDGE_HOT: Color = rgb(157, 255, 183);
const LANE_LINE: Color = rgb(43, 133, 72);
const PHOSPHOR: Color = rgb(116, 255, 151);
const PHOSPHOR_WHITE: Color = rgb(215, 255, 224);
const PHOSPHOR_DIM: Color = rgb(30, 96, 50);
const PHOSPHOR_DARK: Color = rgb(12, 49, 24);
const SPARK: Color = rgb(210, 255, 210);
const CAR_WHITE: Color = rgb(196, 255, 210);
const CAR_MID: Color = rgb(110, 220, 140);
const CAR_DARK: Color = rgb(27, 92, 48);
const CAR_GLASS: Color = rgb(2, 20, 9);
const TIRE: Color = rgb(1, 7, 3);

const WALL: Color = rgb(7, 7, 7);
const WALL_LINE: Color = rgb(15, 14, 12);
const CABINET_DARK: Color = rgb(23, 19, 15);
const CABINET_BLACK: Color = rgb(6, 6, 5);
const ORANGE: Color = rgb(187, 86, 32);
const ORANGE_DARK: Color = rgb(119, 51, 20);
const ORANGE_LIGHT: Color = rgb(218, 112, 45);
const CREAM: Color = rgb(243, 222, 171);
const LED_GREEN: Color = rgb(91, 255, 132);
const LED_AMBER: Color = rgb(242, 183, 62);

// -------------------------------------------------------------------------
// Small drawing helpers
// -------------------------------------------------------------------------

fn fill_quad(a: Vec2, b: Vec2, c: Vec2, d: Vec2, color: Color) {
    draw_triangle(a, b, c, color);
    draw_triangle(a, c, d, color);
}

fn panel(x: f32, y: f32, w: f32, h: f32, fill: Color, border: Color) {
    draw_rectangle(x, y, w, h, fill);
    draw_rectangle_lines(x, y, w, h, 1.0, border);
}

// -------------------------------------------------------------------------
// A compact 5 x 7 bitmap font
// -------------------------------------------------------------------------

fn glyph(c: char) -> Option<[u8; 7]> {
    let g = match c.to_ascii_uppercase() {
        'A' => [
            0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001,
        ],
        'B' => [
            0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110,
        ],
        'C' => [
            0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110,
        ],
        'D' => [
            0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110,
        ],
        'E' => [
            0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111,
        ],
        'F' => [
            0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000,
        ],
        'G' => [
            0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111,
        ],
        'H' => [
            0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001,
        ],
        'I' => [
            0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b11111,
        ],
        'J' => [
            0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100,
        ],
        'K' => [
            0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001,
        ],
        'L' => [
            0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111,
        ],
        'M' => [
            0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001,
        ],
        'N' => [
            0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001,
        ],
        'O' => [
            0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110,
        ],
        'P' => [
            0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000,
        ],
        'Q' => [
            0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101,
        ],
        'R' => [
            0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001,
        ],
        'S' => [
            0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110,
        ],
        'T' => [
            0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100,
        ],
        'U' => [
            0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110,
        ],
        'V' => [
            0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100,
        ],
        'W' => [
            0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b10101, 0b01010,
        ],
        'X' => [
            0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001,
        ],
        'Y' => [
            0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100,
        ],
        'Z' => [
            0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111,
        ],
        '0' => [
            0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110,
        ],
        '1' => [
            0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110,
        ],
        '2' => [
            0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111,
        ],
        '3' => [
            0b11111, 0b00010, 0b00100, 0b00010, 0b00001, 0b10001, 0b01110,
        ],
        '4' => [
            0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010,
        ],
        '5' => [
            0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110,
        ],
        '6' => [
            0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110,
        ],
        '7' => [
            0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000,
        ],
        '8' => [
            0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110,
        ],
        '9' => [
            0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100,
        ],
        ':' => [
            0b00000, 0b00100, 0b00100, 0b00000, 0b00100, 0b00100, 0b00000,
        ],
        '.' => [
            0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00100, 0b00100,
        ],
        ',' => [
            0b00000, 0b00000, 0b00000, 0b00000, 0b00100, 0b00100, 0b01000,
        ],
        '-' => [
            0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000,
        ],
        '!' => [
            0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00000, 0b00100,
        ],
        '?' => [
            0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b00000, 0b00100,
        ],
        '/' => [
            0b00001, 0b00010, 0b00010, 0b00100, 0b01000, 0b01000, 0b10000,
        ],
        '+' => [
            0b00000, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00000,
        ],
        '=' => [
            0b00000, 0b00000, 0b11111, 0b00000, 0b11111, 0b00000, 0b00000,
        ],
        '\'' => [
            0b00100, 0b00100, 0b01000, 0b00000, 0b00000, 0b00000, 0b00000,
        ],
        _ => return None,
    };
    Some(g)
}

pub fn text_width(text: &str, scale: f32) -> f32 {
    let chars = text.chars().count() as f32;
    if chars == 0.0 {
        0.0
    } else {
        chars * 6.0 * scale - scale
    }
}

pub fn draw_pixel_text(text: &str, x: f32, y: f32, scale: f32, color: Color) {
    let mut cursor = x;
    for ch in text.chars() {
        if let Some(rows) = glyph(ch) {
            for (row, bits) in rows.iter().enumerate() {
                let mut col = 0;
                while col < 5 {
                    let bit = 1 << (4 - col);
                    if bits & bit == 0 {
                        col += 1;
                        continue;
                    }
                    let start = col;
                    while col < 5 && bits & (1 << (4 - col)) != 0 {
                        col += 1;
                    }
                    draw_rectangle(
                        cursor + start as f32 * scale,
                        y + row as f32 * scale,
                        (col - start) as f32 * scale,
                        scale,
                        color,
                    );
                }
            }
        }
        cursor += 6.0 * scale;
    }
}

fn draw_text_shadow(text: &str, x: f32, y: f32, scale: f32, color: Color, shadow: Color) {
    draw_pixel_text(text, x + scale, y + scale, scale, shadow);
    draw_pixel_text(text, x, y, scale, color);
}

fn centered_text(text: &str, y: f32, scale: f32, color: Color) {
    let x = (SCREEN_W - text_width(text, scale)) * 0.5;
    draw_pixel_text(text, x, y, scale, color);
}

fn centered_text_shadow(text: &str, y: f32, scale: f32, color: Color, shadow: Color) {
    let x = (SCREEN_W - text_width(text, scale)) * 0.5;
    draw_text_shadow(text, x, y, scale, color, shadow);
}

// -------------------------------------------------------------------------
// Seven-segment LED digits
// -------------------------------------------------------------------------

const DIGIT_SEGMENTS: [u8; 10] = [
    0b0111111, 0b0000110, 0b1011011, 0b1001111, 0b1100110, 0b1101101, 0b1111101, 0b0000111,
    0b1111111, 0b1101111,
];

fn draw_seven_digit(x: f32, y: f32, w: f32, h: f32, thickness: f32, digit: u8, lit_color: Color) {
    let mask = DIGIT_SEGMENTS[(digit % 10) as usize];
    let t = thickness;
    let half = h * 0.5;
    let segments = [
        (x + t, y, w - 2.0 * t, t),
        (x + w - t, y + t, t, half - 1.5 * t),
        (x + w - t, y + half + 0.5 * t, t, half - 1.5 * t),
        (x + t, y + h - t, w - 2.0 * t, t),
        (x, y + half + 0.5 * t, t, half - 1.5 * t),
        (x, y + t, t, half - 1.5 * t),
        (x + t, y + half - 0.5 * t, w - 2.0 * t, t),
    ];

    for (index, (sx, sy, sw, sh)) in segments.iter().enumerate() {
        let is_lit = mask & (1 << index) != 0;
        if is_lit {
            draw_rectangle(
                *sx - 2.0,
                *sy - 2.0,
                *sw + 4.0,
                *sh + 4.0,
                with_alpha(LED_GREEN, 0.075),
            );
        }
        draw_rectangle(
            *sx,
            *sy,
            *sw,
            *sh,
            if is_lit { lit_color } else { rgb(12, 45, 25) },
        );
    }
}

#[allow(clippy::too_many_arguments)]
fn draw_seven_number(
    value: u32,
    digits: u32,
    x: f32,
    y: f32,
    digit_w: f32,
    digit_h: f32,
    thickness: f32,
    gap: f32,
    color: Color,
) {
    for i in 0..digits {
        let divisor = 10u32.pow(digits - 1 - i);
        let digit = ((value / divisor) % 10) as u8;
        draw_seven_digit(
            x + i as f32 * (digit_w + gap),
            y,
            digit_w,
            digit_h,
            thickness,
            digit,
            color,
        );
    }
}

// -------------------------------------------------------------------------
// Road scene (240 x 360)
// -------------------------------------------------------------------------

pub fn draw_game_screen(game: &Game) {
    draw_sky(game);
    draw_road(game);
    draw_roadside(game);
    draw_cars(game);
    draw_sparks(game);
    draw_crt_ui(game);
    if game.flash > 0.0 {
        draw_rectangle(
            0.0,
            0.0,
            SCREEN_W,
            SCREEN_H,
            with_alpha(PHOSPHOR_WHITE, game.flash * 0.55),
        );
    }
}

fn draw_sky(game: &Game) {
    draw_rectangle(0.0, 0.0, SCREEN_W, SCREEN_H, SKY);

    // Faint green glow above the horizon, like light bleeding through the
    // smoked glass of an old monitor.
    for i in 0..24 {
        let y = HORIZON_Y - i as f32 * 3.0;
        let alpha = 0.007 + (24 - i) as f32 * 0.00055;
        draw_rectangle(
            0.0,
            y,
            SCREEN_W,
            3.0,
            with_alpha(PHOSPHOR_DARK, alpha * 8.0),
        );
    }

    // A few slow, distant stars keep the top of the screen alive.
    for i in 0..8 {
        let phase = game.distance * 0.0015 + i as f32 * 1.7;
        let x = (phase.sin() * 0.5 + 0.5) * SCREEN_W;
        let y = 8.0 + (i as f32 * 17.0 + game.distance * 0.01).rem_euclid(HORIZON_Y - 8.0);
        let twinkle = 0.10 + ((phase * 2.4).sin() * 0.5 + 0.5) * 0.25;
        draw_rectangle(x, y, 1.0, 1.0, with_alpha(PHOSPHOR, twinkle));
    }

    draw_rectangle(
        0.0,
        HORIZON_Y - 1.0,
        SCREEN_W,
        2.0,
        with_alpha(PHOSPHOR, 0.16),
    );
}

fn draw_road(game: &Game) {
    const STEPS: usize = 74;
    let distance = game.distance;

    for i in (0..STEPS).rev() {
        let t0 = i as f32 / STEPS as f32;
        let t1 = (i + 1) as f32 / STEPS as f32;
        // Quadratic spacing puts most polygons near the camera, where they
        // matter for the sensation of speed.
        let z0 = VIEW_DISTANCE * t0 * t0;
        let z1 = VIEW_DISTANCE * t1 * t1;
        let p0 = project(z0);
        let p1 = project(z1);
        if p0.y - p1.y < 0.02 {
            continue;
        }

        let center0 = SCREEN_W * 0.5 + screen_offset(distance, z0) * p0.scale;
        let center1 = SCREEN_W * 0.5 + screen_offset(distance, z1) * p1.scale;
        let half0 = ROAD_HALF_WIDTH * p0.scale;
        let half1 = ROAD_HALF_WIDTH * p1.scale;

        let stripe = ((distance + z0) / 58.0).floor() as i32;
        let asphalt = if stripe & 1 == 0 { ROAD_A } else { ROAD_B };

        // Black/green verge behind the road.
        let verge = if stripe & 1 == 0 {
            rgb(2, 13, 7)
        } else {
            rgb(2, 10, 6)
        };
        draw_rectangle(0.0, p1.y, SCREEN_W, p0.y - p1.y + 0.4, verge);

        let l0 = center0 - half0;
        let r0 = center0 + half0;
        let l1 = center1 - half1;
        let r1 = center1 + half1;
        fill_quad(
            vec2(l0, p0.y),
            vec2(r0, p0.y),
            vec2(r1, p1.y),
            vec2(l1, p1.y),
            asphalt,
        );

        // Hot shoulders: two thin tapered strips.
        let shoulder0 = (2.2 * p0.scale).max(0.5);
        let shoulder1 = (2.2 * p1.scale).max(0.35);
        let edge_color = if stripe & 1 == 0 {
            ROAD_EDGE
        } else {
            ROAD_EDGE_HOT
        };
        fill_quad(
            vec2(l0, p0.y),
            vec2(l0 + shoulder0, p0.y),
            vec2(l1 + shoulder1, p1.y),
            vec2(l1, p1.y),
            edge_color,
        );
        fill_quad(
            vec2(r0 - shoulder0, p0.y),
            vec2(r0, p0.y),
            vec2(r1, p1.y),
            vec2(r1 - shoulder1, p1.y),
            edge_color,
        );

        // Broken lane dividers, three to make a four-lane highway.
        let dash_phase = (distance + z0).rem_euclid(112.0);
        if dash_phase < 52.0 {
            for divider in [0.25f32, 0.5, 0.75] {
                let lx0 = l0 + (r0 - l0) * divider;
                let lx1 = l1 + (r1 - l1) * divider;
                let width0 = (1.15 * p0.scale).max(0.35);
                let width1 = (1.15 * p1.scale).max(0.25);
                fill_quad(
                    vec2(lx0 - width0, p0.y),
                    vec2(lx0 + width0, p0.y),
                    vec2(lx1 + width1, p1.y),
                    vec2(lx1 - width1, p1.y),
                    LANE_LINE,
                );
            }
        }
    }

    // A soft vanishing line where the asphalt meets the night.
    draw_rectangle(
        0.0,
        HORIZON_Y - 1.0,
        SCREEN_W,
        1.0,
        with_alpha(PHOSPHOR, 0.25),
    );
}

fn draw_roadside(game: &Game) {
    let spacing = 155.0;
    let start = (game.distance / spacing).floor() * spacing;

    for i in 0..14 {
        let world = start + i as f32 * spacing;
        let z = world - game.distance;
        if !(20.0..VIEW_DISTANCE * 0.92).contains(&z) {
            continue;
        }
        let projection = project(z);
        let scale = projection.scale;
        let center = SCREEN_W * 0.5 + screen_offset(game.distance, z) * scale;
        let half = ROAD_HALF_WIDTH * scale;
        let post_h = 2.0 + 13.0 * scale;
        let post_w = (1.5 * scale).max(0.6);
        let dim = with_alpha(PHOSPHOR_DIM, (0.25 + scale * 0.7).min(0.9));
        let hot = with_alpha(PHOSPHOR, (0.45 + scale * 0.55).min(1.0));

        for side in [-1.0f32, 1.0] {
            let x = center + side * (half + 5.0 * scale);
            draw_rectangle(x, projection.y - post_h, post_w, post_h, dim);
            draw_rectangle(
                x - post_w * 0.6,
                projection.y - post_h,
                post_w * 2.2,
                (0.8 * scale).max(0.5),
                hot,
            );
        }
    }
}

enum Actor {
    Player,
    Traffic(usize),
}

fn draw_cars(game: &Game) {
    if game.phase == Phase::GameOver {
        return;
    }

    let mut actors: Vec<(f32, Actor)> = Vec::with_capacity(game.traffic.len() + 1);
    for (index, car) in game.traffic.iter().enumerate() {
        if car.z > VIEW_DISTANCE + 50.0 || car.z < -80.0 {
            continue;
        }
        actors.push((car.z, Actor::Traffic(index)));
    }
    actors.push((PLAYER_Z, Actor::Player));
    actors.sort_by(|a, b| b.0.total_cmp(&a.0));

    for (_, actor) in actors {
        match actor {
            Actor::Traffic(index) => draw_traffic_car(game, index),
            Actor::Player => draw_player_car(game),
        }
    }
}

fn draw_traffic_car(game: &Game, index: usize) {
    let car = game.traffic[index];
    let projection = project(car.z);
    if projection.scale < 0.035 {
        return;
    }
    let screen_x = SCREEN_W * 0.5
        + screen_offset(game.distance, car.z) * projection.scale
        + car.lateral * ROAD_HALF_WIDTH * projection.scale;
    let (base_w, base_h) = match car.kind {
        0 => (21.0, 27.0),
        1 => (23.0, 30.0),
        _ => (24.0, 33.0),
    };
    let scale = projection.scale;
    let width = base_w * scale;
    let height = base_h * scale;
    let body = match car.variant {
        0 => CAR_MID,
        1 => CAR_WHITE,
        _ => rgb(72, 177, 102),
    };
    let wobble = (car.wobble_phase).sin() * 0.6 * scale;
    draw_car(
        screen_x + wobble,
        projection.y + 1.0,
        width,
        height,
        body,
        false,
        car.kind,
        0.0,
        0.0,
    );
}

fn draw_player_car(game: &Game) {
    let projection = project(PLAYER_Z);
    let x = SCREEN_W * 0.5 + game.lateral * ROAD_HALF_WIDTH * projection.scale;
    let blink = game.invulnerable > 0.0 && (get_time() * 18.0) as i32 % 2 == 0;
    if blink {
        return;
    }

    let (angle, lift) = if game.phase == Phase::Crashed {
        let progress = 1.0 - (game.crash_timer / 1.45).clamp(0.0, 1.0);
        (
            progress * std::f32::consts::TAU * 1.35,
            (progress * 12.0).min(8.0),
        )
    } else {
        (0.0, 0.0)
    };

    draw_car(
        x,
        projection.y + 2.0 - lift,
        28.0,
        39.0,
        CAR_WHITE,
        true,
        if game.phase == Phase::Crashed { 1 } else { 0 },
        angle,
        game.lean,
    );
}

#[allow(clippy::too_many_arguments)]
fn draw_car(
    x: f32,
    bottom_y: f32,
    width: f32,
    height: f32,
    body: Color,
    player: bool,
    kind: u8,
    angle: f32,
    lean: f32,
) {
    if width < 4.0 || height < 5.0 {
        draw_rectangle(x - width * 0.5, bottom_y - height, width, height, body);
        return;
    }

    let cx = x;
    let cy = bottom_y - height * 0.5;
    let w = width;
    let h = height;

    // Ground shadow stays flat while the car spins.
    draw_ellipse(
        cx,
        bottom_y - h * 0.02,
        w * 0.50,
        h * 0.08,
        0.0,
        rgba(0, 0, 0, 0.5),
    );

    let part = |dx: f32, dy: f32, pw: f32, ph: f32, color: Color| {
        let (sin, cos) = angle.sin_cos();
        let px = cx + dx * cos - dy * sin;
        let py = cy + dx * sin + dy * cos;
        draw_rectangle_ex(
            px,
            py,
            pw,
            ph,
            DrawRectangleParams {
                offset: vec2(0.5, 0.5),
                rotation: angle,
                color,
            },
        );
    };

    let lean_px = lean * w * 0.06;

    // Wheels and a dark silhouette.
    part(-w * 0.42, h * 0.16, w * 0.17, h * 0.31, TIRE);
    part(w * 0.42, h * 0.16, w * 0.17, h * 0.31, TIRE);
    part(0.0, h * 0.03, w * 0.96, h * 0.78, rgb(1, 10, 4));

    // Main body.
    part(0.0, h * 0.10, w * 0.88, h * 0.62, body);
    part(0.0, h * 0.02, w * 0.79, h * 0.42, body);

    // Cabin, rear glass and roof.
    let roof_w = if kind == 2 { w * 0.72 } else { w * 0.61 };
    part(lean_px, -h * 0.20, roof_w, h * 0.28, body);
    part(lean_px, -h * 0.22, roof_w * 0.76, h * 0.14, CAR_GLASS);
    part(lean_px, -h * 0.30, roof_w * 0.92, h * 0.045, CAR_WHITE);

    if kind == 2 {
        // Box van: tall rear doors and a central seam.
        part(
            0.0,
            h * 0.10,
            w * 0.74,
            h * 0.42,
            with_alpha(CAR_WHITE, 0.30),
        );
        part(0.0, h * 0.10, w * 0.045, h * 0.42, CAR_DARK);
    } else {
        // Boot lid panel.
        part(
            0.0,
            h * 0.20,
            w * 0.68,
            h * 0.17,
            with_alpha(CAR_DARK, 0.55),
        );
    }

    // Bumper and rear lamps.
    part(0.0, h * 0.40, w * 0.94, h * 0.045, rgb(2, 18, 8));
    part(-w * 0.29, h * 0.29, w * 0.17, h * 0.055, PHOSPHOR_WHITE);
    part(w * 0.29, h * 0.29, w * 0.17, h * 0.055, PHOSPHOR_WHITE);

    if player {
        // Racing roundel and a spoiler give the hero car a period silhouette.
        part(0.0, -h * 0.35, w * 0.77, h * 0.045, body);
        part(-w * 0.37, -h * 0.33, w * 0.05, h * 0.10, CAR_DARK);
        part(w * 0.37, -h * 0.33, w * 0.05, h * 0.10, CAR_DARK);
        part(
            0.0,
            h * 0.14,
            w * 0.28,
            h * 0.12,
            with_alpha(CAR_GLASS, 0.55),
        );
        draw_circle(
            cx + lean_px,
            cy + h * 0.14,
            (w * 0.055).max(0.8),
            PHOSPHOR_WHITE,
        );
    } else {
        // White flashes on the corners help distant traffic read.
        part(
            -w * 0.32,
            -h * 0.12,
            w * 0.10,
            h * 0.12,
            with_alpha(CAR_WHITE, 0.5),
        );
        part(
            w * 0.32,
            -h * 0.12,
            w * 0.10,
            h * 0.12,
            with_alpha(CAR_WHITE, 0.5),
        );
    }
}

fn draw_sparks(game: &Game) {
    for spark in &game.sparks {
        let alpha = (spark.life / spark.max_life).clamp(0.0, 1.0);
        let size = (spark.size * (0.35 + alpha)).max(0.7);
        draw_rectangle(
            spark.x - size * 0.5,
            spark.y - size * 0.5,
            size,
            size,
            with_alpha(SPARK, alpha),
        );
    }
}

fn draw_crt_ui(game: &Game) {
    match game.phase {
        Phase::Attract => draw_attract(game),
        Phase::Countdown => draw_countdown(game),
        Phase::GameOver => draw_game_over(game),
        Phase::Racing | Phase::Crashed => draw_race_notice(game),
    }

    if game.paused {
        draw_rectangle(0.0, 0.0, SCREEN_W, SCREEN_H, rgba(0, 0, 0, 0.66));
        let pulse = 0.7 + 0.3 * (get_time() as f32 * 2.5).sin().abs();
        centered_text_shadow(
            "PAUSED",
            142.0,
            5.0,
            with_alpha(PHOSPHOR_WHITE, pulse),
            VOID,
        );
        centered_text("P OR ESC TO RESUME", 198.0, 1.0, PHOSPHOR);
        centered_text("Q TO QUIT", 212.0, 1.0, PHOSPHOR_DIM);
    }
}

fn draw_attract(game: &Game) {
    draw_rectangle(0.0, 44.0, SCREEN_W, 158.0, rgba(0, 0, 0, 0.62));
    draw_rectangle(0.0, 44.0, SCREEN_W, 1.0, with_alpha(PHOSPHOR, 0.35));
    draw_rectangle(0.0, 201.0, SCREEN_W, 1.0, with_alpha(PHOSPHOR, 0.2));

    centered_text("TAITO", 54.0, 1.0, PHOSPHOR);
    centered_text_shadow("SPEED", 76.0, 6.0, PHOSPHOR_WHITE, PHOSPHOR_DARK);
    centered_text_shadow("RACE", 126.0, 6.0, PHOSPHOR_WHITE, PHOSPHOR_DARK);
    centered_text("1974", 178.0, 1.0, PHOSPHOR_DIM);

    let pulse = 0.62 + 0.38 * (game.demo_clock * 4.0).sin().abs();
    centered_text_shadow(
        "PRESS ENTER TO START",
        224.0,
        2.0,
        with_alpha(CREAM, pulse),
        VOID,
    );
    centered_text("A/D OR ARROWS STEER   W/UP GAS", 251.0, 1.0, PHOSPHOR);
    centered_text("AVOID TRAFFIC - BEAT THE CLOCK", 262.0, 1.0, PHOSPHOR_DIM);

    let best = format!("HI SCORE {:06}", game.best);
    draw_pixel_text(&best, 8.0, 8.0, 1.0, PHOSPHOR);
    draw_pixel_text(
        "90 SEC",
        SCREEN_W - text_width("90 SEC", 1.0) - 8.0,
        8.0,
        1.0,
        PHOSPHOR,
    );
}

fn draw_countdown(game: &Game) {
    let Some(number) = game.countdown_number() else {
        return;
    };
    let text = number.to_string();
    draw_rectangle(0.0, 112.0, SCREEN_W, 96.0, rgba(0, 0, 0, 0.4));
    centered_text("GET READY", 100.0, 1.0, PHOSPHOR);
    centered_text_shadow(&text, 122.0, 11.0, PHOSPHOR_WHITE, PHOSPHOR_DARK);
    centered_text("THE CLOCK STARTS ON GO", 208.0, 1.0, PHOSPHOR_DIM);
    centered_text("HOLD GAS TO LAUNCH", 220.0, 1.0, PHOSPHOR);
}

fn draw_race_notice(game: &Game) {
    if let Some(notice) = game.notice {
        let alpha = (notice.timer * 2.0).clamp(0.0, 1.0);
        match notice.text {
            "GO!" => {
                centered_text_shadow("GO!", 126.0, 8.0, with_alpha(CREAM, alpha), VOID);
            }
            "CRASH!" => {
                let flash = if (get_time() * 22.0) as i32 % 2 == 0 {
                    1.0
                } else {
                    0.55
                };
                centered_text_shadow(
                    "CRASH!",
                    132.0,
                    5.0,
                    with_alpha(PHOSPHOR_WHITE, alpha * flash),
                    VOID,
                );
            }
            text => {
                let width = text_width(text, 2.0) + 16.0;
                draw_rectangle(
                    (SCREEN_W - width) * 0.5,
                    82.0,
                    width,
                    24.0,
                    rgba(0, 8, 2, 0.75),
                );
                draw_rectangle_lines(
                    (SCREEN_W - width) * 0.5,
                    82.0,
                    width,
                    24.0,
                    1.0,
                    with_alpha(PHOSPHOR, 0.5),
                );
                centered_text(text, 91.0, 2.0, with_alpha(CREAM, alpha));
            }
        }
    }

    // A small speed/gear strip at the top of the tube keeps vital information
    // in the player's field of view without turning the road into a HUD.
    let speed = format!("{:03}", game.speed as u32);
    draw_pixel_text(&speed, 7.0, 7.0, 1.0, PHOSPHOR_WHITE);
    draw_pixel_text("KM/H", 27.0, 7.0, 1.0, PHOSPHOR);
    let time = format!("{:03}", game.display_time());
    draw_pixel_text(
        &time,
        SCREEN_W - text_width(&time, 1.0) - 7.0,
        7.0,
        1.0,
        PHOSPHOR_WHITE,
    );
}

fn draw_game_over(game: &Game) {
    draw_rectangle(0.0, 0.0, SCREEN_W, SCREEN_H, rgba(0, 0, 0, 0.76));
    draw_rectangle(12.0, 54.0, SCREEN_W - 24.0, 246.0, rgba(0, 9, 3, 0.72));
    draw_rectangle_lines(
        12.0,
        54.0,
        SCREEN_W - 24.0,
        246.0,
        1.0,
        with_alpha(PHOSPHOR, 0.45),
    );

    centered_text_shadow("TIME UP", 72.0, 5.0, PHOSPHOR_WHITE, PHOSPHOR_DARK);
    centered_text("FINAL SCORE", 132.0, 1.0, PHOSPHOR);

    let score = format!("{:06}", game.score.min(999_999));
    centered_text_shadow(&score, 146.0, 4.0, CREAM, VOID);

    let stats = format!(
        "PASSED {:02}   TOP {:03} KM/H",
        game.cars_passed.min(99),
        game.top_speed as u32
    );
    centered_text(&stats, 190.0, 1.0, PHOSPHOR);

    if game.new_best {
        if (get_time() as f32 * 4.0).sin() > -0.15 {
            centered_text("NEW RECORD!", 206.0, 2.0, LED_AMBER);
        }
    } else {
        let best = format!("BEST {:06}", game.best.min(999_999));
        centered_text(&best, 206.0, 1.0, PHOSPHOR);
    }

    centered_text("ENTER  RACE AGAIN", 238.0, 2.0, PHOSPHOR_WHITE);
    centered_text("TAITO  1974", 272.0, 1.0, PHOSPHOR);
}

// -------------------------------------------------------------------------
// Cabinet (960 x 720)
// -------------------------------------------------------------------------

pub fn draw_cabinet(game: &Game, screen: &Texture2D, muted: bool) {
    draw_wall();
    draw_cabinet_chassis();
    draw_marquee();
    draw_left_panel(game);
    draw_right_panel(game);
    draw_screen(screen, muted);
    draw_control_deck(muted);
}

fn draw_wall() {
    draw_rectangle(0.0, 0.0, 960.0, 720.0, WALL);
    for i in 0..18 {
        let x = i as f32 * 64.0 - 60.0;
        draw_line(x, 0.0, x + 190.0, 720.0, 1.0, WALL_LINE);
    }
    draw_rectangle(0.0, 648.0, 960.0, 72.0, rgb(4, 4, 4));
}

fn draw_cabinet_chassis() {
    // Drop shadow and the main plywood shell.
    draw_rectangle(154.0, 26.0, 680.0, 704.0, rgba(0, 0, 0, 0.65));
    draw_rectangle(140.0, 16.0, 680.0, 700.0, CABINET_DARK);
    draw_rectangle(146.0, 22.0, 668.0, 688.0, rgb(31, 25, 20));
    draw_rectangle_lines(140.0, 16.0, 680.0, 700.0, 2.0, rgb(60, 44, 30));

    // Orange side wings, inspired by the original upright's warm laminate.
    for x in [146.0, 684.0] {
        draw_rectangle(x, 104.0, 130.0, 552.0, ORANGE_DARK);
        draw_rectangle(x + 3.0, 104.0, 124.0, 548.0, ORANGE);
        draw_rectangle(x + 3.0, 104.0, 124.0, 24.0, ORANGE_LIGHT);
    }

    // Central black face around the monitor.
    draw_rectangle(280.0, 96.0, 400.0, 568.0, CABINET_BLACK);
    draw_rectangle(286.0, 102.0, 388.0, 556.0, rgb(8, 8, 7));
    draw_rectangle_lines(280.0, 96.0, 400.0, 568.0, 2.0, rgb(46, 33, 23));

    // Bezel lip.
    draw_rectangle(294.0, 104.0, 372.0, 552.0, rgb(2, 3, 2));
    draw_rectangle_lines(294.0, 104.0, 372.0, 552.0, 1.0, rgb(74, 55, 35));

    // Warm light spill from the tube.
    draw_rectangle(292.0, 102.0, 376.0, 556.0, rgba(72, 255, 130, 0.025));

    // Screws.
    for (x, y) in [
        (298.0, 108.0),
        (662.0, 108.0),
        (298.0, 652.0),
        (662.0, 652.0),
    ] {
        draw_circle(x, y, 3.0, rgb(44, 38, 29));
        draw_circle(x, y, 1.2, rgb(90, 77, 54));
    }
}

fn draw_marquee() {
    let x = 208.0;
    let y = 26.0;
    let w = 544.0;
    let h = 64.0;

    draw_rectangle(x, y, w, h, rgba(0, 0, 0, 0.55));
    draw_rectangle(x + 3.0, y + 3.0, w - 6.0, h - 6.0, rgb(5, 10, 7));
    draw_rectangle_lines(x, y, w, h, 2.0, ORANGE_DARK);
    draw_rectangle_lines(x + 5.0, y + 5.0, w - 10.0, h - 10.0, 1.0, rgb(48, 113, 65));

    // Taito badge.
    panel(
        x + 14.0,
        y + 15.0,
        72.0,
        34.0,
        rgb(10, 67, 30),
        rgb(108, 182, 116),
    );
    draw_pixel_text("TAITO", x + 20.0, y + 26.0, 2.0, PHOSPHOR_WHITE);

    // 1974 badge.
    panel(
        x + w - 96.0,
        y + 15.0,
        82.0,
        34.0,
        rgb(52, 24, 8),
        ORANGE_LIGHT,
    );
    draw_pixel_text("1974", x + w - 83.0, y + 27.0, 2.0, CREAM);

    // Marquee wordmark.
    let title = "SPEED RACE";
    let scale = 4.0;
    let title_x = x + (w - text_width(title, scale)) * 0.5;
    draw_text_shadow(title, title_x, y + 18.0, scale, CREAM, ORANGE_DARK);
    draw_rectangle(title_x, y + 51.0, text_width(title, scale), 2.0, ORANGE);
}

fn draw_left_panel(game: &Game) {
    let x = 152.0;
    let y = 112.0;

    // Period side art: a diagonal speed flash behind the instruments.
    for i in 0..4 {
        let offset = i as f32 * 18.0;
        draw_line(
            x + 8.0,
            y + 462.0 + offset,
            x + 112.0,
            y + 402.0 + offset,
            2.0,
            rgba(70, 25, 7, 0.4),
        );
    }

    // Taito badge.
    panel(
        x + 8.0,
        y + 8.0,
        76.0,
        28.0,
        rgb(8, 57, 26),
        rgb(83, 154, 88),
    );
    draw_pixel_text("TAITO", x + 14.0, y + 18.0, 1.5, PHOSPHOR_WHITE);

    draw_pixel_text("SPEED", x + 38.0, y + 46.0, 2.0, CREAM);
    draw_pixel_text("RACE", x + 44.0, y + 66.0, 2.0, CREAM);
    draw_rectangle(x + 30.0, y + 86.0, 70.0, 1.0, ORANGE_DARK);

    // Analog speedometer.
    draw_speedometer(
        x + 64.0,
        y + 158.0,
        48.0,
        game.speed,
        game.controls.throttle,
    );

    // Pedal lamps.
    panel(
        x + 10.0,
        y + 250.0,
        108.0,
        58.0,
        rgb(25, 11, 5),
        ORANGE_DARK,
    );
    draw_pixel_text("GAS", x + 18.0, y + 260.0, 1.5, CREAM);
    draw_pixel_text("BRAKE", x + 18.0, y + 282.0, 1.5, CREAM);
    let gas_on = game.controls.throttle > 0.15;
    let brake_on = game.controls.brake > 0.15;
    draw_circle(
        x + 102.0,
        y + 265.0,
        5.0,
        if gas_on { LED_GREEN } else { rgb(12, 38, 21) },
    );
    draw_circle(
        x + 102.0,
        y + 287.0,
        5.0,
        if brake_on { LED_AMBER } else { rgb(42, 31, 10) },
    );
    if gas_on {
        draw_circle(x + 102.0, y + 265.0, 8.0, rgba(91, 255, 132, 0.14));
    }

    // Checkered racing strip.
    let check_y = y + 326.0;
    for row in 0..2 {
        for column in 0..8 {
            let color = if (row + column) % 2 == 0 {
                CREAM
            } else {
                rgb(37, 24, 15)
            };
            draw_rectangle(
                x + 10.0 + column as f32 * 13.0,
                check_y + row as f32 * 12.0,
                13.0,
                12.0,
                color,
            );
        }
    }

    // Stylised #12 side profile.
    draw_side_car(x + 64.0, y + 410.0);

    draw_pixel_text("100 YEN", x + 30.0, y + 512.0, 1.0, with_alpha(CREAM, 0.7));
}

fn draw_speedometer(cx: f32, cy: f32, radius: f32, speed: f32, throttle: f32) {
    draw_circle(cx, cy, radius + 5.0, rgb(58, 31, 14));
    draw_circle(cx, cy, radius, rgb(9, 21, 12));
    draw_circle_lines(cx, cy, radius, 2.0, CREAM);
    draw_circle_lines(cx, cy, radius - 5.0, 1.0, rgb(50, 111, 64));

    let start_angle = 135.0f32.to_radians();
    let sweep = 270.0f32.to_radians();
    for tick in 0..=12 {
        let angle = start_angle + sweep * tick as f32 / 12.0;
        let major = tick % 2 == 0;
        let inner = if major { radius - 13.0 } else { radius - 9.0 };
        let outer = radius - 5.0;
        let (sin, cos) = angle.sin_cos();
        draw_line(
            cx + cos * inner,
            cy + sin * inner,
            cx + cos * outer,
            cy + sin * outer,
            if major { 2.0 } else { 1.0 },
            if major { PHOSPHOR_WHITE } else { PHOSPHOR_DIM },
        );
    }

    let ratio = (speed / MAX_SPEED).clamp(0.0, 1.0);
    let needle_angle = start_angle + sweep * ratio;
    let (sin, cos) = needle_angle.sin_cos();
    draw_line(
        cx,
        cy,
        cx + cos * (radius - 14.0),
        cy + sin * (radius - 14.0),
        3.0,
        rgb(92, 31, 8),
    );
    draw_line(
        cx,
        cy,
        cx + cos * (radius - 15.0),
        cy + sin * (radius - 15.0),
        1.4,
        CREAM,
    );
    draw_circle(cx, cy, 4.0, CREAM);
    draw_circle(cx, cy, 2.0, ORANGE_DARK);

    let speed_text = format!("{:03}", speed as u32);
    let x = cx - text_width(&speed_text, 2.0) * 0.5;
    draw_pixel_text(&speed_text, x, cy + radius + 11.0, 2.0, PHOSPHOR_WHITE);
    draw_pixel_text(
        "KM/H",
        cx - text_width("KM/H", 1.0) * 0.5,
        cy + radius + 30.0,
        1.0,
        PHOSPHOR_DIM,
    );

    if throttle > 0.1 {
        draw_rectangle(cx - 14.0, cy - 12.0, 28.0, 3.0, rgba(91, 255, 132, 0.18));
    }
}

fn draw_side_car(cx: f32, y: f32) {
    // Wheels.
    draw_circle(cx - 30.0, y + 19.0, 12.0, rgb(13, 10, 8));
    draw_circle(cx + 32.0, y + 19.0, 12.0, rgb(13, 10, 8));
    draw_circle(cx - 30.0, y + 19.0, 5.0, rgb(83, 66, 45));
    draw_circle(cx + 32.0, y + 19.0, 5.0, rgb(83, 66, 45));

    // Low, long 1970s racer.
    draw_rectangle(cx - 48.0, y - 2.0, 96.0, 17.0, CREAM);
    draw_rectangle(cx - 31.0, y - 14.0, 43.0, 15.0, CREAM);
    draw_rectangle(cx - 25.0, y - 11.0, 25.0, 9.0, rgb(34, 82, 51));
    draw_rectangle(cx - 48.0, y + 4.0, 96.0, 5.0, ORANGE_DARK);
    draw_rectangle(cx - 51.0, y + 10.0, 9.0, 5.0, rgb(24, 16, 11));
    draw_rectangle(cx + 43.0, y + 10.0, 10.0, 5.0, rgb(24, 16, 11));
    draw_circle(cx + 6.0, y + 4.0, 7.0, rgb(245, 241, 221));
    draw_pixel_text("12", cx - 1.0, y, 1.0, rgb(29, 33, 26));
}

fn draw_right_panel(game: &Game) {
    let x = 690.0;
    let y = 122.0;
    let w = 112.0;
    let h = 362.0;

    draw_rectangle(x - 5.0, y - 5.0, w + 10.0, h + 10.0, ORANGE_DARK);
    draw_rectangle(x, y, w, h, rgb(5, 8, 5));
    draw_rectangle_lines(x, y, w, h, 2.0, rgb(12, 12, 8));
    draw_rectangle_lines(x + 5.0, y + 5.0, w - 10.0, h - 10.0, 1.0, rgb(70, 54, 31));

    draw_led_module(
        x + 8.0,
        y + 10.0,
        w - 16.0,
        58.0,
        "SCORE",
        game.score,
        6,
        12.0,
        22.0,
        2.0,
    );
    draw_led_module(
        x + 8.0,
        y + 78.0,
        w - 16.0,
        77.0,
        "TIME",
        game.display_time(),
        3,
        20.0,
        30.0,
        3.0,
    );
    draw_led_module(
        x + 8.0,
        y + 165.0,
        w - 16.0,
        59.0,
        "EXTEND",
        game.next_extend,
        6,
        10.0,
        16.0,
        1.6,
    );
    draw_led_module(
        x + 8.0,
        y + 234.0,
        w - 16.0,
        58.0,
        "HI SCORE",
        game.best,
        6,
        10.0,
        16.0,
        1.6,
    );

    draw_rectangle(x + 8.0, y + 303.0, w - 16.0, 1.0, rgb(66, 49, 27));
    draw_pixel_text("TAITO", x + 35.0, y + 317.0, 1.5, with_alpha(CREAM, 0.75));
    draw_pixel_text("1974", x + 39.0, y + 336.0, 1.0, with_alpha(CREAM, 0.4));

    // Lower side art and coin door.
    let cy = y + 400.0;
    draw_rectangle(x + 8.0, cy, w - 16.0, 80.0, rgb(38, 16, 7));
    draw_rectangle_lines(x + 8.0, cy, w - 16.0, 80.0, 1.0, ORANGE_LIGHT);
    draw_pixel_text("FREE", x + 36.0, cy + 12.0, 1.5, CREAM);
    draw_pixel_text("PLAY", x + 36.0, cy + 28.0, 1.5, CREAM);
    draw_rectangle(x + 32.0, cy + 50.0, 48.0, 7.0, rgb(9, 8, 6));
    draw_rectangle(x + 35.0, cy + 52.0, 42.0, 2.0, rgb(110, 83, 46));
    draw_circle(x + 56.0, cy + 68.0, 3.0, LED_GREEN);
}

#[allow(clippy::too_many_arguments)]
fn draw_led_module(
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    label: &str,
    value: u32,
    digits: u32,
    digit_w: f32,
    digit_h: f32,
    thickness: f32,
) {
    draw_rectangle(x, y, w, h, rgb(2, 10, 5));
    draw_rectangle_lines(x, y, w, h, 1.0, rgb(46, 66, 30));

    // Yellow label strip, like the original cabinet's scoreboard.
    draw_rectangle(x + 2.0, y + 2.0, w - 4.0, 15.0, rgb(216, 160, 48));
    draw_rectangle(x + 2.0, y + 2.0, w - 4.0, 2.0, rgb(255, 220, 123));
    draw_pixel_text(label, x + 5.0, y + 6.0, 1.0, rgb(22, 24, 8));

    let gap = (w - 8.0 - digit_w * digits as f32) / (digits.saturating_sub(1).max(1) as f32);
    let total = digits as f32 * digit_w + (digits - 1) as f32 * gap;
    let start_x = x + (w - total) * 0.5;
    let digit_y = y + 23.0 + (h - 28.0 - digit_h) * 0.35;
    draw_seven_number(
        value, digits, start_x, digit_y, digit_w, digit_h, thickness, gap, LED_GREEN,
    );
}

fn draw_screen(screen: &Texture2D, muted: bool) {
    // Green halo spilling from the phosphor.
    draw_rectangle(
        CRT_X - 12.0,
        CRT_Y - 12.0,
        384.0,
        564.0,
        rgba(48, 220, 96, 0.035),
    );
    draw_rectangle(
        CRT_X - 6.0,
        CRT_Y - 6.0,
        372.0,
        552.0,
        rgba(55, 255, 110, 0.05),
    );
    draw_rectangle(
        CRT_X - 2.0,
        CRT_Y - 2.0,
        364.0,
        544.0,
        rgba(100, 255, 150, 0.09),
    );

    draw_texture_ex(
        screen,
        CRT_X,
        CRT_Y,
        WHITE,
        DrawTextureParams {
            dest_size: Some(vec2(SCREEN_W * CRT_SCALE, SCREEN_H * CRT_SCALE)),
            flip_y: true,
            ..Default::default()
        },
    );

    // Scanlines and a slight tube vignette.
    let mut y = CRT_Y + 1.0;
    while y < CRT_Y + SCREEN_H * CRT_SCALE {
        draw_rectangle(CRT_X, y, SCREEN_W * CRT_SCALE, 1.0, rgba(0, 0, 0, 0.18));
        y += 3.0;
    }
    for i in 0..12 {
        let a = 0.012 + i as f32 * 0.005;
        draw_rectangle(
            CRT_X,
            CRT_Y + i as f32,
            SCREEN_W * CRT_SCALE,
            1.0,
            rgba(0, 0, 0, a * 4.0),
        );
        draw_rectangle(
            CRT_X,
            CRT_Y + SCREEN_H * CRT_SCALE - i as f32,
            SCREEN_W * CRT_SCALE,
            1.0,
            rgba(0, 0, 0, a * 4.0),
        );
        draw_rectangle(
            CRT_X + i as f32,
            CRT_Y,
            1.0,
            SCREEN_H * CRT_SCALE,
            rgba(0, 0, 0, a * 3.0),
        );
        draw_rectangle(
            CRT_X + SCREEN_W * CRT_SCALE - i as f32,
            CRT_Y,
            1.0,
            SCREEN_H * CRT_SCALE,
            rgba(0, 0, 0, a * 3.0),
        );
    }

    // A restrained sweep of reflection across the glass.
    fill_quad(
        vec2(CRT_X + 185.0, CRT_Y),
        vec2(CRT_X + 250.0, CRT_Y),
        vec2(CRT_X + 115.0, CRT_Y + SCREEN_H * CRT_SCALE),
        vec2(CRT_X + 50.0, CRT_Y + SCREEN_H * CRT_SCALE),
        rgba(220, 255, 230, 0.018),
    );

    if muted {
        let label = "SOUND OFF";
        let w = text_width(label, 1.0) + 8.0;
        draw_rectangle(
            CRT_X + SCREEN_W * CRT_SCALE - w - 8.0,
            CRT_Y + 8.0,
            w,
            14.0,
            rgba(0, 0, 0, 0.7),
        );
        draw_pixel_text(
            label,
            CRT_X + SCREEN_W * CRT_SCALE - w - 4.0,
            CRT_Y + 12.0,
            1.0,
            PHOSPHOR_DIM,
        );
    }

    // Tiny title plaque under the monitor.
    draw_rectangle(
        CRT_X + 100.0,
        CRT_Y + SCREEN_H * CRT_SCALE + 7.0,
        160.0,
        1.0,
        ORANGE_DARK,
    );
}

fn draw_control_deck(muted: bool) {
    let x = 146.0;
    let y = 660.0;
    let w = 668.0;
    let h = 48.0;
    draw_rectangle(x, y, w, h, rgb(16, 13, 10));
    draw_rectangle_lines(x, y, w, h, 2.0, rgb(66, 44, 26));
    draw_rectangle(x + 5.0, y + 5.0, w - 10.0, 1.0, ORANGE_DARK);

    let line_one = "STEER  A/D OR ARROWS     GAS  W/UP     BRAKE  S/DOWN";
    let line_two = if muted {
        "P PAUSE   M UNMUTE   F11 FULLSCREEN   Q QUIT"
    } else {
        "P PAUSE   M MUTE   F11 FULLSCREEN   Q QUIT"
    };
    draw_pixel_text(
        line_one,
        x + (w - text_width(line_one, 2.0)) * 0.5,
        y + 10.0,
        2.0,
        CREAM,
    );
    draw_pixel_text(
        line_two,
        x + (w - text_width(line_two, 1.5)) * 0.5,
        y + 31.0,
        1.5,
        with_alpha(CREAM, 0.55),
    );
}
