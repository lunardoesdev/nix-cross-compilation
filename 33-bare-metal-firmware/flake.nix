{
  description = "Chapter 33 — a bare-metal ARM firmware image (linker script, startup, .elf/.bin), run under QEMU";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      localSystem = "x86_64-linux";

      # A freestanding bare-metal ARM toolchain: no C library at all.
      crossSystem = {
        config = "arm-none-eabi";
        libc = null;              # freestanding (see chapter 09)
      };

      buildPlatform  = nixpkgs.lib.systems.elaborate localSystem;
      targetPlatform = nixpkgs.lib.systems.elaborate crossSystem;

      nativePkgs = import nixpkgs { inherit localSystem; };
      targetPkgs = import nixpkgs { inherit localSystem crossSystem; };

      stdenv = nativePkgs.stdenv.override {
        inherit buildPlatform;
        hostPlatform = targetPlatform;
        targetPlatform = targetPlatform;
        cc = targetPkgs.buildPackages.gcc;
        hasCC = true;
        extraBuildInputs = [ ];
        overrides = _: _: { };
        allowedRequisites = null;
      };

      # The two libraries, as static archives (as in chapter 02).
      mkLib = { pname, sources, headers, deps ? [], linkLibs ? [] }:
        stdenv.mkDerivation {
          inherit pname;
          version = "1.0.0";
          src = ./src;
          buildInputs = deps;
          strictDeps = true;
          dontConfigure = true;
          enableParallelBuilding = false;
          buildPhase = ''
            runHook preBuild
            mkdir -p obj
            for f in ${nixpkgs.lib.concatStringsSep " " sources}; do
              $CC -Os -ffreestanding -mcpu=cortex-m3 -mthumb \
                -c "$f" -o "obj/$(basename "$f" .c).o"
            done
            $AR rcs "lib${pname}.a" obj/*.o
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/lib" "$out/include"
            cp "lib${pname}.a" "$out/lib/"
            ${nixpkgs.lib.concatMapStringsSep "\n" (h: ''cp "${h}" "$out/include/"'') headers}
            runHook postInstall
          '';
        };

      libadd = mkLib { pname = "add"; sources = [ "add.c" ]; headers = [ "add.h" ]; };
      libmul = mkLib {
        pname = "mul"; sources = [ "mul.c" ]; headers = [ "mul.h" ];
        deps = [ libadd ];
      };

      # =======================================================================
      # The firmware image.
      # =======================================================================
      # Compile the startup code and the program, link against the two static
      # libraries with our own linker script, and produce an .elf plus a raw
      # .bin and an Intel .hex.
      firmware = stdenv.mkDerivation {
        pname = "firmware";
        version = "1.0.0";
        src = ./src;

        buildInputs = [ libmul libadd ];

        # qemu runs on the *build* machine, so it is a native build tool.
        nativeBuildInputs = [ nativePkgs.qemu ];

        strictDeps = true;
        dontConfigure = true;
        enableParallelBuilding = false;

        buildPhase = ''
          runHook preBuild

          CFLAGS="-Os -ffreestanding -fno-builtin -Wall -Wextra \
                  -mcpu=cortex-m3 -mthumb"

          for f in startup.c semihosting.c main.c; do
            $CC $CFLAGS -I"${libmul}/include" -I"${libadd}/include" \
              -c "$f" -o "''${f%.c}.o"
          done

          # Link: no C library, no startup files -- our own linker script and
          # Reset_Handler are the whole runtime.
          $CC -mcpu=cortex-m3 -mthumb -nostdlib -nostartfiles \
            -T linker.ld \
            startup.o semihosting.o main.o \
            -L"${libmul}/lib" -lmul -L"${libadd}/lib" -ladd \
            -o firmware.elf

          $OBJCOPY -O binary firmware.elf firmware.bin
          $OBJCOPY -O ihex   firmware.elf firmware.hex

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p "$out/bin"
          cp firmware.elf firmware.bin firmware.hex "$out/bin/"
          runHook postInstall
        '';

        # Run it on QEMU's lm3s6965evb (Cortex-M3) and check the output.
        doCheck = true;
        checkPhase = ''
          runHook preCheck
          out="$(timeout 20 ${nativePkgs.qemu}/bin/qemu-system-arm \
            -M lm3s6965evb -nographic -no-reboot \
            -semihosting-config enable=on,target=native \
            -kernel firmware.elf 2>&1 || true)"
          echo "$out"
          echo "$out" | grep -q 'firmware: mul(6, 7) = 42'
          runHook postCheck
        '';

        meta.description = "bare-metal ARM firmware image";
      };
    in
    {
      packages.${localSystem} = {
        inherit libadd libmul firmware;
        default = firmware;
      };
    };
}
