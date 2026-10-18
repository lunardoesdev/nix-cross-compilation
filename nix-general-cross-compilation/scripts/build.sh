#!/usr/bin/env bash
#
# Thin wrapper around `nix build` that enforces the project rule:
#
#     ALWAYS USE A SINGLE CORE AND A SINGLE JOB.
#
# Usage:
#   ./scripts/build.sh                 # build the default package
#   ./scripts/build.sh .#linux-uselib2 # build one output
#   ./scripts/build.sh all             # build every output (see below)
#
set -euo pipefail

cd "$(dirname "$0")/.."

NIX_FLAGS=(--max-jobs 1 --cores 1)

if [ "${1:-}" = "all" ]; then
    shift
    # Everything in lib/packages.nix, in a sensible order.
    exec nix build "${NIX_FLAGS[@]}" \
        .#linux-libadd .#linux-libmul .#linux-uselib2 .#linux-sdl3-game \
        .#windows-libadd .#windows-libmul .#windows-uselib2 .#windows-sdl3-game \
        .#android-libadd .#android-libmul .#android-uselib2 .#android-sdl3-game \
        .#emscripten-libadd .#emscripten-libmul .#emscripten-sdl3-game \
        .#linux-libs .#linux-libs-tar \
        .#linux-portable-uselib2 .#linux-portable-sdl3-game \
        .#linux-portable-uselib2-tar .#linux-portable-sdl3-game-tar \
        .#linux-portable-uselib2-appimage .#linux-portable-sdl3-game-appimage \
        "$@"
fi

exec nix build "${NIX_FLAGS[@]}" "$@"
