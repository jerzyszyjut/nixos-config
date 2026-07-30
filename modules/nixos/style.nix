{ config, lib, pkgs, ... }:

{
  # =======================================================================
  # ONE PLACE FOR HOW EVERYTHING LOOKS.
  #
  # Stylix applies this scheme to kitty, Hyprland borders, waybar, fuzzel,
  # mako, zathura, yazi, btop, GTK and Qt. Change it here, everything follows.
  # =======================================================================
  stylix = {
    enable = true;
    polarity = "dark"; # important: keeps a dark UI despite the bright wallpaper

    # ---- Gruvbox Material, dark medium -----------------------------------
    # Written inline rather than referencing base16-schemes, because the
    # `gruvbox-material-*` variants aren't reliably present in that package —
    # only plain `gruvbox-dark-*`, which has the harsher original contrast.
    # This is the Material palette: same warmth, softer foreground.
    #
    # To use a file from the package instead:
    #   ls ${pkgs.base16-schemes}/share/themes/ | grep gruvbox
    #   base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
    base16Scheme = {
      base00 = "282828"; # bg
      base01 = "32302f"; # lighter bg — status bars, line numbers
      base02 = "45403d"; # selection
      base03 = "5a524c"; # comments
      base04 = "928374"; # dark foreground
      base05 = "d4be98"; # default foreground
      base06 = "ddc7a1"; # light foreground
      base07 = "ebdbb2"; # lightest
      base08 = "ea6962"; # red — variables, diff deleted
      base09 = "e78a4e"; # orange — numbers, constants
      base0A = "d8a657"; # yellow — classes, search
      base0B = "a9b665"; # green — strings, diff added
      base0C = "89b482"; # aqua — escapes, regex
      base0D = "7daea3"; # blue — functions
      base0E = "d3869b"; # purple — keywords
      base0F = "d65d0e"; # brown — deprecated
    };

    # ---- wallpaper -------------------------------------------------------
    # I can't include the Windows XP "Bliss" image — it's a copyrighted
    # Microsoft photograph. Save your own copy as modules/nixos/wallpaper.jpg.
    #
    # It's 1600x1200 (4:3) and your panel isn't, so scaling matters:
    #   "fill"    crop to cover the screen — what you want for Bliss
    #   "fit"     letterbox with bars
    #   "stretch" distort to fit
    # DISABLED so the config evaluates out of the box. A Nix path literal must
    # exist at EVALUATION time, so pointing at a missing file fails the whole
    # build — not just the wallpaper.
    #
    # To enable, after first boot:
    #   cp yourimage.jpg modules/nixos/wallpaper.jpg
    #   git add modules/nixos/wallpaper.jpg      # flakes only see tracked files
    # then uncomment both lines below.
    #
    # imageScalingMode: "fill" crops to cover (right for a 4:3 image on a 16:10
    # panel), "fit" letterboxes, "stretch" distorts.
    #
    # image = ./wallpaper.jpg;
    # imageScalingMode = "fill";

    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
        # Narrower — fits noticeably more code per line on a 14" panel:
        # package = pkgs.nerd-fonts.iosevka;
        # name = "Iosevka Nerd Font";
      };
      sansSerif = {
        package = pkgs.inter;
        name = "Inter";
      };
      serif = {
        package = pkgs.noto-fonts;
        name = "Noto Serif";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
      sizes = {
        terminal = 12;
        applications = 11;
        desktop = 11;
        popups = 11;
      };
    };

    opacity.terminal = 0.95;

    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 24;
    };
  };

  # ---- Neovim ------------------------------------------------------------
  # Stylix's neovim target is OFF, and the colorscheme comes from the
  # `gruvbox-material` plugin inside dotfiles/nvim instead. Reason: Stylix
  # doesn't exist on the remote boxes, so a Stylix-themed editor would look
  # different on every machine you work on. The plugin travels with the config.
  #
  # If you'd rather Stylix generate it, flip this to true and delete the
  # colorscheme line from dotfiles/nvim/lua/custom/plugins/extras.lua.
  home-manager.users.jerzy.stylix.targets.neovim.enable = false;
}
