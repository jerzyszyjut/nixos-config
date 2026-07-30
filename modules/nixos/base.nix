{ config, lib, pkgs, ... }:

{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "@wheel" ];
  };

  # The Nix store grows without bound if left alone. Keep this aggressive.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;

  nixpkgs.config.allowUnfree = true;

  # ---- locale & keyboard -------------------------------------------------
  time.timeZone = "Europe/Warsaw";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_TIME = "pl_PL.UTF-8";
    LC_PAPER = "pl_PL.UTF-8";
    LC_MEASUREMENT = "pl_PL.UTF-8";
    LC_MONETARY = "pl_PL.UTF-8";
  };
  i18n.supportedLocales = [
    "en_US.UTF-8/UTF-8"
    "pl_PL.UTF-8/UTF-8"
  ];

  services.xserver.xkb = {
    layout = "pl";
    model = "pc105";
  };
  console.useXkbConfig = true; # your VC keymap is currently unset

  # ---- keyd: Caps Lock -> Escape -----------------------------------------
  # System level, so it applies in the TTY, in Hyprland, and inside every
  # application without exception. This is the single best change you can make
  # for living in Neovim on a laptop keyboard.
  #
  # If you later want home-row mods, this is where they go — keyd supports
  # layers and tap/hold. Start simple.
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings.main.capslock = "esc";
    };
  };

  # ---- user --------------------------------------------------------------
  users.users.jerzy = {
    isNormalUser = true;
    description = "jerzy";
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
      "video"
      "input"
      "dialout"
      "kvm"
    ];
  };

  # Must be enabled at system level too, or fish won't pick up Nix
  # completions and PATH entries correctly.
  programs.fish.enable = true;

  security.sudo.wheelNeedsPassword = true;

  # University / work CA certificates — you have a ~/certificates directory.
  # security.pki.certificateFiles = [ ./certs/some-ca.crt ];

  environment.systemPackages = with pkgs; [
    git
    neovim
    wget
    curl
    pciutils
    usbutils
    lm_sensors
    file
    tree
    ncdu # replaces filelight; keyboard-driven disk usage
  ];

  environment.variables.EDITOR = "nvim";

  services.fwupd.enable = true; # replaces Ubuntu's firmware-updater snap
  # NB: system.stateVersion lives in hosts/thinkpad/default.nix — defining it
  # in two modules is a conflict, not a merge.
}
