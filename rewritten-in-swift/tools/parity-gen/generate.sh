#!/bin/sh
# Materialise a Rust parity-trace generator from the canonical game sources.
#
# The canonical game (repository root) is a binary crate, so its `game`, `rng`
# and `road` modules cannot be imported through a library interface. This
# script copies those three files *verbatim* into a scratch directory, drops
# in a tiny crate root and the trace driver, builds with the system cargo and
# writes JSON Lines fixtures to ../../Fixtures/parity/.
#
# The canonical crate is never modified. See docs/INVESTIGATION-parity.md.
#
# Usage: ./generate.sh            (writes ../../Fixtures/parity/*.jsonl)
#        ./generate.sh --keep     (leaves the scratch crate for inspection)
#
# Requires: cargo (rustup or a system install). The game's own dependencies
# (macroquad, cpal, gilrs) are NOT needed: the copied modules use only std.

set -eu
cd "$(dirname "$0")"

repo_root=$(cd ../../.. && pwd)
src="$repo_root/src"
work=$PWD/.work
# Absolute paths: cargo runs the binary with the crate directory as its working
# directory, so relative output paths would land inside the scratch crate.
out=$(cd ../.. && pwd)/Fixtures/parity

if [ ! -f "$src/game.rs" ]; then
    echo "generate.sh: canonical sources not found at $src" >&2
    exit 1
fi
if ! command -v cargo >/dev/null 2>&1; then
    echo "generate.sh: cargo not found; install Rust or generate fixtures elsewhere" >&2
    exit 1
fi

rm -rf "$work"
mkdir -p "$work/src" "$out"
cp "$src/game.rs" "$src/rng.rs" "$src/road.rs" "$work/src/"
# The scenarios need three private items to build a reproducible start state
# without touching the canonical file (docs/INVESTIGATION-parity.md "Generator construction"):
# `Game::rng`, `Game::traffic` and `Game::seed_traffic`. Widen them to
# `pub(crate)` in the *scratch copy only*. The substitution is checked: the
# script fails loudly if the canonical source no longer matches.
python3 - "$work/src/game.rs" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
for old, new in [
    ("    rng: Rng,", "    pub(crate) rng: Rng,"),
    ("    pub traffic: Vec<TrafficCar>,", "    pub traffic: Vec<TrafficCar>,"),
    ("    fn seed_traffic(&mut self) {", "    pub(crate) fn seed_traffic(&mut self) {"),
]:
    if old not in text:
        sys.exit(f"generate.sh: canonical pattern not found: {old!r}")
    text = text.replace(old, new, 1)
open(path, "w").write(text)
PY

cp crate_root.rs "$work/src/main.rs"
cp trace_fixtures.rs "$work/src/parity_trace.rs"

# `[workspace]` stops Cargo from treating any enclosing manifest as the
# scratch crate's workspace root.
cat > "$work/Cargo.toml" <<EOF
[workspace]
[package]
name = "speed-race-parity-gen"
version = "0.0.0"
edition = "2024"
publish = false

[[bin]]
name = "parity-gen"
path = "src/main.rs"

[profile.dev]
debug = false
EOF

commit=$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo unknown)
echo "generating parity fixtures from canonical sources at $commit"
# `--cfg test` exposes the canonical crate's `#[cfg(test)]`-gated
# `Game::with_seed`, the constructor the Rust unit tests use for determinism.
# Without it every fixture would draw its starting traffic from the clock.
(cd "$work" && RUSTFLAGS="--cfg test -A unused" cargo run --quiet --release -- "$out" "$commit")


if [ "${1:-}" != "--keep" ]; then
    rm -rf "$work"
fi
echo "done: $(ls "$out" | wc -l | tr -d ' ') fixture file(s) in $out"
