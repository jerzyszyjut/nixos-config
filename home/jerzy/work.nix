{ config, lib, pkgs, osConfig, ... }:

# The home-manager half of modules/profiles/work.nix. `osConfig` is the whole
# NixOS configuration, handed to every home-manager module because
# home-manager runs as a NixOS module here — so the profile is switched on in
# exactly one place (flake.nix) and both halves follow.

lib.mkIf osConfig.profiles.work.enable {
  home.packages = with pkgs; [
    # ---- GUI ---------------------------------------------------------------
    slack
    vscode # keeping this as the GUI fallback; drop if nvim sticks
    zed-editor # trying this out
    # Cursor dropped per your call.

    # ---- studying ----------------------------------------------------------
    # Vault/library paths and setup steps (Better BibTeX plugin, Typst
    # citation export) are in docs/STUDY-SETUP.md. Living in the work profile
    # rather than the base is a judgement call — move these three back to
    # packages.nix if you want them on a machine that does no development.
    obsidian
    anki
    (import ./zotero.nix { inherit pkgs; })

    # ---- Claude Code -------------------------------------------------------
    # You have ~/.claude and ~/.claude.json already. Pairs with
    # coder/claudecode.nvim — see the notes at the bottom of apps.nix.
    unstable.claude-code

    # ---- languages & package managers --------------------------------------
    uv # your Python workflow; works because of nix-ld in profiles/work.nix
    (python313.withPackages (ps: with ps; [ debugpy pynvim ]))
    nodejs_22
    yarn
    cookiecutter
    postgresql # psql client + the libpq headers you had via libpq-dev

    # ---- language servers for nvim -----------------------------------------
    # These replace everything mason would otherwise download. Adding a server
    # means adding it here AND to the `servers` table in dotfiles/nvim/init.lua.
    # The language-agnostic ones (nil, marksman, bash-language-server, stylua)
    # stay in packages.nix so nvim is still useful on a machine without this
    # profile.
    pyright
    ruff
    typescript-language-server # was nodePackages.*; that scope was removed
    yaml-language-server # your k8s manifests
    # dockerfile-language-server-nodejs  # renamed? nix search nixpkgs dockerfile-language
    vscode-langservers-extracted # jsonls, html, css

    # ---- TUI ---------------------------------------------------------------
    lazydocker
  ];

  # Duplicated from modules/profiles/work.nix's environment.variables.
  # LD_LIBRARY_PATH: that NixOS-level one lands in /etc/set-environment, which
  # only reaches PAM login sessions — it never actually made it into the
  # graphical (greetd -> Hyprland -> kitty -> fish) session on this machine
  # (verified: EDITOR from home.sessionVariables DID show up in Hyprland's own
  # environ, but LD_LIBRARY_PATH from environment.variables did not).
  # home-manager's session vars go through hm-session-vars.sh, which
  # demonstrably does reach the real shell, so set it here too.
  #
  # Read straight off the NixOS option instead of repeating the package list,
  # so the two can no longer drift apart.
  home.sessionVariables.LD_LIBRARY_PATH =
    lib.makeLibraryPath osConfig.programs.nix-ld.libraries;
}
