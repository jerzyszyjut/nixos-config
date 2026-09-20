{ config, lib, pkgs, osConfig, ... }:

# The home-manager half of modules/profiles/media-server.nix — the handles you
# drive the stack with, for a shell ON the server. Every admin UI below is
# bound to 127.0.0.1, so these abbreviations only resolve here; from the
# laptop, ssh in (or forward the port) and use them there.

let
  hostname = osConfig.networking.hostName;

  units = [
    "jellyfin"
    "seerr"
    "radarr"
    "sonarr"
    "bazarr"
    "prowlarr"
    "qbittorrent"
    "flaresolverr"
    "homepage-dashboard"
  ];
in
lib.mkIf osConfig.profiles.mediaServer.enable {
  home.packages = with pkgs; [
    # Manual subtitle fetching, for when a film arrives without Polish
    # subtitles and Bazarr has not picked it up:
    #   subliminal download -l pl "Film (2024).mkv"
    #
    # There is no top-level `subliminal` attribute — it is packaged as a
    # Python library that happens to ship a CLI, so it has to be reached
    # through the package set. It lives on the server because this is where
    # the files it edits are.
    python313Packages.subliminal
  ];

  # The admin UIs, loopback-only by design, kept here for the days something
  # needs poking.
  #
  # The first three are also defined by the client profile, pointed at
  # `serverHost`. A host that enables BOTH profiles would then have two
  # definitions of one option and home-manager fails the build outright
  # rather than picking one — so these three are mkDefault and the client
  # wins wherever it is present. The result is the same page either way: on a
  # combined host `serverHost` defaults to localhost.
  programs.fish.shellAbbrs = {
    media = lib.mkDefault "xdg-open http://localhost:8082"; # Homepage — is everything up?
    seerr = lib.mkDefault "xdg-open http://localhost:5055"; # Seerr — add a film here
    jf = lib.mkDefault "xdg-open http://localhost:8096"; # Jellyfin — the one you watch in
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
    systemctl status --no-pager -n0 ${lib.concatStringsSep " " units}
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
  #
  # On a server you normally want autostart left on and never touch these;
  # they earn their keep while you are still wiring the stack up.
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

    if grep -q "mediaServer.autostart = $to;" $f
        echo "autostart juz jest $word"
        return 0
    end
    if not grep -q "mediaServer.autostart = $from;" $f
        echo "nie znalazlem linii 'mediaServer.autostart' w $f" >&2
        return 1
    end

    sed -i "s/mediaServer.autostart = $from;/mediaServer.autostart = $to;/" $f
    echo "autostart -> $word, przebudowuje..."
    sudo nixos-rebuild switch --flake $HOME/nixos-config#${hostname}
  '';
}
