{
  description = "Cross-compilation demo: C libs + SDL3 game for Linux/Windows/Android/Emscripten, plus portable (FHS) Linux bundles";

  # Pinned to the nixpkgs revision that is already present in this machine's
  # channel/Nix store, so most of the toolchain does not have to be downloaded.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      # `allowUnfree` is required for the Android NDK used by the
      # `aarch64-android-prebuilt` cross target.
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      # `nix build .#linux-uselib2`, `.#windows-sdl3-game`, ...
      packages.${system} = import ./lib/packages.nix { inherit pkgs; };

      # Convenience aliases, same as some of the packages above.
      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.linux-uselib2}/bin/uselib2";
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [ nixfmt just ];
      };
    };
}
