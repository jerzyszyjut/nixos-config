{ config, lib, pkgs, ... }:

let
  cfg = config.profiles.work;
in
{
  # =========================================================================
  # THE "PRACA" PROFILE.
  #
  # Everything here is only built when a host asks for it:
  #
  #   profiles.work.enable = true;   # set per-host in flake.nix
  #
  # The split exists so a future machine can take one half of this repo and
  # leave the other behind. What stays OUTSIDE the profiles (base.nix,
  # desktop.nix, style.nix, net.nix, secrets.nix) is the stuff you want on
  # literally any machine you own: the user, the compositor, the theme, WiFi.
  #
  # The home-manager half of this profile lives in home/jerzy/work.nix and
  # keys off the same option via `osConfig`.
  # =========================================================================
  options.profiles.work.enable = lib.mkEnableOption ''
    the work/development profile: nix-ld, Docker, the C/C++ and Python
    toolchains, k8s CLIs, LaTeX/Typst
  '';

  config = lib.mkIf cfg.enable {
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

    # ---- containers ------------------------------------------------------
    # The group membership lives here rather than in base.nix: without Docker
    # enabled there is no "docker" group, and useradd refuses to add a user to
    # a group that does not exist. extraGroups is a list option, so this
    # appends to the base list instead of replacing it.
    users.users.jerzy.extraGroups = [ "docker" ];

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

      # ---- C/C++ toolchain (build-essential, clang, cmake, ninja...) ------
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

      # ---- C/C++ side-project tooling -------------------------------------
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

      # ---- emulation / embedded ------------------------------------------
      qemu

      # ---- cloud / k8s (all kept) -----------------------------------------
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

      # ---- LaTeX -----------------------------------------------------------
      # For conference manuscripts (CVF/IEEE templates), which Typst can't do.
      # scheme-medium is ~2GB and covers latexmk/bibtex/Times + the recommended
      # collection; the extras below live in collection-latexextra, which medium
      # omits, and are exactly what the CVF wacv.sty/cvpr.sty templates pull in.
      # Add a name here rather than jumping to texliveFull (~7GB) -- find the
      # provider of a missing foo.sty with: nix run nixpkgs#texlive.bin.texfindpkg -- query foo.sty
      (texliveMedium.withPackages (ps: with ps; [
        cleveref # \cref/\Cref, required by wacv.sty
        enumitem # \begin{itemize}[leftmargin=*] etc.
        multirow # multi-row table cells
        makecell # line breaks inside table cells
        silence # wacv.sty uses it to mute template warnings
        lineno # review-mode line numbers in CVF templates
      ]))

      poppler-utils # pdfinfo/pdftotext -- check page counts against page limits
    ];

    # Dropped per your call: aircrack-ng, dsniff, nmap, wireshark, steam,
    # gamemode, gimp, super-productivity, pdfarranger, pdfsam, cursor, brave.
  };
}
