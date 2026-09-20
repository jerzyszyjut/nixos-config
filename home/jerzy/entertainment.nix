{ config, lib, pkgs, osConfig, ... }:

# The home-manager half of modules/profiles/entertainment.nix — the players
# and the shortcuts that open the media server's web UIs. Switched on from the
# same single option in flake.nix.
#
# Nothing here assumes the server is this machine. The abbreviations below are
# built from `profiles.entertainment.serverHost`, so the laptop opens the
# stack running on the server box, and the admin commands that only make sense
# next to the services live in home/jerzy/media-server.nix instead.

let
  cfg = osConfig.profiles.entertainment;

  # Kept in step with `ports` in modules/profiles/media-server.nix. Duplicated
  # rather than shared because the two halves now run on different machines:
  # on the laptop `osConfig.profiles.mediaServer` is disabled and its port
  # attrset is not evaluated at all.
  open = port: "xdg-open http://${cfg.serverHost}:${toString port}";
in
lib.mkIf cfg.enable {
  home.packages = with pkgs; [
    # ---- watching ----------------------------------------------------------
    # Jellyfin's web UI works fine in Firefox, but the desktop client gets you
    # hardware decoding through its bundled mpv instead of the browser's
    # decoder, which on a laptop is the difference between a warm palm rest
    # and a loud one. Same server, same library, nicer playback.
    #
    # On first launch it asks for the server address: http://<server>:8096,
    # using the Tailscale name — see `serverHost` in the profile module.
    jellyfin-media-player

    # mpv is the one that opens instantly when you just want to play a file
    # off disk without a library in the way. vlc stays for the awkward formats
    # and for casting to a TV.
    mpv
    vlc

    # ---- music -------------------------------------------------------------
    spotify

    # ---- talking -----------------------------------------------------------
    discord
  ];

  # `media` and `seerr` are the two you will actually type: the dashboard and
  # the place you add a film. The admin UIs (Radarr, Prowlarr, qBittorrent)
  # are bound to the server's loopback and are NOT reachable from here — ssh
  # to the server and use the abbreviations from media-server.nix, or forward
  # a port: `ssh -L 7878:localhost:7878 <server>`.
  programs.fish.shellAbbrs = {
    media = open 8082; # Homepage — is everything up?
    seerr = open 5055; # Seerr — add a film here
    jf = open 8096; # Jellyfin — the one you watch in
  };
}
