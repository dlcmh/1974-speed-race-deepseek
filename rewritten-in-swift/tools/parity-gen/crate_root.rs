// Scratch crate root materialised by generate.sh.
//
// It compiles *verbatim copies* of the canonical game's modules (copied from
// ../../../src/{game,rng,road}.rs at generation time) together with
// parity_trace.rs, which drives the real `Game` and writes the fixtures.
// Nothing here is part of the canonical crate.

mod game;
mod parity_trace;
mod rng;
mod road;

fn main() {
    parity_trace::run();
}
