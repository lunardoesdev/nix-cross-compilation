{
  description = "Chapter 41 — exotic targets: a UEFI application (and a kernel-module recipe)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      gnu = pkgs.gnu-efi;

      # =======================================================================
      # A UEFI application (.efi) for x86_64.
      # =======================================================================
      # UEFI on x86_64 uses the System V ABI, so the *native* gcc works -- the
      # "cross" part is freestanding compilation plus gnu-efi's crt0/linker
      # script and the PE/COFF conversion step.
      uefiApp = pkgs.stdenv.mkDerivation {
        pname = "uefi-demo";
        version = "1.0.0";
        src = ./src;

        nativeBuildInputs = [ pkgs.binutils ];

        dontConfigure = true;
        enableParallelBuilding = false;

        buildPhase = ''
          runHook preBuild

          CFLAGS="-I${gnu}/include/efi -I${gnu}/include/efi/x86_64 \
                  -fPIC -fshort-wchar -ffreestanding \
                  -fno-stack-protector -mno-red-zone -O2 -Wall -Wextra"

          $CC $CFLAGS -c main.c -o main.o
          $CC $CFLAGS -c add.c  -o add.o
          $CC $CFLAGS -I. -c mul.c -o mul.o
          $AR rcs libadd.a add.o
          $AR rcs libmul.a mul.o

          # Link as a shared object against gnu-efi, then convert to PE/COFF.
          $LD -shared -Bsymbolic \
            -T ${gnu}/lib/elf_x86_64_efi.lds \
            ${gnu}/lib/crt0-efi-x86_64.o \
            main.o libmul.a libadd.a \
            -L${gnu}/lib -lefi -lgnuefi \
            -o uefi-demo.so

          $OBJCOPY \
            -j .text -j .sdata -j .data -j .dynamic \
            -j .dynsym -j .rel -j .rela -j .reloc \
            --target=efi-app-x86_64 \
            uefi-demo.so uefi-demo.efi

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p "$out/bin"
          cp uefi-demo.efi "$out/bin/"
          runHook postInstall
        '';

        doCheck = true;
        checkPhase = ''
          runHook preCheck
          file uefi-demo.efi | tee file.txt
          grep -q 'PE32+ executable' file.txt
          grep -qi 'EFI application' file.txt
          runHook postCheck
        '';

        meta.description = "UEFI application built with gnu-efi";
      };
    in
    {
      packages.${system} = {
        inherit uefiApp;
        default = uefiApp;
      };
    };
}
