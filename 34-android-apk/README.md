[« Previous: 33 — A bare-metal firmware image](../33-bare-metal-firmware/README.md) · [Index](../README.md) · [Next: 35 — A musl-static bundle »](../35-musl-static-bundle/README.md)

# 34 — Packaging an Android APK (and AAB, and signing)

> **Goal.** Take the cross-built arm64 libraries from the earlier chapters and
> package them into a **real, signed Android APK** — then document how the same
> thing is done for an **AAB** and with a **release signing key**.

Chapter [16](../16-target-android/README.md) stopped at "these are arm64 ELF
files, packaging an APK is out of scope". This chapter does the packaging.

The complete flake is in [`flake.nix`](flake.nix); sources in [`src/`](src).

---

## 1. What an APK actually contains

An APK is a zip with a fixed structure. For a native-only app:

```
cdemo.apk
├── AndroidManifest.xml          (binary XML)
├── lib/arm64-v8a/
│   ├── libmain.so               <- the NativeActivity, exports ANativeActivity_onCreate
│   ├── libadd.so
│   └── libmul.so
└── META-INF/                    <- signatures
```

There is **no Java/Kotlin code**: `android:hasCode="false"`, and
`android.app.NativeActivity` loads `libmain.so` (the name comes from the
`android.app.lib_name` meta-data).

## 2. The native side

`libmain.so` exports one symbol:

```c
void ANativeActivity_onCreate(ANativeActivity *activity, void *saved, size_t size)
{
    activity->callbacks->onStart = on_start;   /* framework allocates the struct */
}
```

In `onStart` we call `mul(6, 7)` (→ `libmul` → `libadd`) and finish. The three
libraries are built with the **NDK clang** for `arm64-v8a`, with the API level in
the driver name (`aarch64-linux-android21-clang`).

## 3. The packaging pipeline

```sh
# 1. compile the native libraries (NDK clang, API 21, arm64)
aarch64-linux-android21-clang -shared -fPIC -O2 -Wl,-soname,libadd.so  add.c  -o libadd.so
aarch64-linux-android21-clang -shared -fPIC -O2 -Wl,-soname,libmul.so  mul.c  -I. -L. -ladd -o libmul.so
aarch64-linux-android21-clang -shared -fPIC -O2 -Wl,-soname,libmain.so main.c -I. -L. -lmul -ladd \
    -landroid -llog -o libmain.so

# 2. stage them at lib/<ABI>/
mkdir -p stage/lib/arm64-v8a && cp lib*.so stage/lib/arm64-v8a/

# 3. package (aapt compiles the manifest and writes the zip)
aapt package -f -M AndroidManifest.xml -I $SDK/platforms/android-35/android.jar \
    -F unsigned.apk stage/

# 4. align (required for uncompressed resources on many devices)
zipalign -f 4 unsigned.apk aligned.apk

# 5. sign
keytool -genkeypair -keystore debug.keystore -storepass android \
    -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 \
    -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
apksigner sign --ks debug.keystore --ks-pass pass:android --key-pass pass:android \
    --out cdemo.apk aligned.apk

# 6. verify
apksigner verify --verbose cdemo.apk
```

The flake does exactly this in `buildPhase`, with the tools from the full SDK
(`composeAndroidPackages { buildToolsVersions = ["35.0.0"]; platformVersions = ["35"]; includeNDK = true; }`).

## 4. Run it

```sh
nix build .#apk --max-jobs 1 --cores 1
ls result
# cdemo.apk  unsigned.apk
```

## 5. Verify

```sh
$ aapt dump badging result/cdemo.apk
package: name='org.example.cdemo' versionCode='1' versionName='1.0' …
sdkVersion:'21'
launchable-activity: name='android.app.NativeActivity'
native-code: 'arm64-v8a'

$ unzip -l result/cdemo.apk
… AndroidManifest.xml
… lib/arm64-v8a/libadd.so
… lib/arm64-v8a/libmain.so
… lib/arm64-v8a/libmul.so

$ apksigner verify --verbose result/cdemo.apk
Verifies
Verified using v1 scheme (JAR signing): true
Verified using v2 scheme (APK Signature Scheme v2): true
Verified using v3 scheme (APK Signature Scheme v3): true
```

