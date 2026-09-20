{ config, lib, pkgs, ... }:

let
  cfg = config.profiles.entertainment;
in
{
  # =========================================================================
  # THE "ROZRYWKA" PROFILE — the watching half.
  #
  # This is the CLIENT side: the players, Spotify, Discord, and the shell
  # abbreviations that open the server's web UIs. It installs no services and
  # stores no films, so it is cheap and belongs on every machine you actually
  # sit in front of.
  #
  # The stack it talks to — Prowlarr, Radarr, Sonarr, qBittorrent, Jellyfin,
  # Seerr — is `profiles.mediaServer` in modules/profiles/media-server.nix,
  # and lives on the machine that is always on. The two were one profile
  # while the ThinkPad did both jobs; splitting them is what lets the laptop
  # keep the players after the server moved out.
  #
  # Almost everything here is home-manager (home/jerzy/entertainment.nix),
  # because a media player is a user program, not a system one. This module
  # exists to declare the options both halves read.
  # =========================================================================
  options.profiles.entertainment = {
    enable = lib.mkEnableOption ''
      the entertainment profile: the media players (jellyfin-media-player,
      mpv, vlc), Spotify, Discord, and the shortcuts that open the media
      server's web UIs.

      Clients only — the services are `profiles.mediaServer`
    '';

    serverHost = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      example = "kino";
      description = ''
        Host the media server's web UIs are reached at, used to build the
        `jf`, `seerr` and `media` shell abbreviations.

        This should normally be the server's *Tailscale* name rather than a
        LAN address or IP: Jellyfin, Seerr and Homepage are all declared with
        `openFirewall = false` and are reachable only over tailscale0, which
        modules/nixos/net.nix marks trusted. A tailnet name also keeps
        working from outside the flat, which a LAN address does not.

        Left as "localhost" it addresses a server running on this same
        machine, which is the right answer if one host does both jobs.
      '';
    };
  };

  # Nothing system-level is needed for the clients themselves — mpv, vlc and
  # jellyfin-media-player are plain user packages, and the hardware decoding
  # they use comes from the Mesa/VA-API stack that modules/nixos/desktop.nix
  # already installs for every machine with a screen. So there is no `config`
  # block here at all; see home/jerzy/entertainment.nix for the real content.
}
