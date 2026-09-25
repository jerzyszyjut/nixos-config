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
      #   profiles.desktop        Hyprland, greetd, PipeWire, fonts,
      #                           Firefox, printing — anything with a screen
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
            ./modules/nixos/net.nix
            ./modules/nixos/secrets.nix

            # ---- opt-in ----
            # desktop.nix is here rather than above because `kino` is
            # headless: a laptop with the lid shut that nobody logs into
            # locally has no use for a compositor, and building one for it
            # cost several GB and produced a Hyprland that segfaulted on
            # every greetd login.
            ./modules/nixos/desktop.nix
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
            desktop.enable = true;
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
        # Lenovo Legion 5 15ITH6H (82JH), always on, holds the library.
        # docs/SERVER-INSTALL.md is how it was built.
        #
        # No `work.enable`: this box needs neither Docker nor LaTeX.
        kino = mkHost {
          hostModule = ./hosts/kino;

          # No exact 15ITH6H module exists in nixos-hardware, and the nearest
          # relative (lenovo-legion-16ithg6) is worse than nothing here — it
          # pulls in the NVIDIA prime and Ampere driver modules, which is the
          # opposite of what this machine wants. So the pieces are composed
          # directly instead:
          hardwareModules = [
            # Tiger Lake-H: microcode, plus the whole Intel GPU stack —
            # intel-media-driver, vpl-gpu-rt and intel-compute-runtime. That
            # is what gives Jellyfin QuickSync transcoding, and on Gen12 it
            # handles HEVC and tone mapping in hardware.
            nixos-hardware.nixosModules.common-cpu-intel

            # Blacklists nouveau and nvidia and then REMOVES the RTX 3060
            # from the PCI bus via udev, along with its audio and USB-C
            # functions. On a machine that never sleeps, an idle dGPU is
            # 10-15 W burned continuously for a card nothing will ever draw
            # on — this box transcodes with QuickSync and has no display
            # workload at all.
            nixos-hardware.nixosModules.common-gpu-nvidia-disable

            # fstrim.timer for the two NVMe drives.
            nixos-hardware.nixosModules.common-pc-ssd
          ];

          profiles = {
            # ---- qBittorrent through Mullvad --------------------------
            # Only qBittorrent uses this; see the long comment in
            # modules/profiles/media-server.nix for why that is structural
            # rather than a compromise. The private key is NOT here — it
            # lives at /var/lib/mullvad/private.key, mode 600, because
            # anything in a Nix option lands in the world-readable store.
            #
            # These three come from the WireGuard config Mullvad generates
            # (ch-zrh-wg-001, Zurich). None of them is secret: an address,
            # a server's public key, and a public endpoint.
            #
            # Only the IPv4 address is used. The config also assigns an
            # IPv6 one, and leaving it out means qBittorrent has no v6 path
            # through the tunnel — which is the safe direction to fail,
            # since a v6 route that bypassed the tunnel is exactly the leak
            # this whole arrangement exists to prevent.
            mediaServer.vpn.enable = true;
            mediaServer.vpn.address = "10.71.89.111/32";
            mediaServer.vpn.peer.publicKey = "chvEpRH+05o+ESv8QLzNyY3Phirsym0mUvF03Kt7oCo=";
            mediaServer.vpn.peer.endpoint = "193.32.127.71:51820";

            # Second tunnel, Warsaw (pl-waw-wg-101), for Jellyfin only: the
            # Polish IPTV channels (TVP, Polsat) are geo-blocked. Own key in
            # /var/lib/mullvad/streams.key, registered as its own device.
            mediaServer.vpn.streams.enable = true;
            mediaServer.vpn.streams.address = "10.141.29.3/32";
            mediaServer.vpn.streams.peer.publicKey = "fO4beJGkKZxosCZz1qunktieuPyzPnEVKVQNhzanjnA=";
            mediaServer.vpn.streams.peer.endpoint = "45.134.212.66:51820";

            # No desktop.enable: headless on purpose. A TTY and SSH over
            # Tailscale are the two ways in, and that is enough — the first
            # `tailscale up` has to be typed at the machine, which a TTY
            # handles fine.
            mediaServer.enable = true;
            # Whether the stack comes up with the machine. Not a runtime
            # switch: /etc/systemd/system is a read-only store symlink, so
            # `systemctl disable` has nowhere to write. The
            # media-autostart-on / media-autostart-off commands rewrite this
            # exact line and rebuild — keep it on one line for that reason.
            mediaServer.autostart = true;
          };
        };
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
