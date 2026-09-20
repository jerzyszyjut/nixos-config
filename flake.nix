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

      # Chromium-based apps (Spotify, Obsidian, Discord) died at startup on
      # this machine with "GPU process isn't usable. Goodbye." Recent Chromium
      # enables Vulkan by default, and its Vulkan path does not work under
      # `--ozone-platform=wayland` — Obsidian says so outright: "'--ozone-
      # platform=wayland' is not compatible with Vulkan". The GPU process dies
      # on startup and takes the whole app with it.
      #
      # Vulkan itself is healthy: vulkaninfo reports Intel Graphics (MTL) on
      # Mesa 26.1.8 with no errors, so this turns off Chromium's use of Vulkan
      # rather than falling back to XWayland. XWayland also works, but it gives
      # up crisp rendering on the 4K screen at scale 1.5, which is the whole
      # reason that scale is set in dotfiles/hypr/hyprland.conf.
      #
      # symlinkJoin, not overrideAttrs: this only puts a wrapper in front of a
      # binary that is already built, so nothing is recompiled. The .desktop
      # files use bare `Exec=spotify` / `Exec=Discord` resolved through PATH,
      # so launcher entries get the wrapper as well as the shell does.
      overlayChromiumNoVulkan = final: prev:
        let
          noVulkan = name: exes: pkg: prev.symlinkJoin {
            inherit name;
            paths = [ pkg ];
            nativeBuildInputs = [ prev.makeWrapper ];
            postBuild = prev.lib.concatMapStrings
              (exe: ''
                if [ -e "$out/bin/${exe}" ]; then
                  wrapProgram "$out/bin/${exe}" --add-flags "--disable-features=Vulkan"
                fi
              '')
              exes;
          };
        in
        {
          spotify = noVulkan "spotify" [ "spotify" ] prev.spotify;
          obsidian = noVulkan "obsidian" [ "obsidian" ] prev.obsidian;
          discord = noVulkan "discord" [ "discord" "Discord" ] prev.discord;
        };

      # =====================================================================
      # ONE MACHINE = ONE mkHost CALL.
      #
      # Everything below `common` is on every machine: the user, Hyprland, the
      # Stylix theme, WiFi, secrets. Everything else is opt-in through
      # `profiles`, which is how this repo serves both halves of your life
      # without a second copy of it:
      #
      #   profiles.work           nix-ld, Docker, C++/Python/k8s, LaTeX,
      #                           the editors and language servers
      #   profiles.entertainment  the players (jellyfin-media-player, mpv,
      #                           vlc), Spotify, Discord — clients only
      #   profiles.mediaServer    Prowlarr + Radarr + Sonarr + qBittorrent +
      #                           Jellyfin + Seerr — the services
      #
      # The last two are deliberately separate. They were one profile while
      # the ThinkPad hosted the library itself; now the server is its own
      # machine, the laptop keeps the players and enables `entertainment`
      # alone, while the server enables `mediaServer` and never builds a
      # desktop player it has no screen for.
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
            { nixpkgs.overlays = [ overlayUnstable overlayChromiumNoVulkan ]; }

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
            ./modules/profiles/media-server.nix
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

            # The players, Spotify and Discord. The services this talks to
            # moved off this machine — see `kino` below — so what is left
            # here is jellyfin-media-player pointed at the server over
            # Tailscale, and nothing that downloads or transcodes.
            entertainment.enable = true;
            entertainment.serverHost = "kino";

            # Explicit rather than merely absent: this laptop used to run the
            # whole stack, and the line is here so it is obvious that not
            # running it is a decision. See docs/SERVER-INSTALL.md for the
            # move, including what to do with the old /var/lib/media.
            mediaServer.enable = false;
          };
        };

        # ---- the server ----------------------------------------------
        # The always-on laptop that holds the library. Bring it up with
        # docs/SERVER-INSTALL.md: it walks the whole thing from writing the
        # USB stick to the first `nixos-install`, and ends at the point where
        # this entry is uncommented.
        #
        # It needs hosts/kino/hardware-configuration.nix, which only
        # `nixos-generate-config` running ON that machine can write. Until
        # that file exists this block must stay commented out — Nix cannot
        # evaluate a host whose disks it has never seen.
        #
        # No `work.enable`: a headless box needs neither Docker nor LaTeX.
        #
        # kino = mkHost {
        #   hostModule = ./hosts/kino;
        #   profiles = {
        #     mediaServer.enable = true;
        #     # Whether the stack comes up with the machine. Not a runtime
        #     # switch: /etc/systemd/system is a read-only store symlink, so
        #     # `systemctl disable` has nowhere to write. The
        #     # media-autostart-on / media-autostart-off commands rewrite
        #     # this exact line and rebuild — keep it on one line for that.
        #     mediaServer.autostart = true;
        #   };
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
