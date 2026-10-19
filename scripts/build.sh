#!/usr/bin/env bash
#
# Thin wrapper around `nix build` that enforces this guide's rule:
#
#     ALWAYS USE A SINGLE CORE AND A SINGLE JOB.
#
# Cross toolchains are heavy; letting Nix fan out over every core can make a
# machine unusable.  This script always passes `--max-jobs 1 --cores 1`, so you
# cannot forget them.
#
# Usage:
#   ./scripts/build.sh                       # build .#default in $PWD
#   ./scripts/build.sh .#libmul              # build one output
#   ./scripts/build.sh -C 02-first-cross-flake .#libmul
#   ./scripts/build.sh --all                 # build the default output of every chapter
#
set -euo pipefail

# Always run from the repository root, no matter where the script is called from.
cd "$(dirname "$0")/.."

NIX_FLAGS=(--max-jobs 1 --cores 1)

# -C DIR: run the build from DIR instead (e.g. a chapter directory).
if [ "${1:-}" = "-C" ]; then
    shift
    cd "$1"
    shift
fi

# --all: build the `default` output of every chapter that has a flake.nix.
if [ "${1:-}" = "--all" ]; then
    shift
    for chapter in */; do
        if [ -f "${chapter}flake.nix" ]; then
            echo "==> ${chapter%/}"
            ( cd "$chapter" && exec nix build "${NIX_FLAGS[@]}" .#default "$@" )
        fi
    done
    exit 0
fi

exec nix build "${NIX_FLAGS[@]}" "$@"
