{
  description = "C++ project devShell: CMake, Catch2/GTest/gbenchmark, clangd";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          cmake
          ninja
          clang-tools # clangd, clang-format, clang-tidy
          gdb
          lldb
          ccache
          cppcheck
          include-what-you-use
          catch2_3
          gtest
          gbenchmark
          pkg-config
        ];

        # bear generates compile_commands.json when a project doesn't use
        # CMake's own EXPORT_COMPILE_COMMANDS (this one does — see
        # CMakeLists.txt — so it's a fallback, not required).
        shellHook = ''
          export CMAKE_CXX_COMPILER_LAUNCHER=ccache
        '';
      };
    };
}
