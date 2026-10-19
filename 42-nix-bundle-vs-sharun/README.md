[« Previous: 41 — Exotic targets](../41-exotic-targets/README.md) · [Index](../README.md) · [Next: Appendix A — Troubleshooting & FAQ »](../appendix-a-troubleshooting/README.md)

# 42 — `nix bundle` vs sharun

> **Goal.** Compare the two ways to ship a Nix-built program to a machine without
> Nix: Nix's own **`nix bundle`** and the **sharun** AppDir/AppImage approach used
> in Part 5.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. `nix bundle`

```sh
nix bundle --max-jobs 1 --cores 1 .#uselib2 -o ./uselib2-bundle
./uselib2-bundle
```

By default it packs the **whole closure** into a single **self-extracting
executable** (the `arx` bundler). The result is one file — here **26 MB** — that
unpacks to a temporary directory and runs the program.

```sh
$ file uselib2-bundle
…: symbolic link to /nix/store/…-uselib2-arx
$ env -i HOME=/tmp ./uselib2-bundle
uselib2: add(6, 7) = 13
uselib2: mul(6, 7) = 42
```

Note the `HOME`: the launcher wants a home directory. That is a launcher detail,
not a program one.

You can pick another bundler:

```sh
nix bundle --bundler github:NixOS/bundlers#toDockerImage .#uselib2
```

Bundlers are ordinary flakes exposing `bundlers.<system>.<name>`.

## 2. What `nix bundle` does *not* do

It is **generic**: it knows how to pack a closure, not how to make a *Linux
desktop application* work. In particular it does not:

* set `XDG_DATA_DIRS`, `LD_LIBRARY_PATH`, glvnd/DRI paths, Qt/GTK plugin paths;
* provide an `AppDir` layout or a `.desktop` file;
* append *host* driver directories (the `nixGL` problem);
* offer a FUSE-less AppImage runtime.

That is exactly the layer `sharun` (chapter 18) adds.

## 3. Side by side

| | `nix bundle` (arx) | sharun AppDir / AppImage | musl-static (ch. 35) |
|---|---|---|---|
| output | one self-extracting file | directory / tar.zst / AppImage | one AppImage |
| carries | full closure | glibc + libs (or none) | nothing (static) |
| env setup | no | **yes** (GL, X11, plugins, …) | n/a |
| host drivers | no | **yes** (fallback path) | no |
| desktop entry | no | yes | yes |
| FUSE-less | n/a (extracts) | uruntime extracts | uruntime extracts |
| size (CLI demo) | 26 MB | ~15 MB | **1.4 MB** |
| arbitrary language/app | yes | yes | only if it links statically |

Sizes differ because the bundlers compress and lay out differently; `nix bundle`
is the simplest to invoke, sharun is the most "desktop-aware".

## 4. Which to choose

* **One file, any program, minimal effort** → `nix bundle`.
* **A desktop/GL application that must work on glibc *and* musl** → sharun with
  a bundled Mesa ([ch. 24](../24-gl-bundled-mesa/README.md)).
* **A CLI tool that must run literally everywhere** → musl-static
  ([ch. 35](../35-musl-static-bundle/README.md)).
* **You need env handling and host drivers but not a full bundle** → sharun
  host-driver AppDir ([ch. 27](../27-gl-host-drivers/README.md)).

## 5. Verify

```sh
nix build .#uselib2 --max-jobs 1 --cores 1
nix bundle --max-jobs 1 --cores 1 .#uselib2 -o /tmp/uselib2-bundle
file /tmp/uselib2-bundle
env -i HOME=/tmp /tmp/uselib2-bundle
```

## 6. Pitfalls

* **`env -i` without `HOME`.** The arx launcher fails with `HOME: parameter not
  set`; pass `HOME` (or do not clear it).
* **Expecting GL to work.** `nix bundle` does not set the glvnd/DRI environment;
  a GL app will not find its driver unless the host is already set up.
* **Assuming `nix bundle` is an AppImage.** It is not; there is no `.desktop`
  integration or host-driver fallback.
* **Forgetting the output is a symlink into the store.** `-o` creates a symlink;
  copy the resolved file when distributing it.

## 7. The end of the guide

You now have:
* the fundamentals (Part 1) and a toolchain you can replace piece by piece (Part 2),
* one recipe for many targets (Part 3) and the four headline targets (Part 4),
* portable Linux bundles and 32-bit/static variants (Part 5, 35, 39),
* more platforms and languages (Part 6, 32),
* portable OpenGL in four flavours (Part 7),
* real build systems and cross build-system integration (Part 8, 31),
* and the edges: Android packaging, bare metal, UEFI, Canadian crosses, CI.

Continue with [Appendix A — Troubleshooting & FAQ](../appendix-a-troubleshooting/README.md),
or the target cheat sheet in [Appendix D](../appendix-d-target-cheatsheet/README.md).

---

[« Previous: 41 — Exotic targets](../41-exotic-targets/README.md) · [Index](../README.md) · [Next: Appendix A — Troubleshooting & FAQ »](../appendix-a-troubleshooting/README.md)
