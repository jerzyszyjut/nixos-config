{ config, lib, pkgs, ... }:

# NOTE ON PACKAGE NAMES
# A few names below are commented out because I could not verify them against
# this exact nixpkgs revision. Nix fails on the FIRST bad name, so leaving
# several unverified ones in means one rebuild per mistake. Check and re-enable
# in a batch instead:
#
#   nix search nixpkgs <name>
#
# Verified-good names are left active.

{
  home.packages = with pkgs; [
    # ---- GUI apps you kept ----------------------------------------------
    # Firefox is declared at system level in desktop.nix so its extensions
    # (uBlock Origin, Bitwarden) can be force-installed via policy.
    kdePackages.okular # annotation; zathura handles daily reading
    thunderbird # aerc is configured in apps.nix, try it gradually
    slack
    discord
    spotify
    vlc
    qbittorrent
    # hunspellDicts.pl_PL  # check: nix search nixpkgs hunspellDicts

    # ---- editors ---------------------------------------------------------
    vscode # keeping this as the GUI fallback; drop if nvim sticks
    # Cursor dropped per your call.

    # ---- Claude Code -----------------------------------------------------
    # You have ~/.claude and ~/.claude.json already. Pairs with
    # coder/claudecode.nvim — see the notes at the bottom of apps.nix.
    unstable.claude-code

    # ---- terminal toolkit ------------------------------------------------
    eza
    ripgrep
    fd
    sd # sed with sane syntax
    jq
    yq
    dust # du, but readable
    duf # df, but readable
    btop
    nvtopPackages.intel
    hyperfine
    tokei
    tealdeer # tldr pages
    entr # run a command when files change

    # ---- TUI tools -------------------------------------------------------
    lazydocker
    # gitui  # you already have lazygit; re-add if you want a second opinion
    # ncspot  # you kept the Spotify GUI; re-add if you change your mind

    # ---- languages & package managers ------------------------------------
    tree-sitter # nvim-treesitter compiles parsers with this
    uv # your Python workflow; works because of nix-ld in dev.nix
    (python313.withPackages (ps: with ps; [ debugpy pynvim ]))
    nodejs_22
    yarn
    cookiecutter
    postgresql # psql client + the libpq headers you had via libpq-dev

    # ---- Neovim ----------------------------------------------------------
    # kickstart uses `vim.pack`, Neovim's built-in plugin manager, which needs
    # 0.12+. If `nvim --version` shows 0.11 on stable, uncomment the unstable
    # line and comment out the base.nix entry instead.
    # unstable.neovim

    # ---- language servers for nvim ---------------------------------------
    # These replace everything mason would otherwise download. Adding a server
    # means adding it here AND to the `servers` table in dotfiles/nvim/init.lua.
    lua-language-server
    pyright
    ruff
    typescript-language-server # was nodePackages.*; that scope was removed
    texlab # LaTeX LSP
    marksman # Markdown LSP
    markdownlint-cli
    bash-language-server
    yaml-language-server # your k8s manifests
    # dockerfile-language-server-nodejs  # renamed? nix search nixpkgs dockerfile-language
    vscode-langservers-extracted # jsonls, html, css
    # Debug adapters, also normally installed by mason:
    stylua # conform.nvim calls this for Lua formatting
    # clangd comes from clang-tools in dev.nix
    # tinymist (Typst LSP) is in dev.nix

    # ---- Nix tooling -----------------------------------------------------
    nixpkgs-fmt
    nil # Nix LSP, for editing this repo in nvim
    nix-tree # find out what's eating your disk
    nh # nicer nixos-rebuild frontend
    nix-output-monitor
  ];
}
