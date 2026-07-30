{ config, lib, pkgs, ... }:

{
  # ---- compositor --------------------------------------------------------
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd Hyprland";
      user = "greeter";
    };
  };

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;

  # ---- portals -----------------------------------------------------------
  # This plus PipeWire is what makes SCREEN SHARING work in Slack and Discord
  # on Wayland. Skip it and screen share silently fails.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # ---- graphics ----------------------------------------------------------
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
      libvdpau-va-gl
    ];
  };

  # ---- audio -------------------------------------------------------------
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  hardware.bluetooth.enable = true;


  # ---- fonts -------------------------------------------------------------
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans # required for Chinese to render at all
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
      liberation_ttf
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only
    ];
    # NO fontconfig.defaultFonts here — Stylix owns that option, and setting it
    # in two places is asking for a conflict. Installing the CJK fonts below is
    # sufficient: fontconfig automatically falls back to any installed font for
    # glyphs the primary family lacks, so Chinese still renders.
  };

  # ---- Firefox -----------------------------------------------------------
  # Declared at system level because `policies` lets you force-install
  # extensions without any manual clicking — uBlock Origin and Bitwarden are
  # present on a fresh install.
  #
  # Verify the Bitwarden extension ID against about:debugging#/runtime/this-firefox
  # if it ever fails to appear.
  programs.firefox = {
    enable = true;
    policies = {
      DisableTelemetry = true;
      DisablePocket = true;
      DisableFirefoxStudies = true;
      ExtensionSettings = {
        "uBlock0@raymondhill.net" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
          installation_mode = "force_installed";
        };
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
          installation_mode = "force_installed";
        };
      };
    };
  };

  # ---- the bits GNOME used to do for you ---------------------------------
  environment.systemPackages = with pkgs; [
    # WM ecosystem
    waybar # status bar
    fuzzel # launcher
    mako # notifications
    hyprlock # screen locker
    hypridle # idle daemon
    hyprpaper # wallpaper
    hyprpolkitagent # GUI privilege prompts

    # clipboard & screenshots — you already use grim/slurp
    wl-clipboard
    cliphist
    grim
    slurp
    hyprshot # `hyprshot -m window -m active` needs no mouse

    # hardware controls the GNOME shell used to handle
    brightnessctl
    playerctl
    pavucontrol
    # wiremix  # TUI mixer; recent addition, may not be in this nixpkgs.
    #          # check: nix search nixpkgs wiremix
    pulsemixer # older, definitely present TUI mixer
    networkmanagerapplet
    blueman
    solaar # your Logitech receiver
  ];

  services.gvfs.enable = true;
  services.udisks2.enable = true;
  programs.dconf.enable = true;

  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true; # network printer discovery
  };
}
