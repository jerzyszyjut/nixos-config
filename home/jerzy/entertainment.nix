{ config, lib, pkgs, osConfig, ... }:

# The home-manager half of modules/profiles/entertainment.nix — the players
# and the shortcuts, where the profile module holds the services. Switched on
# from the same single option in flake.nix.

lib.mkIf osConfig.profiles.entertainment.enable {
  home.packages = with pkgs; [
    # ---- watching ----------------------------------------------------------
    # Jellyfin's web UI works fine in Firefox, but the desktop client gets you
    # hardware decoding through its bundled mpv instead of the browser's
    # decoder, which on a laptop is the difference between a warm palm rest
    # and a loud one. Same server, same library, nicer playback.
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

    # ---- subtitles ---------------------------------------------------------
    # Manual fetching, for when a film arrives without Polish subtitles and
    # you have not enabled Bazarr in the profile module yet:
    #   subliminal download -l pl "Film (2024).mkv"
    #
    # There is no top-level `subliminal` attribute — it is packaged as a Python
    # library that happens to ship a CLI, so it has to be reached through the
    # package set.
    python313Packages.subliminal
  ];

  # `media` and `seerr` are the two you will actually type. The rest are the
  # admin UIs, loopback-only by design, kept here for the days something needs
  # poking.
  programs.fish.shellAbbrs = {
    media = "xdg-open http://localhost:8082"; # Homepage — is everything up?
    seerr = "xdg-open http://localhost:5055"; # Seerr — add a film here
    jf = "xdg-open http://localhost:8096"; # Jellyfin — the one you watch in
    rad = "xdg-open http://localhost:7878"; # Radarr — admin, rarely needed
    son = "xdg-open http://localhost:8989"; # Sonarr — same, for series
    prow = "xdg-open http://localhost:9696"; # Prowlarr — trackers
    baz = "xdg-open http://localhost:6767"; # Bazarr — subtitles
    qbt = "xdg-open http://localhost:8080"; # qBittorrent — raw transfers
  };

  # Homepage answers this too, in colour. This is for when the reason a tile
  # went red is the interesting part.
  # One line on purpose: a trailing backslash would be passed through
  # literally, because Nix's indented strings do not treat it as an escape.
  programs.fish.functions.media-status = ''
    systemctl status --no-pager -n0 jellyfin seerr radarr sonarr bazarr prowlarr qbittorrent flaresolverr homepage-dashboard
  '';

  # ---- the four handles ----------------------------------------------------
  # Start/stop go through media.target, which every unit is PartOf, so one
  # command moves all nine. Downloads in flight are not lost: qBittorrent
  # writes its resume data on shutdown and picks them back up on start.
  programs.fish.functions.media-up = ''
    sudo systemctl start media.target; and echo "media: up"
  '';

  programs.fish.functions.media-down = ''
    sudo systemctl stop media.target; and echo "media: down"
  '';

  # Autostart is config, not runtime state, because /etc/systemd/system is a
  # symlink into the read-only store — `systemctl disable` cannot persist
  # anything. So these two rewrite the option in flake.nix and rebuild, which
  # is why they take ~30s and ask for a password. They deliberately refuse to
  # do anything if the expected line is not there, rather than sed silently
  # matching nothing and reporting success.
  programs.fish.functions.media-autostart-on = ''
    __media_autostart false true "wlaczony"
  '';

  programs.fish.functions.media-autostart-off = ''
    __media_autostart true false "wylaczony"
  '';

  programs.fish.functions.__media_autostart = ''
    set -l from $argv[1]
    set -l to $argv[2]
    set -l word $argv[3]
    set -l f $HOME/nixos-config/flake.nix

    if grep -q "entertainment.autostart = $to;" $f
        echo "autostart juz jest $word"
        return 0
    end
    if not grep -q "entertainment.autostart = $from;" $f
        echo "nie znalazlem linii 'entertainment.autostart' w $f" >&2
        return 1
    end

    sed -i "s/entertainment.autostart = $from;/entertainment.autostart = $to;/" $f
    echo "autostart -> $word, przebudowuje..."
    sudo nixos-rebuild switch --flake $HOME/nixos-config#thinkpad
  '';
}
