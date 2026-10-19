{
  description = "Chapter 34 — packaging a cross-built Android app: APK, signing, AAB";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        config.android_sdk.accept_license = true;
      };

      # Full Android SDK (build-tools + platform + NDK).  Everything is cached.
      android = pkgs.buildPackages.androidenv.composeAndroidPackages {
        includeNDK = true;
        ndkVersion = "27.0.12077973";
        buildToolsVersions = [ "35.0.0" ];
        platformVersions = [ "35" ];
        includeCmake = false;
        includeEmulator = false;
      };
      sdk = "${android.androidsdk}/libexec/android-sdk";

      ndk = "${sdk}/ndk/27.0.12077973";
      clang = "${ndk}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang";
      buildTools = "${sdk}/build-tools/35.0.0";
      androidJar = "${sdk}/platforms/android-35/android.jar";

      # =======================================================================
      # Build the native libraries and the signed APK.
      # =======================================================================
      apk = pkgs.stdenv.mkDerivation {
        pname = "cdemo";
        version = "1.0.0";
        src = ./src;

        # apksigner is a Java tool; keytool generates the signing key.
        nativeBuildInputs = [ pkgs.apksigner pkgs.jdk pkgs.bundletool ];

        dontConfigure = true;
        enableParallelBuilding = false;

        buildPhase = ''
          runHook preBuild

          # --- native libraries (arm64-v8a) --------------------------------
          ${clang} -shared -fPIC -O2 -Wl,-soname,libadd.so  add.c  -o libadd.so
          ${clang} -shared -fPIC -O2 -Wl,-soname,libmul.so  mul.c  -I. -L. -ladd -o libmul.so
          ${clang} -shared -fPIC -O2 -Wl,-soname,libmain.so main.c -I. -L. -lmul -ladd \
            -landroid -llog -o libmain.so

          # --- stage the APK payload ---------------------------------------
          mkdir -p stage/lib/arm64-v8a
          cp libmain.so libadd.so libmul.so stage/lib/arm64-v8a/

          # --- package + align + sign --------------------------------------
          ${buildTools}/aapt package -f \
            -M AndroidManifest.xml \
            -I "${androidJar}" \
            -F unsigned.apk stage/

          ${buildTools}/zipalign -f 4 unsigned.apk aligned.apk

          # A throw-away debug keystore.  For a real app use your own key --
          # see the chapter text.
          keytool -genkeypair \
            -keystore debug.keystore \
            -storepass android -alias androiddebugkey -keypass android \
            -keyalg RSA -keysize 2048 -validity 10000 \
            -dname "CN=Android Debug,O=Android,C=US"

          apksigner sign \
            --ks debug.keystore \
            --ks-pass pass:android --key-pass pass:android \
            --out cdemo.apk aligned.apk

          apksigner verify --verbose cdemo.apk

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p "$out"
          cp cdemo.apk "$out/"
          cp unsigned.apk "$out/" 2>/dev/null || true
          runHook postInstall
        '';

        doCheck = true;
        checkPhase = ''
          runHook preCheck
          echo "== badging =="
          ${buildTools}/aapt dump badging cdemo.apk | grep -E \
            "^package:|^launchable-activity:|^native-code:" | tee badging.txt
          grep -q "package: name='org.example.cdemo'" badging.txt
          grep -q "launchable-activity: name='android.app.NativeActivity'" badging.txt
          grep -q "native-code: 'arm64-v8a'" badging.txt

          echo "== signature =="
          apksigner verify --verbose cdemo.apk
          runHook postCheck
        '';

        meta.description = "Signed Android APK containing the arm64 native libraries";
      };
    in
    {
      packages.${system} = {
        inherit apk;
        default = apk;
      };

      # Expose the SDK paths for inspection.
      androidSdk = sdk;
    };
}
