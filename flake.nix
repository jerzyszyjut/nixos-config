{
  description = "jerzy's machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # One color scheme + one font, applied to every app on the system.
    stylix = {
      url = "github:nix-community/stylix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, home-manager, nixos-hardware, stylix, sops-nix, ... }:
    let
      system = "x86_64-linux";

      # Anything you want newer than stable is reachable as pkgs.unstable.<name>.
      overlayUnstable = final: prev: {
        unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      };

      # =====================================================================
      # ONE MACHINE = ONE mkHost CALL.
      #
      # Everything below `common` is on every machine: the user, Hyprland, the
      # Stylix theme, WiFi, secrets. Everything else is opt-in through
      # `profiles`, which is how this repo serves both halves of your life
      # without a second copy of it:
      #
      #   profiles.work           nix-ld, Docker, C++/Python/k8s, LaTeX, Slack,
      #                           the editors and language servers
      #   profiles.entertainment  Prowlarr + Radarr + qBittorrent + Jellyfin,
      #                           the players, Spotify, Discord
      #
      # A new machine is then a handful of lines at the bottom of this file:
      # give it a directory under hosts/, say which profiles it wants, and
      # `nixos-rebuild switch --flake ~/nixos-config#<name>`. Nothing has to be
      # copied or deleted, and a work-only laptop never even builds Jellyfin.
      #
      # Each profile declares its own option and wraps its whole config in
      # `mkIf` — see modules/profiles/. The home-manager side reads the same
      # option through `osConfig`, so one line here moves both halves.
      # =====================================================================
      mkHost = { hostModule, profiles, hardwareModules ? [ ] }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            { nixpkgs.overlays = [ overlayUnstable ]; }

            stylix.nixosModules.stylix
            sops-nix.nixosModules.sops

            # ---- always on ----
            ./modules/nixos/base.nix
            ./modules/nixos/style.nix
            ./modules/nixos/desktop.nix
            ./modules/nixos/net.nix
            ./modules/nixos/secrets.nix

            # ---- opt-in ----
            ./modules/profiles/work.nix
            ./modules/profiles/entertainment.nix
            { inherit profiles; }

            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { inherit inputs; };
                users.jerzy = import ./home/jerzy;
                backupFileExtension = "hm-bak";
              };
            }

            hostModule
          ] ++ hardwareModules;
        };
    in
    {
      nixosConfigurations = {
        thinkpad = mkHost {
          hostModule = ./hosts/thinkpad;
          # ThinkPad E14 Gen 6 (Intel), machine type 21M7 — exact match exists.
          hardwareModules = [ nixos-hardware.nixosModules.lenovo-thinkpad-e14-intel-gen6 ];
          profiles = {
            work.enable = true;
            entertainment.enable = true;
            # Whether the media stack comes up with the machine. Not a
            # runtime switch: /etc/systemd/system is a read-only store
            # symlink, so `systemctl disable` has nowhere to write. The
            # media-autostart-on / media-autostart-off commands rewrite this
            # exact line and rebuild — keep it on one line for that reason.
            entertainment.autostart = false;
          };
        };

        # A second machine looks like this. Copy hosts/thinkpad to
        # hosts/<name>, replace hardware-configuration.nix with the one
        # `nixos-generate-config` produces on that box, set its hostName, and
        # uncomment:
        #
        # kino = mkHost {
        #   hostModule = ./hosts/kino;
        #   profiles.entertainment.enable = true;
        # };
      };

      # `nix flake init -t ~/nixos-config#cpp` in an empty directory to start a
      # new C++ project with CMake + Catch2/GTest/gbenchmark + clangd wired up
      # as a devShell, instead of installing those globally.
      templates.cpp = {
        path = ./templates/cpp;
        description = "C++ project: CMake, Catch2/GTest/gbenchmark, clangd devShell";
      };
    };
}
