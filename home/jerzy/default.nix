{ config, lib, pkgs, ... }:

let
  # Where this repo lives on disk. mkOutOfStoreSymlink points at the real
  # working copy rather than a read-only /nix/store path, so you can edit your
  # nvim/fish/hypr config and see the change immediately — no rebuild. This is
  # the trick that keeps dotfiles editable AND portable to the TASK nodes.
  repo = "${config.home.homeDirectory}/nixos-config";
in
{
  imports = [
    ./ssh.nix
    ./apps.nix
    ./waybar.nix
    ./packages.nix
    ./backup.nix
  ];

  home.username = "jerzy";
  home.homeDirectory = "/home/jerzy";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  # =======================================================================
  # PORTABLE DOTFILES
  #
  # Plain files in dotfiles/, symlinked here. The same directory can be
  # git-cloned onto any remote box and used as-is, because nothing in it
  # is Nix-generated. Anything you'd want on a remote Ubuntu box goes here.
  # =======================================================================
  xdg.configFile = {
    "nvim".source = config.lib.file.mkOutOfStoreSymlink "${repo}/dotfiles/nvim";
    "btop".source = config.lib.file.mkOutOfStoreSymlink "${repo}/dotfiles/btop";

    # Machine-specific, so Nix-managed would be fine — but keeping these as
    # dotfiles means you can tweak keybinds without a rebuild, which matters a
    # lot while you're still learning Hyprland.
    "hypr".source = config.lib.file.mkOutOfStoreSymlink "${repo}/dotfiles/hypr";
    # waybar is NOT symlinked — it's managed in waybar.nix so its stylesheet
    # can interpolate the Stylix colors. It's never needed on a remote server,
    # so the portability argument doesn't apply.
  };

  home.file.".tmux.conf".source =
    config.lib.file.mkOutOfStoreSymlink "${repo}/dotfiles/tmux.conf";

  # ---- git ---------------------------------------------------------------
  programs.git = {
    enable = true;
    lfs.enable = true;
    settings = {
      user.name = "jerzyszyjut";
      user.email = "jerzy.szyjut@outlook.com";
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      rerere.enabled = true;
      diff.algorithm = "histogram";
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };

  programs.gh.enable = true;
  programs.lazygit.enable = true;

  # ---- shell -------------------------------------------------------------
  programs.fish = {
    enable = true;
    shellAliases = {
      cat = "bat";
      ls = "eza";
      ll = "eza -l --git";
      nrs = "sudo nixos-rebuild switch --flake ~/nixos-config#thinkpad";
      nrt = "sudo nixos-rebuild test --flake ~/nixos-config#thinkpad";
    };

    shellAbbrs = {
      # kitty's ssh kitten: ships terminfo to the remote host automatically,
      # so nothing on the remote hosts needs configuring.
      s = "kitten ssh";
    };
  };

  programs.starship.enable = true;

  # ---- fish plugins ------------------------------------------------------
  # Replaces Oh My Fish, declaratively. `done` is the sleeper hit: it fires a
  # desktop notification when a long command finishes, which is exactly what
  # you want when a remote training job or a nixos-rebuild is running in
  # another workspace.
  programs.fish.plugins = [
    { name = "done"; src = pkgs.fishPlugins.done.src; }
    { name = "sponge"; src = pkgs.fishPlugins.sponge.src; }
    { name = "autopair"; src = pkgs.fishPlugins.autopair.src; }
    { name = "puffer"; src = pkgs.fishPlugins.puffer.src; }
    { name = "colored-man-pages"; src = pkgs.fishPlugins.colored-man-pages.src; }
  ];

  # ---- direnv ------------------------------------------------------------
  # nix-direnv adds flake caching, so entering a project directory activates
  # its devShell instantly. This is how you stop installing toolchains globally.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableFishIntegration = true;
  };

  # ---- atuin -------------------------------------------------------------
  # Searchable shell history in a database instead of a flat file. With a
  # laptop plus several remote hosts, this is a bigger daily win than any
  # editor plugin. Run `atuin register` (or `atuin login`) once to sync;
  # it works fine purely locally too if you'd rather not.
  programs.atuin = {
    enable = true;
    enableFishIntegration = true;
    flags = [ "--disable-up-arrow" ]; # keeps fish's own up-arrow behaviour
    settings = {
      style = "compact";
      inline_height = 20;
      search_mode = "fuzzy";
    };
  };

  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
  };
  programs.bat.enable = true;
  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  # GTK, Qt, icon and cursor theming are all owned by Stylix now — see
  # modules/nixos/style.nix. Declaring them here as well would conflict.

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    MANPAGER = "nvim +Man!";
    # Wayland hints — matters for the Electron apps you kept (Discord, Slack,
    # Spotify, VS Code).
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    MOZ_ENABLE_WAYLAND = "1";
  };
}