## 6. Signing: debug vs release

* **Debug key** (what the flake uses) is fine for `adb install` and testing, but
  Google Play will reject it, and you cannot update an app signed with a
  different key.
* **Release key**: generate one *once*, keep it offline and backed up:

  ```sh
  keytool -genkeypair -keystore release.keystore -alias mykey \
    -keyalg RSA -keysize 4096 -validity 10000 \
    -dname "CN=Your Name, O=Your Org, C=US"
  apksigner sign --ks release.keystore --ks-key-alias mykey \
    --out app-release.apk app-release-unsigned.apk
  ```

* **Never commit a keystore.** In Nix, pass it in at build time
  (`apksigner sign --ks /path/to/release.keystore …`) or use
  `--ks-pass file:…` / environment-based passwords.
* **Play App Signing**: with an AAB, Google re-signs the delivered APKs; your
  upload key only signs the bundle. Losing the *upload* key can be recovered by
  Google; losing a self-managed *app signing* key cannot.

## 7. AAB (Android App Bundle)

An AAB is not a zip of APKs — it is a publishing format that Google Play (or
`bundletool`) turns into per-device APKs. It contains:

```
base/
├── manifest/AndroidManifest.xml
├── dex/                         (empty here: hasCode=false)
├── lib/arm64-v8a/*.so
├── res/                         (compiled resources, optional)
├── resources.pb
└── assets/
BundleConfig.pb
```

Producing one is normally done by **Gradle** (`./gradlew bundleRelease`) or by
`bundletool` from a module zip:

```sh
bundletool build-bundle --modules=base.zip --output=cdemo.aab --config=BundleConfig.json
bundletool build-apks --bundle=cdemo.aab --output=cdemo.apks --mode=universal
```

Because `aapt` produces an APK, not the module layout, this chapter stops at the
signed APK and documents the AAB step. For a Nix-native Gradle build you would
use `pkgs.gradle` + an `androidenv` SDK and run `bundleRelease`; the native
libraries are the same ones built here.

> **Which to ship?** Play requires AAB for new apps; for sideloading/F-Droid an
> APK is still the unit of distribution. Build the same native libs either way.

## 8. Pitfalls

* **Manifest twice.** `aapt package -M AndroidManifest.xml stage/` fails with
  "Duplicate file" if the manifest is also inside `stage/` (we hit this).
* **`hasCode="false"` without a `NativeActivity`.** The app installs but there is
  nothing to launch.
* **Wrong `android.app.lib_name`.** It must match the library name **without**
  `lib`/`.so` (`main` → `libmain.so`).
* **No `zipalign`.** Some devices refuse unaligned APKs; sign *after* aligning
  (aligning a signed APK invalidates the signature).
* **Signing with the wrong key.** You cannot update an installed app signed with
  a different key; Play rejects debug keys.
* **ABI mismatch.** `lib/arm64-v8a/` must contain arm64 ELF; an x86-64 `.so`
  installs and then fails to load. Check with `file`.
* **libc coupling.** These are Android/bionic libraries; do not mix them with the
  glibc bundles from [Part 5](../18-fhs-portable-sharun-uruntime/README.md).

## 9. What's next

[Chapter 35](../35-musl-static-bundle/README.md) returns to Linux and builds the
"runs anywhere" bundle: **musl-static + sharun**.

---

[« Previous: 33 — A bare-metal firmware image](../33-bare-metal-firmware/README.md) · [Index](../README.md) · [Next: 35 — A musl-static bundle »](../35-musl-static-bundle/README.md)
