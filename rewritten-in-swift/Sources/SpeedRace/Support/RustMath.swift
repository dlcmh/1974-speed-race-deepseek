// Speed Race (1974) — Swift + Metal port.
//
// Numeric helpers that reproduce Rust standard-library semantics which differ
// subtly from Swift's default `Float` methods. Every one of these has a
// comment explaining the Rust behaviour it pins, because getting one wrong
// silently shifts gameplay or breaks the golden parity traces.

import Foundation

/// Rust's `f32::clamp(min, max)`.
///
/// Swift's `min`/`max`/`clamped` propagate NaN differently from Rust, so the
/// Rust semantics are spelled out: a NaN value stays NaN, and a NaN bound
/// panics in Rust. Debug builds assert on NaN bounds to surface the same
/// programming error; release builds fall back to the finite bound.
public func rustClamp(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
    assert(!lower.isNaN && !upper.isNaN, "clamp bounds must not be NaN")
    if value.isNaN { return value }
    if value < lower { return lower }
    if value > upper { return upper }
    return value
}

// Rust's `f32::sin`/`f32::cos` on this target may call either of libm's two
// implementations, *per call site*: the optimiser folds a call into the
// correctly-rounded double-precision `sin`/`cos` (rounded once to f32), or
// leaves a `sinf`/`cosf` call. The canonical game exhibits both:
//
//   attract demo `lean = (demo_clock * 0.46).cos() * 0.5`
//       -> f64 path:     cos = 1064608836, lean = 1056220228
//   attract demo `lateral = (demo_clock * 0.46).sin() * 0.34`
//       -> sinf path:    sin = 1057042959, lateral = 1043313850
//
// Both bit patterns were read from the canonical Rust game itself (fixtures and
// direct probes; see docs/INVESTIGATION-parity.md). The port therefore
// provides both and uses the one the canonical call site resolves to.
//
// Swift's `Foundation.sin(_: Float)` matches *neither* at every argument, so
// the port binds libm directly with `@_silgen_name`. These are ordinary
// libSystem functions; no dependency or C shim is added.

@_silgen_name("sin")
private func libmSinDouble(_ value: Double) -> Double

@_silgen_name("cos")
private func libmCosDouble(_ value: Double) -> Double

@_silgen_name("sinf")
private func libmSinf(_ value: Float) -> Float

@_silgen_name("cosf")
private func libmCosf(_ value: Float) -> Float

/// Rust's `f32::sin` where the canonical call site resolves to the
/// double-precision `sin` rounded once to `f32`.
public func rustSin(_ value: Float) -> Float {
    Float(libmSinDouble(Double(value)))
}

/// Rust's `f32::sin` where the canonical call site calls `sinf`.
public func rustSinFloat(_ value: Float) -> Float {
    libmSinf(value)
}

/// Rust's `f32::cos` where the canonical call site calls `cosf`.
public func rustCosFloat(_ value: Float) -> Float {
    libmCosf(value)
}

/// Rust's `f32::cos` where the canonical call site resolves to the
/// double-precision `cos` rounded once to `f32`.
public func rustCos(_ value: Float) -> Float {
    Float(libmCosDouble(Double(value)))
}

/// Rust's `f32 as u32` saturating cast.
///
/// `UInt32(_:)` traps in Swift for NaN, negative and out-of-range values, so
/// every port of a Rust float-to-int cast goes through here instead.
public enum RustFloat {
    public static func toUInt32Saturating(_ value: Float) -> UInt32 {
        if value.isNaN || value <= 0.0 { return 0 }
        if value >= 4_294_967_296.0 { return .max }
        return UInt32(value)
    }

    public static func toInt32Saturating(_ value: Float) -> Int32 {
        if value.isNaN { return 0 }
        if value <= -2_147_483_648.0 { return .min }
        if value >= 2_147_483_648.0 { return .max }
        return Int32(value)
    }
}

extension UInt32 {
    /// Rust: `x as u32` where `x: f32`.
    public init(rustSaturating value: Float) {
        self = RustFloat.toUInt32Saturating(value)
    }
}

extension Int32 {
    /// Rust: `x as i32` where `x: f32`.
    public init(rustSaturating value: Float) {
        self = RustFloat.toInt32Saturating(value)
    }
}

extension Float {
    /// Rust's `std::f32::consts::TAU`.
    ///
    /// Rust's constant is `6.283185307179586_f64 as f32` (bits 0x40C90FDB),
    /// which stays exact when cast. Swift's `2.0 * Float.pi` computes
    /// `0x1.921fb6p+1 * 2` = `0x40C90FDC` — one ULP *above* Rust — and that
    /// shifted every `rng.range(0.0, std::f32::consts::TAU)` result. The
    /// golden traces caught it as a one-ULP traffic wobble-phase mismatch
    /// (docs/PORTING-JOURNEY.md §6). Always use this constant.
    public static let rustTau: Float = 6.2831855
}
