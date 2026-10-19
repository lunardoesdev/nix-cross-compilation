[« Previous: 22 — devkitPro with devkitNix](../22-devkitpro-devkitnix/README.md) · [Index](../README.md) · [Next: Appendix B — Glossary »](../appendix-b-glossary/README.md)

# Appendix C — The single-core rule & build script

> Every command in this guide uses **one core and one job**. This appendix
> explains why, and collects the exact flags.

## Why

Cross toolchains are among the heaviest things Nix can build. A single
`nix build` that fans out over every core can:

* make the machine unusable for anything else,
* exhaust memory (a parallel gcc can use gigabytes per job),
* and, on a laptop, trip thermal limits and *slow the build down* anyway.

So this guide treats "one core, one job" as a hard rule.

## The flags

```sh
nix build .#libadd --max-jobs 1 --cores 1
```

| flag | meaning |
|------|---------|
| `--max-jobs 1` (or `-j1`) | build at most **one derivation at a time** |
| `--cores 1` | let each derivation use at most **one CPU core** |

`--max-jobs` limits *parallel derivations*; `--cores` sets `NIX_BUILD_CORES`,
which build systems use for their own parallelism. You want both.

You can also make it permanent for a shell:

```sh
nix build --option max-jobs 1 --option cores 1 .#libadd
```

or globally in `nix.conf`:

```
max-jobs = 1
cores = 1
```

## In the derivations

Flags only control the *invocation*. Inside a derivation, a build system may
still try to parallelise. Every derivation in this guide therefore also sets:

```nix
enableParallelBuilding = false;
```

and, where a `make` is invoked directly, `make -j1`.

## The wrapper script

`scripts/build.sh` wraps the flags so you cannot forget them:

```sh
./scripts/build.sh .#libmul                       # nix build .#libmul --max-jobs 1 --cores 1
./scripts/build.sh -C 02-first-cross-flake .#libmul
./scripts/build.sh --all                          # every chapter's `default`
```

It always `cd`s to the guide root and passes `--max-jobs 1 --cores 1`.

## Copy-paste block

```sh
# native / cross build of one output
nix build .#<output> --max-jobs 1 --cores 1

# everything in a chapter
nix build --max-jobs 1 --cores 1

# run an app (e.g. chapter 03's explainer)
nix run .#explain --max-jobs 1 --cores 1
```

---

[« Previous: 22 — devkitPro with devkitNix](../22-devkitpro-devkitnix/README.md) · [Index](../README.md) · [Next: Appendix B — Glossary »](../appendix-b-glossary/README.md)
