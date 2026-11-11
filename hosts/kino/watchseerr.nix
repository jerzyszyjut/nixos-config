{ config, lib, pkgs, inputs, ... }:

# watchseerr (github:jerzyszyjut/watchseerr): every hour, whatever is on the
# watchlists below becomes a request in Seerr, made as the Seerr user named
# here, so it goes through the usual approval and on to Radarr/Sonarr.
# Serializd requests only the seasons that are on the watchlist.
#
# Anything requested once is remembered (/var/lib/watchseerr/state.json) and
# never asked for again, so declining it in Seerr sticks. Requests are only
# ever added: taking a film off the watchlist does not cancel it.
#
#   journalctl -u watchseerr                      what the last pass did
#   systemctl start watchseerr                    a pass now
let
  # Seerr keeps its API key in its own settings file. Copying it out to a
  # root-only file in /run at boot keeps it out of this public repo and out
  # of the Nix store, and follows Seerr if the key is ever regenerated.
  keyFile = "/run/watchseerr/seerr-api-key";
in
{
  imports = [ inputs.watchseerr.nixosModules.default ];

  services.watchseerr = {
    enable = true;
    seerrUrl = "http://127.0.0.1:5055";
    apiKeyFile = keyFile;
    interval = "hourly";
    settings = {
      # At most this many requests per pass, so a long watchlist arrives over
      # a few hours instead of all at once.
      max_requests_per_run = 25;
      sources = [
        { type = "letterboxd"; user = "kosher67"; seerr_user = "jerzy"; }
        { type = "serializd"; user = "kosher67"; seerr_user = "jerzy"; }
      ];
    };
  };

  systemd.services.watchseerr-key = {
    description = "Copy Seerr's API key for watchseerr";
    after = [ "seerr.service" ];
    path = [ pkgs.jq pkgs.coreutils ];
    serviceConfig.Type = "oneshot";
    script = ''
      install -d -m 700 /run/watchseerr
      umask 077
      jq -er .main.apiKey /var/lib/seerr/settings.json > ${keyFile}
    '';
  };

  systemd.services.watchseerr = {
    requires = [ "watchseerr-key.service" ];
    after = [ "watchseerr-key.service" "seerr.service" ];
  };
}
