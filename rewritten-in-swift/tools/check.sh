#!/bin/sh
# Speed Race (1974) — Swift + Metal port.
#
# The verification gate. Run this before every commit.
#
#   ./tools/check.sh
#
# In sandboxed environments where SwiftPM cannot write its caches, pass the
# extra flags through SWIFT_ARGS, e.g.
#
#   SWIFT_ARGS=--disable-sandbox ./tools/check.sh
#
# Stages:
#   1. swift-format lint   — style, line length, naming, one statement per line
#   2. release build with -warnings-as-errors
#                          — unused variables, dead stores, actor isolation,
#                            unreachable code; the closest thing Swift has to
#                            a built-in linter
#   3. parity-check        — ported unit tests plus the golden-trace replay
#
# There is no Swift equivalent of Clippy that ships with the toolchain.
# `swift-format` is Apple's own formatter/linter and is included with the
# Command Line Tools; SwiftLint and Perforce's `periphery` (dead-code analysis)
# are third-party and deliberately not required by this repository.

set -eu
cd "$(dirname "$0")/.."

SWIFT="${SWIFT:-swift}"
SWIFT_FORMAT="${SWIFT_FORMAT:-xcrun swift-format}"
SWIFT_ARGS="${SWIFT_ARGS:-}"

echo "==> swift-format lint"
$SWIFT_FORMAT lint --recursive Sources Tests

echo "==> build (release, warnings as errors)"
# shellcheck disable=SC2086
$SWIFT build -c release -Xswiftc -warnings-as-errors $SWIFT_ARGS

echo "==> parity and unit checks"
# shellcheck disable=SC2086
$SWIFT run $SWIFT_ARGS parity-check

echo "==> all checks passed"
