[« Previous: 36 — Customizing nixpkgs](../36-customizing-nixpkgs/README.md) · [Index](../README.md) · [Next: 38 — Canadian cross »](../38-canadian-cross/README.md)

# 37 — CI with GitHub Actions

> **Goal.** Build and test the whole guide in CI: one job per chapter, one core
> and one job per build, with a binary cache so repeated runs are cheap.

This chapter is configuration, not a flake. The workflow lives at
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

---

## 1. The shape of the problem

There are ~30 chapters, each an **independent flake**. You could:

* build them all in one job sequentially (simple, slow, one failure hides the rest);
* build them in a **matrix**, one job per chapter (parallel across runners, each
  still single-core).

The matrix is better: a failure names the chapter, and runners are cheap while
your machine's cores are precious.

## 2. Discovering chapters

Do not hard-code the list — new chapters should appear automatically:

```yaml
- id: find
  run: |
    chapters=$(find . -mindepth 2 -maxdepth 2 -name flake.nix -printf '%h\n' \
      | sed 's#^\./##' | sort \
      | jq -R -s -c 'split("\n") | map(select(length > 0))')
    echo "chapters=$chapters" >> "$GITHUB_OUTPUT"
```

This skips text-only chapters (they have no `flake.nix`).

## 3. One job per chapter

```yaml
strategy:
  fail-fast: false
  matrix:
    chapter: ${{ fromJson(needs.discover.outputs.chapters) }}
steps:
  - uses: actions/checkout@v4
  - uses: cachix/install-nix-action@v31
    with:
      extra_nix_config: |
        experimental-features = nix-command flakes
  - working-directory: ${{ matrix.chapter }}
    run: nix build .#default --max-jobs 1 --cores 1
```

Note the flags: **`--max-jobs 1 --cores 1`**, always, even in CI. The guide's
rule does not change because the machine is disposable.

`nix build` runs each chapter's `checkPhase` (the GL/QEMU/APK checks), so this
*is* the test suite.

## 4. Caching

Two layers:

* **Upstream cache** (`cache.nixos.org`) already has gcc/clang/NDK/QEMU, so most
  runs download, not build.
* **Your own cache** stores the chapters' outputs and any custom derivations:

  ```yaml
  - if: ${{ vars.CACHIX_NAME != '' }}
    uses: cachix/cachix-action@v15
    with:
      name: ${{ vars.CACHIX_NAME }}
      authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}
  ```

  Then `cachix push <name> ./result` locally (or let `cachix watch-exec` do it
  during the build). Without a cache, every run re-evaluates and re-downloads.

## 5. Artifacts

The APK (`34`) and AppImages (`18`, `24–30`) are file outputs. If you want them
from CI, add an upload step after the build:

```yaml
- uses: actions/upload-artifact@v4
  with:
    name: ${{ matrix.chapter }}
    path: |
      ${{ matrix.chapter }}/result*/*.AppImage
      ${{ matrix.chapter }}/result*/*.apk
    if-no-files-found: ignore
```

(Keep an eye on size: the bundled-GL AppImages are ~90 MB.)

## 6. `nix flake check` vs `nix build`

* `nix build .#default` builds **one** output and runs its `checkPhase`.
* `nix flake check` evaluates the flake and builds its `checks` output. None of
  the chapters define `checks`, so you would need to add them, e.g.:

  ```nix
  checks.${system}.default = self.packages.${system}.default;
  ```

  For the guide, building `.#default` per chapter is simpler and sufficient.

## 7. Restricting the matrix

Some chapters are heavy (devkitPro pulls Docker images, Android pulls the SDK,
GL builds Mesa). To keep PR runs fast, filter:

```yaml
matrix:
  chapter: ${{ fromJson(needs.discover.outputs.chapters) }}
  exclude:
    - chapter: 18-fhs-portable-sharun-uruntime
    - chapter: 22-devkitpro-devkitnix
    - chapter: 24-gl-bundled-mesa
```

and run the full matrix nightly (`on: schedule`).

## 8. Pitfalls

* **Parallel Nix inside one job.** Do not drop `--cores 1` because "CI is
  ephemeral" — a runaway build still hits the runner's memory limit.
* **No cache.** Cross toolchains are large; without cachix every run pays for it.
* **Secrets in `if`.** The `vars.CACHIX_NAME != ''` guard works with a repository
  *variable*; a secret in `if` is not reliable — use a variable for the name.
* **Hard-coded chapter list.** It rots; discover it.
* **Wrong runner.** This guide cross-compiles *from x86-64 Linux*; use
  `ubuntu-latest`. macOS/Windows runners would not run the Linux-native builds.
* **Uploading 90 MB × N.** Cache the store, upload artifacts only when needed.

## 9. What's next

[Chapter 38](../38-canadian-cross/README.md) goes deeper into platform theory:
the **Canadian cross** (`build ≠ host ≠ target`).

---

[« Previous: 36 — Customizing nixpkgs](../36-customizing-nixpkgs/README.md) · [Index](../README.md) · [Next: 38 — Canadian cross »](../38-canadian-cross/README.md)
