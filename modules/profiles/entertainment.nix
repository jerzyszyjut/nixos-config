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

    tvp = {
      enable = lib.mkEnableOption ''
        a Polish exit for TVP only: Firefox sends *.tvp.pl through Mullvad's
        SOCKS proxy in Warsaw, everything else goes out as usual.

        Needs its own Mullvad device key in sops as mullvad/tvp_key
      '';

      address = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "The address Mullvad assigned to the mullvad/tvp_key device.";
      };

      domains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "tvp.pl" "tvp.info" "redcdn.pl" ];
        description = ''
          Domains (and their subdomains) sent through Poland. tvp.pl covers
          the site, api.tvp.pl's geo check, the player and the stream CDN;
          redcdn.pl is the CDN TVP has used for some streams. The geo check
          and the stream must leave from the same country, so keep them
          together.
        '';
      };
    };
  };

  # =========================================================================
  # TVP FROM ABROAD, WITHOUT A FULL VPN
  #
  # The tunnel carries exactly one address: Mullvad's in-tunnel SOCKS5
  # proxy, 10.64.0.1, which exits wherever the tunnel lands — Warsaw here.
  # allowedIPs is that /32, so the only route the interface adds is for
  # that /32; nothing else on the machine can end up in it by accident.
  #
  # Choosing WHAT goes through it is then Firefox's job, via a PAC file:
  # TVP domains to the proxy, everything else DIRECT. Name resolution for
  # proxied requests happens at the proxy (SOCKS5 with remote DNS), so TVP
  # also sees a Polish resolver, not just a Polish address.
  #
  # Firefox only. Other programs are untouched — which is the point.
  # =========================================================================
  config = lib.mkIf (cfg.enable && cfg.tvp.enable) {
    sops.secrets."mullvad/tvp_key".mode = "0400";

    networking.wireguard.interfaces.wg-tvp = {
      ips = [ cfg.tvp.address ];
      privateKeyFile = config.sops.secrets."mullvad/tvp_key".path;
      peers = [{
        # pl-waw-wg-202 (M247). Not just any Warsaw server: TVP's CDN
        # answers 403 to the DataPacket-hosted ones (101-103), while the
        # M247 pair gets the stream. Tested 2026-09-25.
        publicKey = "nyfOkamv1ryTS62lsmyU96cqI0dtqek84DhyxWgAQGY=";
        endpoint = "146.70.144.34:51820";
        allowedIPs = [ "10.64.0.1/32" ];
        persistentKeepalive = 25;
      }];
    };

    environment.etc."firefox/tvp.pac".text = ''
      function FindProxyForURL(url, host) {
        var d = ${builtins.toJSON cfg.tvp.domains};
        for (var i = 0; i < d.length; i++)
          if (host === d[i] || dnsDomainIs(host, "." + d[i]))
            return "SOCKS5 10.64.0.1:1080";
        return "DIRECT";
      }
    '';

    programs.firefox.policies.Proxy = {
      Mode = "autoConfig";
      AutoConfigURL = "file:///etc/firefox/tvp.pac";
      UseProxyForDNS = true;
      Locked = false;
    };

    assertions = [{
      assertion = cfg.tvp.address != "";
      message = "profiles.entertainment.tvp.enable needs tvp.address from the Mullvad device.";
    }];
  };
}
