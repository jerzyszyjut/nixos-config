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
#
# WHAT BELONGS HERE: things you would want on any machine of yours, whichever
# profile it runs. Development tooling went to home/jerzy/work.nix, players and
# media to home/jerzy/entertainment.nix — see modules/profiles/.

{
  home.packages = with pkgs; [
    # ---- GUI apps you kept ----------------------------------------------
    # Firefox is declared at system level in desktop.nix so its extensions
    # (uBlock Origin, Bitwarden) can be force-installed via policy.
    kdePackages.okular # annotation; zathura handles daily reading
    thunderbird # aerc is configured in apps.nix, try it gradually
    # qbittorrent (the GUI) is deliberately NOT here any more: the
    # entertainment profile runs qbittorrent-nox as a system service, and two
    # clients fighting over the same peer port is a bad afternoon. Its web UI
    # is at http://localhost:8080.
    # hunspellDicts.pl_PL  # check: nix search nixpkgs hunspellDicts

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
    unzip

    # ---- Neovim ----------------------------------------------------------
    # kickstart uses `vim.pack`, Neovim's built-in plugin manager, which needs
    # 0.12+. If `nvim --version` shows 0.11 on stable, uncomment the unstable
    # line and comment out the base.nix entry instead.
    # unstable.neovim
    tree-sitter # nvim-treesitter compiles parsers with this

    # Language-agnostic servers only — nvim should still be a usable editor on
    # a machine with no work profile. The per-language ones are in work.nix.
    lua-language-server
    marksman # Markdown LSP
    markdownlint-cli
    bash-language-server
    stylua # conform.nvim calls this for Lua formatting

    # ---- Nix tooling -----------------------------------------------------
    # Not in a profile on purpose: this is what you maintain THIS repo with,
    # so it has to exist on every machine the repo is deployed to.
    nixpkgs-fmt
    nil # Nix LSP, for editing this repo in nvim
    nix-tree # find out what's eating your disk
    nh # nicer nixos-rebuild frontend
    nix-output-monitor
    comma # `, cowsay hi` — run a package once without installing it
    cachix # push/pull a personal binary cache for slow local builds

    # ---- backup ------------------------------------------------------------
    # The systemd service/timer wiring is in home/jerzy/backup.nix; these are
    # just the CLIs. One-time setup (rclone remote, restic password) is in
    # docs/BACKUP.md.
    restic
    rclone
  ];
}
