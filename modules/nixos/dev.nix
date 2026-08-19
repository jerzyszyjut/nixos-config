{ config, lib, pkgs, ... }:

{
  # =======================================================================
  # THE MOST IMPORTANT BLOCK IN THIS REPO, FOR YOU SPECIFICALLY.
  #
  # You use `uv` (found at ~/.local/bin/uv), pipx, and pip. Wheels like torch,
  # numpy, scipy — anything with a compiled extension — expect an FHS-style
  # /lib and a normal dynamic loader. NixOS has neither, so they fail at
  # import time with cryptic "libstdc++.so.6 not found" errors.
  #
  # nix-ld provides a shim loader that makes those wheels just work. With this
  # on, `uv venv && uv pip install torch` behaves like it does on Ubuntu.
  #
  # Test this first, before anything else:
  #   uv venv && uv pip install numpy torch && python -c "import torch"
  # =======================================================================
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib # libstdc++ — the one everything needs
      zlib
      zstd
      openssl
      curl
      libxml2
      glib
      glibc
      xz
      # graphics libs — needed by opencv, matplotlib backends, jupyter widgets
      libGL
      glfw
      libxkbcommon
      libx11
      libxext
      libxrender
      libxi
      libxrandr
      libxcb
      # scientific stack
      blas
      lapack
    ];
  };

  # nix-ld's shim only kicks in for foreign binaries whose ELF interpreter got
  # rewritten — it does nothing for a Nix-built python (e.g. the one `uv`
  # picks up from PATH at /etc/profiles/.../bin/python3.13) loading a
  # manylinux wheel's compiled .so (tokenizers, numpy, torch, ...). That's a
  # native dynamic-link lookup, so it needs the same libraries on
  # LD_LIBRARY_PATH instead of NIX_LD_LIBRARY_PATH. Safe to set globally:
  # Nix binaries resolve their own deps via RPATH first, so this only adds a
  # fallback search path, it doesn't shadow anything.
  environment.variables.LD_LIBRARY_PATH = lib.makeLibraryPath config.programs.nix-ld.libraries;

  # ---- containers --------------------------------------------------------
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly"; # unused images accumulate quickly
      flags = [ "--all" ];
    };
  };

  environment.systemPackages = with pkgs; [
    # An Ubuntu container for anything that refuses to cooperate with Nix.
    # `distrobox create -i ubuntu:24.04` and you have your old world back.
    distrobox

    # ---- C/C++ toolchain (build-essential, clang, cmake, ninja...) --------
    gcc
    clang-tools # clang-format, clang-tidy
    lldb
    gdb
    cmake
    ninja
    gnumake
    just
    pkg-config
    autoconf
    automake
    libtool
    bison
    flex
    gperf

    # ---- C/C++ side-project tooling ---------------------------------------
    # CLIs only — no test/benchmark libraries here on purpose. Catch2/GTest/
    # gbenchmark headers on NixOS aren't on the compiler's search path from a
    # plain shell anyway (no FHS), so they belong in a per-project devShell,
    # not global packages. Use `nix flake init -t ~/nixos-config#cpp` in a new
    # project directory — see templates/cpp/flake.nix.
    ccache # wire in per-project via CMAKE_CXX_COMPILER_LAUNCHER=ccache
    cppcheck # static analysis, catches more than clang-tidy on some bugs
    include-what-you-use
    bear # generates compile_commands.json for non-CMake build systems
    conan # C/C++ dependency manager

    # The GCC-bootstrap libs you had installed by hand. These really belong in
    # per-project devShells, but they're here so nothing breaks on day one.
    gmp
    mpfr
    libmpc
    isl

    # ---- emulation / embedded --------------------------------------------
    qemu

    # ---- cloud / k8s (all kept) -------------------------------------------
    kubectl
    krew
    kubernetes-helm
    k9s
    kubectx
    google-cloud-sdk
    awscli2
    s3cmd

    # ---- misc CLI --------------------------------------------------------
    graphviz
    imagemagick
    ffmpeg-full
    libwebp
    zstd

    typst
    tinymist # typst language server, for nvim
  ];

  # Dropped per your call: aircrack-ng, dsniff, nmap, wireshark, steam,
  # gamemode, gimp, super-productivity, pdfarranger, pdfsam, cursor, brave.
}
