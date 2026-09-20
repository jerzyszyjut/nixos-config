{ config, lib, pkgs, ... }:

let
  cfg = config.profiles.mediaServer;

  # ---- where the films live ------------------------------------------------
  # Everything the stack touches sits under ONE directory on ONE btrfs
  # subvolume, and that is not cosmetic. Radarr imports a finished download
  # into the library by HARDLINKING it: the file appears in both places, takes
  # the space once, and qBittorrent keeps seeding the original. Hardlinks
  # cannot cross a filesystem boundary and btrfs counts every subvolume as its
  # own boundary — split downloads and library across subvolumes and Radarr
  # silently falls back to copying, so every film costs twice the disk.
  #
  # /var/lib rather than /home is deliberate too: the radarr, qbittorrent and
  # jellyfin units all run with systemd's ProtectHome=yes, so /home simply is
  # not visible to them. Nothing here is snapshotted or picked up by the
  # restic backup in home/jerzy/backup.nix, which is what you want for data
  # that is re-downloadable by definition.
  mediaRoot = "/var/lib/media";
  downloadDir = "${mediaRoot}/torrents";
  incompleteDir = "${downloadDir}/incomplete";
  moviesDir = "${mediaRoot}/library/movies";
  tvDir = "${mediaRoot}/library/tv";

  # Music sits under the SAME root as the torrents for exactly the reason the
  # comment above gives: Lidarr imports by hardlinking out of qBittorrent's
  # download directory, and a hardlink cannot cross a btrfs subvolume
  # boundary. Put the music library on its own subvolume and every album
  # silently costs twice the disk.
  musicDir = "${mediaRoot}/library/music";

  # Books do NOT have that constraint — nothing hardlinks them, they arrive
  # by hand — but they live here anyway because this is the disk with the
  # space, and because one backup-excluded tree is easier to reason about
  # than two.
  booksDir = "${mediaRoot}/library/books";

  # Drop an .epub here and CWA picks it up, fetches metadata, converts it and
  # files it into booksDir. Deliberately NOT inside library/: CWA deletes
  # what it has ingested, and a delete-happy watcher pointed anywhere near
  # the library is how you lose a collection.
  bookIngestDir = "${mediaRoot}/ingest/books";

  # slskd's downloads. Under mediaRoot for the same hardlink reason as
  # everything else: Lidarr imports finished Soulseek downloads into
  # ${musicDir}, and that only stays cheap while both are one filesystem.
  soulseekDir = "${mediaRoot}/soulseek";

  # Jellyfin's DVR writes here. Recordings are large and re-recordable, so
  # they get the same no-backup treatment as everything else under mediaRoot.
  dvrDir = "${mediaRoot}/dvr";

  # Kept in one place because the services have to be told about each other by
  # hand through their web UIs (see docs/MEDIA.md) and you will be typing
  # these numbers.
  ports = {
    qbittorrent = 8080; # web UI, 127.0.0.1 only
    torrenting = 51413; # the only port opened to the outside world
    prowlarr = 9696; # 127.0.0.1 only
    radarr = 7878; # 127.0.0.1 only
    sonarr = 8989; # 127.0.0.1 only
    bazarr = 6767; # 127.0.0.1 only, but only after the preStart below
    flaresolverr = 8191; # 127.0.0.1 only
    jellyfin = 8096; # LAN-closed, but reachable over Tailscale
    seerr = 5055; # ditto — this is the one you actually use
    homepage = 8082; # ditto — the status page
    lidarr = 8686; # 127.0.0.1 only — admin, like the other *arrs
    navidrome = 4533; # LAN-closed, Tailscale-reachable: the phone needs it
    cwa = 8083; # ditto — you open this from the laptop to send to Kindle
    threadfin = 34400; # 127.0.0.1 only — Jellyfin talks to it over loopback
    bookDownloader = 8084; # LAN-closed, Tailscale-reachable — you search here
    slskd = 5030; # ditto — the Soulseek web UI
    slskdListen = 50300; # the only OTHER port opened to the outside world
  };
in
{
  # =========================================================================
  # THE MEDIA SERVER PROFILE.
  #
  # Everything in here is a SERVICE, and it is meant for the box that is
  # always on — not for a laptop that closes its lid mid-download. The
  # players you watch with (jellyfin-media-player, mpv, vlc) are the separate
  # `profiles.entertainment`, which a laptop enables on its own; the two used
  # to be one profile and were split when the server moved to its own machine.
  #
  #   1337x ─┐
  #          ├─ Prowlarr ──→ Radarr ──→ qBittorrent ──→ library ──→ Jellyfin
  #   inne  ─┘   trackers    one click    download       hardlink    watching
  #
  # Prowlarr is the only thing that knows about trackers; it feeds their search
  # results to Radarr over a local API. In Radarr you search a film, press Add,
  # and it picks a release, hands the torrent to qBittorrent, waits for it,
  # renames the file into ${moviesDir} and tells Jellyfin to rescan. Jellyfin
  # is what you actually open to watch — in a browser, on the phone, or in the
  # jellyfin-media-player desktop app that `profiles.entertainment` installs
  # on the laptop, pointed at this machine over Tailscale.
  #
  # None of these services can be fully configured from Nix: the API keys they
  # authenticate to each other with are generated on first start and live in
  # each service's own database. docs/MEDIA.md is the ~10 minute click-through
  # that connects them, and it only has to be done once per machine.
  # =========================================================================
  options.profiles.mediaServer = {
    enable = lib.mkEnableOption ''
      the media server: Prowlarr, Radarr, Sonarr, Bazarr, qBittorrent,
      FlareSolverr, Jellyfin, Seerr and the Homepage dashboard.

      Services only. Turn this on for the machine that hosts the library, and
      `profiles.entertainment` on each machine you watch from
    '';

    autostart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether the media stack comes up with the machine.

        This has to be an option rather than something you flip at runtime:
        /etc/systemd/system is a symlink into the read-only store, so
        `systemctl enable`, `disable` and `mask` have nowhere to write their
        symlinks and cannot persist a change. Unit enablement on NixOS is
        config, not state.

        Setting this to false only unhooks media.target from boot — the
        services stay installed and `systemctl start media.target` still brings
        the whole stack up by hand.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # ---- the shared group ------------------------------------------------
    # qBittorrent writes a file, Radarr hardlinks and renames it, Jellyfin
    # reads it. Three different service users touching the same bytes, so they
    # meet in one group and the directories below are setgid (2775) so
    # everything created inside them inherits it.
    #
    # Two things have to line up for the hardlink step to work, and both are
    # easy to get wrong:
    #
    #   * fs.protected_hardlinks is 1 by default on NixOS, which means a
    #     process may only hardlink a file it owns OR has read+write on. With
    #     qBittorrent's default umask the file would be 0644 and Radarr, which
    #     only has group read, gets EPERM. Hence UMask=0002 on both units.
    #   * the *arr units run with PrivateUsers=true. That is fine for file
    #     access — DAC checks compare kernel-level uid/gid, not the mapped
    #     ones — but it is the reason to be careful and test rather than
    #     assume when adding another service here.
    users.groups.media = { };

    # So you can browse and delete this stuff from yazi without sudo.
    users.users.jerzy.extraGroups = [ "media" ];

    systemd.tmpfiles.settings."10-media" = {
      "${mediaRoot}".d = { user = "root"; group = "media"; mode = "2775"; };
      "${downloadDir}".d = { user = "qbittorrent"; group = "media"; mode = "2775"; };
      "${incompleteDir}".d = { user = "qbittorrent"; group = "media"; mode = "2775"; };
      "${mediaRoot}/library".d = { user = "radarr"; group = "media"; mode = "2775"; };
      "${moviesDir}".d = { user = "radarr"; group = "media"; mode = "2775"; };
      "${tvDir}".d = { user = "sonarr"; group = "media"; mode = "2775"; };
      "${musicDir}".d = { user = "lidarr"; group = "media"; mode = "2775"; };

      # Owned by the CWA container's user, which is created below purely so
      # these two directories have a non-root owner that the container can
      # map onto. Both are setgid into `media` like everything else, so
      # Navidrome-style read access by other services keeps working.
      "${booksDir}".d = { user = "cwa"; group = "media"; mode = "2775"; };
      "${mediaRoot}/ingest".d = { user = "cwa"; group = "media"; mode = "2775"; };
      "${bookIngestDir}".d = { user = "cwa"; group = "media"; mode = "2775"; };

      "${dvrDir}".d = { user = "jellyfin"; group = "media"; mode = "2775"; };

      # Soulseek downloads. Owned by slskd, group media so Lidarr can import
      # out of here and jerzy can clean up without sudo.
      "${soulseekDir}".d = { user = "slskd"; group = "media"; mode = "2775"; };
      "${soulseekDir}/complete".d = { user = "slskd"; group = "media"; mode = "2775"; };
      "${soulseekDir}/incomplete".d = { user = "slskd"; group = "media"; mode = "2775"; };
    };

    # State for the two containers, kept OUT of ${mediaRoot} on purpose: this
    # is configuration and databases, not re-downloadable media, so it lives
    # on the system disk where it is small and where a future backup would
    # actually want to find it.
    #
    # Threadfin's ids are numeric because the image hardcodes uid 31337 and
    # there is no host account to name — systemd-tmpfiles takes numbers here
    # perfectly well, and inventing a NixOS user just to own two directories
    # would be ceremony.
    systemd.tmpfiles.settings."11-media-containers" = {
      "/var/lib/cwa".d = { user = "cwa"; group = "cwa"; mode = "0750"; };
      "/var/lib/cwa/config".d = { user = "cwa"; group = "cwa"; mode = "0750"; };
      # Created empty so slskd can start before you have put credentials in
      # it. Without the file the unit fails outright on a missing
      # EnvironmentFile, which is a confusing way to learn you have not
      # made a Soulseek account yet.
      "/var/lib/slskd".d = { user = "slskd"; group = "slskd"; mode = "0750"; };
      "/var/lib/slskd/slskd.env".f = { user = "slskd"; group = "slskd"; mode = "0600"; };

      "/var/lib/threadfin".d = { user = "31337"; group = "31337"; mode = "0755"; };
      "/var/lib/threadfin/conf".d = { user = "31337"; group = "31337"; mode = "0755"; };
      "/var/lib/threadfin/tmp".d = { user = "31337"; group = "31337"; mode = "0755"; };
    };

    # btrfs is copy-on-write, and a torrent client writing 4 MiB pieces into
    # random offsets of a 20 GiB file is the worst case for it — the extent
    # tree fragments badly enough to slow down both seeding and playback.
    # chattr +C turns CoW off, but the kernel only honours it on an EMPTY file
    # or directory, and new files inherit it from the directory they are
    # created in. So it has to be applied to the incomplete-downloads
    # directory once, before anything lands there, which is what this does.
    # Files that were already downloaded keep their old behaviour; that is
    # harmless, and re-running this is a no-op.
    systemd.services.media-nocow = {
      description = "Disable btrfs CoW on the torrent scratch directory";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      before = [ "qbittorrent.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Not a failure worth blocking boot over: on a non-btrfs filesystem
        # chattr just returns an error and the stack works fine without it.
        ExecStart = "${pkgs.e2fsprogs}/bin/chattr +C ${incompleteDir}";
        SuccessExitStatus = [ "0" "1" ];
      };
    };

    # ---- qBittorrent -----------------------------------------------------
    # The headless build, driven by Radarr over its web API. Note that the
    # NixOS module rewrites qBittorrent.conf from serverConfig on EVERY start
    # whenever serverConfig is non-empty — so this attrset, not the web UI, is
    # the source of truth for these keys. Change a setting here, not there, or
    # the next restart reverts it.
    services.qbittorrent = {
      enable = true;
      group = "media";
      webuiPort = ports.qbittorrent;
      torrentingPort = ports.torrenting;
      # false on purpose: the firewall rule below opens ONLY the peer port.
      openFirewall = false;

      serverConfig = {
        # Without this qBittorrent refuses to start headless, waiting for
        # someone to accept its legal notice on a terminal nobody is watching.
        LegalNotice.Accepted = true;

        Preferences = {
          General.Locale = "en";
          WebUI = {
            # Bound to loopback, so the only ways in are this machine and an
            # SSH tunnel. That is also why dropping the login prompt for
            # localhost is not a hole worth worrying about — anyone who can
            # reach the port already has a shell on the box.
            Address = "127.0.0.1";
            LocalHostAuth = false;
          };
        };

        BitTorrent.Session = {
          DefaultSavePath = downloadDir;
          TempPath = incompleteDir;
          TempPathEnabled = true;

          # ---- NO SEEDING --------------------------------------------
          # Downloading for private use and *distributing* are separate acts
          # legally, and BitTorrent distributes by default. This turns that
          # off as hard as the protocol allows:
          #
          #   GlobalMaxRatio = 0          the share limit is met the instant
          #                               the download finishes, so the
          #                               torrent stops there
          #   GlobalMaxSeedingMinutes = 0 the same limit expressed in time,
          #                               belt and braces
          #   MaxRatioAction = 0          0 = STOP the torrent. The others are
          #                               1 = remove, 2 = super-seed (the
          #                               exact opposite of what you want),
          #                               3 = remove with content. Stop rather
          #                               than remove, because Radarr has to
          #                               still find the finished torrent in
          #                               the client to import it — cleanup is
          #                               Radarr's job afterwards, see
          #                               docs/MEDIA.md.
          #   GlobalUPSpeedLimit = 2048   2 MiB/s, and this one is NOT about
          #                               restraint — see below. Note that 0
          #                               means UNLIMITED in qBittorrent, not
          #                               "off", so zero would be the opposite
          #                               of a limit.
          #
          # The upload limit is deliberately generous, because it only applies
          # DURING a download. BitTorrent trades pieces: a peer that sends
          # nothing gets choked by everyone else and stops receiving, so
          # throttling the upload to near zero throttles the download with it.
          # That was the first attempt here (1 KiB/s) and it made transfers
          # crawl. Since the torrent stops the instant it completes, the total
          # amount sent is bounded by how long the download takes rather than
          # by this number — the limit exists to stop a swarm saturating the
          # uplink and making the laptop feel slow, not to limit sharing.
          #
          # Lower it if browsing gets choppy while something is downloading;
          # that is the symptom it is here to prevent.
          #
          # Worth being clear about what this is and is not: it minimises what
          # you distribute. It does not hide the IP address you download from,
          # which is what monitoring outfits actually record. That is a
          # separate decision about a VPN, not a qBittorrent setting.
          GlobalMaxRatio = 0.0;
          GlobalMaxSeedingMinutes = 0;
          MaxRatioAction = 0;
          GlobalUPSpeedLimit = 2048;

          # A laptop on battery does not want 500 half-open connections.
          # The two MaxActive* limits are only consulted when the queueing
          # system is on, so that has to be enabled alongside them.
          QueueingSystemEnabled = true;
          MaxActiveDownloads = 3;
          MaxActiveTorrents = 8;
          MaxConnections = 200;
        };
      };
    };

    # 0002 instead of the default 0022, so the file qBittorrent writes is
    # group-writable and Radarr is allowed to hardlink it. See the note on
    # protected_hardlinks above.
    systemd.services.qbittorrent.serviceConfig.UMask = "0002";

    # ---- Prowlarr --------------------------------------------------------
    # Indexer manager. 1337x, and every other tracker you add here, is defined
    # once in Prowlarr and pushed to Radarr automatically, so you never
    # configure a tracker twice.
    services.prowlarr = {
      enable = true;
      settings.server = {
        port = ports.prowlarr;
        bindaddress = "*";
      };
    };

    # ---- FlareSolverr ----------------------------------------------------
    # 1337x sits behind Cloudflare. Prowlarr's plain HTTP client gets a
    # challenge page instead of search results; FlareSolverr runs a headless
    # browser that solves it and hands the cookies back. Without this the
    # 1337x indexer tests green and then returns nothing.
    services.flaresolverr = {
      enable = true;
      port = ports.flaresolverr;
    };

    # The NixOS module exposes `port` but no bind address, so the upstream
    # default applies: `os.environ.get('HOST', '0.0.0.0')`, i.e. every
    # interface. With tailscale0 trusted that quietly put FlareSolverr on the
    # tailnet, contradicting the "127.0.0.1 only" note next to its port above.
    #
    # It holds no data of yours, but it is a service that fetches an arbitrary
    # URL in a real browser on request — a comfortable relay for anyone who can
    # reach it. Prowlarr talks to it over loopback, so nothing else needs to.
    systemd.services.flaresolverr.environment.HOST = "127.0.0.1";

    # ---- Radarr ----------------------------------------------------------
    # The one-click part: search a film, press Add, and it does the rest.
    services.radarr = {
      enable = true;
      group = "media";
      settings.server = {
        port = ports.radarr;
        bindaddress = "*";
      };
    };

    # The module hardens Radarr with UMask=0022; the hardlink import needs
    # 0002 for the same reason qBittorrent does. mkForce because the module
    # already defines this exact key.
    systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";

    # ---- Sonarr ----------------------------------------------------------
    # Radarr for TV series. Separate service because the two have genuinely
    # different jobs: Radarr wants one file, Sonarr tracks seasons and
    # episodes and keeps watching for the next one to air. They share the same
    # Prowlarr indexers and the same qBittorrent, and Seerr routes a request
    # to one or the other by whether TMDB calls it a movie or a series — which
    # is why a series request silently went nowhere until this existed.
    services.sonarr = {
      enable = true;
      group = "media";
      settings.server = {
        port = ports.sonarr;
        bindaddress = "*";
      };
    };

    # Same hardlink-import reason as Radarr above.
    systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0002";

    # ---- Lidarr ----------------------------------------------------------
    # Radarr for music. Same shape as the two above and the same wiring: it
    # asks Prowlarr for releases, hands the torrent to qBittorrent, then
    # hardlinks and renames the finished files into ${musicDir}.
    #
    # Worth knowing before you judge it: music is the weakest of the *arr
    # family, because it matches against MusicBrainz and an album that is
    # tagged badly, is a re-release, or is a live set will sit unmatched.
    # Lidarr is a good way to follow artists you care about and a poor way to
    # acquire a back catalogue in bulk.
    services.lidarr = {
      enable = true;
      group = "media";
      settings.server = {
        port = ports.lidarr;
        bindaddress = "*";
      };
    };

    # Same hardlink-import reason as Radarr and Sonarr.
    systemd.services.lidarr.serviceConfig.UMask = lib.mkForce "0002";

    # ---- slskd (Soulseek) ------------------------------------------------
    # The music equivalent of the book downloader below, and the answer to
    # "where do I find Polish music that no tracker has". Soulseek is not a
    # tracker — it is a network of people's personal music folders, which is
    # why it is strong on exactly the material an anglophone tracker is weak
    # on: bootlegs, live sets, Eastern European catalogue, out-of-print.
    #
    # slskd is the headless daemon with a web UI. It downloads into
    # ${soulseekDir}, and Lidarr can import from there into ${musicDir}.
    services.slskd = {
      enable = true;
      group = "media";

      # Reachable over Tailscale like the other things you actually open.
      openFirewall = false;

      # Soulseek credentials do NOT go here — settings land in the
      # world-readable Nix store. They come from the env file below, which
      # you create by hand once. See docs/SETUP-CHECKLIST.md.
      environmentFile = "/var/lib/slskd/slskd.env";

      settings = {
        web = {
          port = ports.slskd;
          # Listens everywhere; the firewall (tailscale0 only) is the gate,
          # same trade as Jellyfin and Navidrome.
          url_base = "/";
        };

        soulseek.listen_port = ports.slskdListen;

        directories = {
          downloads = "${soulseekDir}/complete";
          incomplete = "${soulseekDir}/incomplete";
        };

        # ---- SHARING, AND WHY IT IS ON --------------------------------
        # This is the one place in this config that deliberately sends your
        # data OUT, and it is the opposite of the torrent decision above,
        # where seeding is off.
        #
        # The reason is that Soulseek is not a swarm, it is a community with
        # manners. Sharing nothing is visible to everyone you download from,
        # and a large share of users auto-ban leechers outright — so a
        # non-sharing slskd does not merely feel rude, it stops working.
        #
        # Only ${musicDir} is exposed. Films, books and downloads in progress
        # are not. To turn this off, empty the list — and expect queues that
        # never advance.
        shares.directories = [ musicDir ];
      };
    };

    # slskd writes into the library-adjacent tree that Lidarr then imports
    # from, so it needs the same group-writable umask as qBittorrent for the
    # hardlink to be permitted. Same fs.protected_hardlinks reasoning.
    systemd.services.slskd.serviceConfig.UMask = lib.mkForce "0002";

    # ---- Navidrome -------------------------------------------------------
    # The music server, and the answer to "how do I listen to this on my
    # phone". It speaks the SUBSONIC API, which is the reason to pick it:
    # Subsonic is a decade-old de-facto standard with a dozen good mobile
    # clients, so you are not tied to a first-party app the way Jellyfin
    # music or Plexamp would tie you.
    #
    # It only ever READS ${musicDir} — Lidarr owns that tree, Navidrome
    # indexes it. Hence group = "media" and no write anywhere near it.
    #
    # Jellyfin can serve music too, and deliberately is not: its music UI and
    # its mobile story are both markedly worse, and pointing two scanners at
    # one tree doubles the I/O for no gain.
    services.navidrome = {
      enable = true;
      group = "media";

      # Unlike the *arr admin UIs this is NOT loopback-bound. The phone has
      # to reach it, and the phone reaches it over Tailscale — so it listens
      # on all interfaces and the firewall (which trusts tailscale0 and
      # nothing else) is what keeps the LAN out. Same trade Jellyfin and
      # Seerr already make.
      openFirewall = false;
      settings = {
        Address = "0.0.0.0";
        Port = ports.navidrome;
        MusicFolder = musicDir;

        # Scan on a timer rather than only at startup: Lidarr drops new
        # albums in whenever a release lands, and a server that only notices
        # them on restart is a server you restart for no reason.
        ScanSchedule = "@every 1h";

        # Transcoding for mobile data. Navidrome ships the ffmpeg-backed
        # profiles but leaves them off by default; turning this on lets a
        # client ASK for a lower bitrate, which is what you want on a train.
        # It does not force transcoding on wifi — the client decides.
        EnableTranscodingConfig = true;

        # Subsonic's legacy auth sends a salted token derived from the
        # password, so the server needs it recoverable rather than hashed.
        # That is a property of the protocol, not of Navidrome — treat these
        # credentials as disposable and do not reuse a real password.
        EnableInsightsCollector = false;
      };
    };

    # ---- Bazarr ----------------------------------------------------------
    # Subtitles for what Radarr and Sonarr have already imported. It talks to
    # both over their APIs, notices what they add, and drops .srt files next
    # to the video. Polish subtitles are the whole reason it is here:
    # napiprojekt and OpenSubtitles are both in its provider list.
    #
    # It needs the media group because it WRITES into the library directories,
    # which are 2775 radarr:media and 2775 sonarr:media.
    services.bazarr = {
      enable = true;
      group = "media";
      listenPort = ports.bazarr;
    };

    # Same reason as Radarr and Sonarr above: the .srt files it writes have to
    # stay group-writable, so those two can rename them alongside the video
    # when a release is later upgraded.
    systemd.services.bazarr.serviceConfig.UMask = lib.mkForce "0002";

    # Bazarr has no bind-address option — not in the NixOS module and not on
    # the command line. The listen address lives in its own config.yaml and
    # defaults to '*', meaning every interface. Because net.nix puts
    # tailscale0 in trustedInterfaces, that default would hand an
    # unauthenticated admin panel to the whole tailnet, while every other
    # admin service in this profile is deliberately 127.0.0.1-only.
    #
    # So seed the address before the first start. Bazarr creates this file
    # empty on first run and fills everything else in from its own defaults,
    # so this one key is enough. The guard means an existing config is never
    # touched: change the address in Settings -> General later and it sticks.
    systemd.services.bazarr.preStart = ''
      cfg="${config.services.bazarr.dataDir}/config/config.yaml"
      if [ ! -e "$cfg" ]; then
        mkdir -p "$(dirname "$cfg")"
        printf 'general:\n  ip: 0.0.0.0\n' > "$cfg"
      else
        # Bazarr writes this file itself, so the seed above only ever runs
        # once. A config.yaml left over from when it was loopback-bound has
        # to be corrected in place, or the change silently does nothing.
        # Narrow on purpose: only this one value, only if it is the old one.
        ${pkgs.gnused}/bin/sed -i 's/^\(\s*\)ip: 127\.0\.0\.1\s*$/\1ip: 0.0.0.0/' "$cfg"
      fi
    '';

    # ---- Jellyfin --------------------------------------------------------
    # The library and the player. Point it at ${moviesDir} on first run.
    services.jellyfin = {
      enable = true;
      group = "media";

      # Left closed to the LAN deliberately. net.nix already trusts the
      # tailscale0 interface wholesale, so the phone and any other tailnet
      # device reach http://thinkpad:8096 without opening a port to whatever
      # café WiFi you happen to be on.
      openFirewall = false;

      # Core Ultra 7 155H — Meteor Lake's Arc iGPU. QSV rather than plain
      # VAAPI: same driver underneath, but Jellyfin's QSV path uses Intel's
      # oneVPL runtime (vpl-gpu-rt, already installed in desktop.nix) and
      # handles 10-bit HEVC and AV1 that this chip decodes in fixed function
      # hardware. The alternative is the CPU chewing through a 4K stream and
      # the fans making it obvious.
      hardwareAcceleration = {
        enable = true;
        type = "qsv";
        device = "/dev/dri/renderD128";
      };

      transcoding = {
        enableHardwareEncoding = true;
        enableToneMapping = true; # HDR film on an SDR laptop panel
        enableSubtitleExtraction = true;
        hardwareDecodingCodecs = {
          h264 = true;
          hevc = true;
          hevc10bit = true;
          vp9 = true;
          av1 = true;
        };
        hardwareEncodingCodecs.hevc = true;
      };

      # Makes the two blocks above authoritative: encoding.xml is rewritten
      # from them on every start. Same trade as everywhere else in this repo —
      # transcoding settings changed in Jellyfin's dashboard are lost on the
      # next restart, so change them here. Set this to false if you would
      # rather tune it by clicking.
      forceEncodingConfig = true;
    };

    # Jellyfin's QSV tone-mapping path (the HDR-to-SDR step enabled above)
    # goes through OpenCL, and Intel's OpenCL runtime is not part of the
    # driver set desktop.nix installs for the desktop itself. Without it
    # transcoding still works, it just silently stops tone mapping and HDR
    # films come out washed out and grey. extraPackages is a list, so this
    # appends to what desktop.nix already declares.
    #
    # `enable` matters on a HEADLESS server and is easy to miss: it used to
    # come from modules/nixos/desktop.nix, which every machine got. Now that
    # the desktop is opt-in, a server without it would have no
    # /run/opengl-driver at all — vainfo would find no driver and Jellyfin
    # would fall back to software transcoding with nothing in the log saying
    # why. Video acceleration is not a desktop feature.
    hardware.graphics.enable = true;
    hardware.graphics.extraPackages = [ pkgs.intel-compute-runtime ];

    # ---- Seerr (was Jellyseerr) ------------------------------------------
    # THE ONE YOU ACTUALLY OPEN. Radarr's UI is an admin tool — it asks about
    # quality profiles and release groups. Seerr sits in front of it and looks
    # like a streaming service: it logs you in with your Jellyfin account,
    # shows Discover/Trending with posters, and a film you pick goes straight
    # to Radarr as a request. After the one-time setup you can stop opening
    # Radarr, Prowlarr and qBittorrent entirely.
    #
    # It also knows what Jellyfin already has, so the library and the "add"
    # button are the same screen rather than two.
    #
    # Renamed upstream: services.jellyseerr became services.seerr in 26.05,
    # with the old name kept as an alias.
    services.seerr = {
      enable = true;
      port = ports.seerr;
      # Same reasoning as Jellyfin: closed to the LAN, reachable over the
      # already-trusted tailscale0, so you can queue a film from the phone.
      openFirewall = false;
    };

    # =====================================================================
    # THE TWO CONTAINERS
    #
    # Everything else in this file is a native NixOS module, which is the
    # pattern worth keeping: the package comes from the flake, updates arrive
    # with `nix flake update`, and the whole thing rolls back with the
    # generation. These two are the exceptions, for the same reason in both
    # cases — nobody has packaged them.
    #
    #   Calibre-Web-Automated  Not in nixpkgs. Plain calibre-web IS, but it
    #                          is a different program: no ingest folder, no
    #                          automatic conversion, no metadata fetch.
    #   Threadfin              Not in nixpkgs. xTeVe is, but it is the
    #                          unmaintained project Threadfin forked from,
    #                          last released in 2020.
    #
    # The cost is real and worth stating: these two update by image tag, not
    # by flake.lock, so `nixos-rebuild` does NOT move them and a rollback
    # does NOT bring the old one back. Pinning by digest below is what keeps
    # that from being a surprise — see the comment there.
    # =====================================================================
    virtualisation.podman = {
      enable = true;
      # Rootless by default for user containers, but these run as system
      # services. No dockerCompat: nothing here wants a `docker` command, and
      # aliasing it would collide with profiles.work on a machine that
      # enabled both.
      dockerCompat = false;
      defaultNetwork.settings.dns_enabled = true;
    };
    virtualisation.oci-containers.backend = "podman";

    # The account the CWA container's files belong to on the host. It exists
    # only so that ${booksDir} has a sane owner: LinuxServer images run their
    # process as PUID:PGID and chown what they touch, and pointing that at
    # root or at a real user is how a library ends up unreadable by anything
    # else.
    users.users.cwa = {
      isSystemUser = true;
      group = "cwa";
      extraGroups = [ "media" ];
      description = "Calibre-Web-Automated container owner";
    };
    users.groups.cwa = { };

    # PUID/PGID have to be NUMBERS, and neither number is known at build
    # time: NixOS allocates the cwa uid and the media gid at activation. So
    # they are looked up at start and written to an env file the container
    # reads, rather than hardcoded — hardcoding them is the bug where the
    # library works until the day a uid shifts and every file belongs to
    # nobody.
    systemd.services.cwa-env = {
      description = "Resolve uid/gid for the Calibre-Web-Automated container";
      wantedBy = [ "media.target" ];
      before = [ "podman-cwa.service" "podman-book-downloader.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "cwa-env" ''
          set -euo pipefail
          umask 022

          # /etc/group is parsed directly rather than with getent, which is
          # NOT part of coreutils — pointing at ${"$"}{pkgs.coreutils}/bin/getent
          # gave "No such file or directory", and because that failure
          # happened inside a command substitution it did not stop the
          # script: PGID came out EMPTY, the LinuxServer image fell back to
          # its built-in gid 911, and it chowned the whole book library to a
          # group that does not exist on this host.
          puid="$(${pkgs.coreutils}/bin/id -u cwa)"
          pgid="$(${pkgs.gnugrep}/bin/grep '^media:' /etc/group | ${pkgs.coreutils}/bin/cut -d: -f3)"

          # Fail LOUDLY. The first version of this reported success while
          # writing a broken file, which is how the bug above survived a
          # reboot unnoticed.
          if [ -z "$puid" ] || [ -z "$pgid" ]; then
            echo "cwa-env: nie udalo sie ustalic uid cwa ($puid) albo gid media ($pgid)" >&2
            exit 1
          fi

          # Both spellings on purpose: the LinuxServer CWA image reads
          # PUID/PGID, the downloader image reads UID/GID. One file, two
          # conventions, no second service to keep in step.
          ${pkgs.coreutils}/bin/printf 'PUID=%s\nPGID=%s\nUID=%s\nGID=%s\nTZ=%s\n' \
            "$puid" "$pgid" "$puid" "$pgid" "${config.time.timeZone}" > /run/cwa.env
        '';
      };
    };

    virtualisation.oci-containers.containers.cwa = {
      # Pinned by DIGEST, not by :latest. A tag is a moving target, and
      # `podman pull` on a restart would silently swap the running version —
      # which for a program that rewrites your book metadata in place is not
      # a risk worth taking for convenience. Update deliberately:
      #   skopeo inspect docker://docker.io/crocodilestick/calibre-web-automated:latest
      # then paste the new digest here and rebuild.
      image = "docker.io/crocodilestick/calibre-web-automated@sha256:c31a738b6d5ec6982c050063dd3f063b6943eb1051fc81144789f840d9093a8d";

      environmentFiles = [ "/run/cwa.env" ];

      volumes = [
        # Its own database and settings — including, once you set it up in
        # the UI, the SMTP credentials for Send-to-Kindle.
        "/var/lib/cwa/config:/config"
        # Watched. Drop a file here and it is processed and then REMOVED.
        "${bookIngestDir}:/cwa-book-ingest"
        # The Calibre library itself: metadata.db plus the book tree.
        "${booksDir}:/calibre-library"
      ];

      # Bound to all interfaces on purpose, like Jellyfin and Seerr: you open
      # this from the laptop over Tailscale to push a book to the Kindle. The
      # firewall is what keeps the LAN out.
      ports = [ "${toString ports.cwa}:8083" ];
    };

    # ---- the book downloader ---------------------------------------------
    # Companion to CWA, by a different author, and the piece that turns
    # "drop a file in ingest" into "search and click". It writes into the
    # SAME ingest folder CWA watches, so the handoff needs no wiring: you
    # click here, the file lands in ${bookIngestDir}, CWA picks it up,
    # fetches metadata, converts, files it, and Send-to-Kindle is one more
    # click. Upstream calls it Shelfmark now.
    #
    # It searches shadow libraries — Anna's Archive and Library Genesis.
    # That is what it is for and it is worth knowing rather than finding out.
    virtualisation.oci-containers.containers.book-downloader = {
      # Digest-pinned for the same reason as the other two.
      image = "ghcr.io/calibrain/calibre-web-automated-book-downloader@sha256:9602290324993c801b319d3166b202b96bd9039af2416f0916dae03a5bdca815";

      environmentFiles = [ "/run/cwa.env" ];
      environment = {
        # The default is already this path, but being explicit means a
        # future image that changes the default cannot silently start
        # writing somewhere CWA is not watching.
        INGEST_DIR = "/cwa-book-ingest";
        FLASK_PORT = toString ports.bookDownloader;
      };

      volumes = [
        "${bookIngestDir}:/cwa-book-ingest"
        # CWA's database, READ-ONLY, so the downloader can grey out books
        # the library already has instead of fetching them twice.
        "/var/lib/cwa/config/app.db:/auth/app.db:ro"
      ];

      ports = [ "${toString ports.bookDownloader}:8084" ];
    };

    virtualisation.oci-containers.containers.threadfin = {
      # Same digest-pinning reasoning as above.
      image = "docker.io/fyb3roptik/threadfin@sha256:863fb0c2945617b4aa48b79eaa655954df72d68fbee6e49a1465934ceb3f057e";

      volumes = [
        "/var/lib/threadfin/conf:/home/threadfin/conf"
        "/var/lib/threadfin/tmp:/tmp/threadfin"
      ];

      # Loopback only. Jellyfin reaches it over localhost, and the admin UI
      # is a rarely-touched config screen like Prowlarr's — reach it with
      #   ssh -L 34400:localhost:34400 kino
      ports = [ "${toString ports.threadfin}:34400" ];
    };

    # ---- Homepage --------------------------------------------------------
    # The status page: one place that shows whether all five services are up
    # and how much disk is left, with links to each. It does not DO anything —
    # Seerr is where you add films, Jellyfin is where you watch them — but it
    # is the answer to "which of these is broken this time".
    #
    # Deliberately configured WITHOUT API keys. Homepage can show live widgets
    # (what is downloading right now, how many films Radarr has) but that needs
    # each service's API key, which is generated on first start and would have
    # to go through sops to avoid landing in the world-readable Nix store.
    # docs/MEDIA.md has that recipe if you want it later. `siteMonitor` below
    # needs no key at all: it just makes an HTTP request and colours the tile.
    services.homepage-dashboard = {
      enable = true;
      listenPort = ports.homepage;
      openFirewall = false;

      # Homepage refuses requests whose Host header is not on this list, which
      # is exactly what you hit when opening it from the phone over Tailscale
      # and getting a blank page instead of an error.
      allowedHosts = lib.concatStringsSep "," [
        "localhost:${toString ports.homepage}"
        "127.0.0.1:${toString ports.homepage}"
        "${config.networking.hostName}:${toString ports.homepage}"
      ];

      settings = {
        title = "media";
        theme = "dark";
        color = "stone"; # closest thing Homepage has to Gruvbox's warm grey
        headerStyle = "clean";
        hideVersion = true;
      };

      # ---- href vs siteMonitor, and why they differ -------------------
      # siteMonitor is fetched BY HOMEPAGE, which runs here — so it always
      # says localhost. href is followed by YOUR BROWSER, which is on the
      # laptop, so localhost there means the laptop and the link goes
      # nowhere. This machine is headless; there is no browser on it for a
      # localhost link to be correct in.
      #
      # So the two groups differ on purpose:
      #
      # Everything here is administered over Tailscale, so every tile but
      # one names the host. The firewall trusts tailscale0 and nothing else,
      # and each of these services has its own login.
      #
      # qBittorrent is the exception and stays on 127.0.0.1. It runs with
      # LocalHostAuth = false, so a loopback connection needs NO password —
      # that is safe only while loopback is the only way in. Binding it to
      # the tailnet without first giving it a password would hand every
      # device on the tailnet unauthenticated control of a process that
      # writes files wherever it can reach, and qBittorrent can be told to
      # run a program on download completion. Reach it with
      #   ssh -L 8080:localhost:8080 kino
      # You will rarely want to: once Radarr drives it, its UI is for
      # watching a transfer that is misbehaving and nothing else.
      #
      # Icon names come from the dashboard-icons project and are fetched from
      # a CDN at page load. Offline you get placeholders, nothing breaks.
      services = [
        {
          "Oglądanie" = [
            {
              "Jellyfin" = {
                href = "http://${config.networking.hostName}:${toString ports.jellyfin}";
                siteMonitor = "http://localhost:${toString ports.jellyfin}";
                description = "Biblioteka i odtwarzanie";
                icon = "jellyfin.png";
              };
            }
            {
              "Seerr" = {
                href = "http://${config.networking.hostName}:${toString ports.seerr}";
                siteMonitor = "http://localhost:${toString ports.seerr}";
                description = "Tu dodajesz film";
                icon = "jellyseerr.png";
              };
            }
          ];
        }
        {
          "Słuchanie i czytanie" = [
            {
              "Navidrome" = {
                href = "http://${config.networking.hostName}:${toString ports.navidrome}";
                siteMonitor = "http://localhost:${toString ports.navidrome}";
                description = "Muzyka — serwer Subsonic dla telefonu";
                icon = "navidrome.png";
              };
            }
            {
              "Book Downloader" = {
                href = "http://${config.networking.hostName}:${toString ports.bookDownloader}";
                siteMonitor = "http://localhost:${toString ports.bookDownloader}";
                description = "Szukanie e-booków → ingest";
                icon = "calibre-web.png";
              };
            }
            {
              "slskd" = {
                href = "http://${config.networking.hostName}:${toString ports.slskd}";
                siteMonitor = "http://localhost:${toString ports.slskd}";
                description = "Soulseek — muzyka niszowa i polska";
                icon = "soulseek.png";
              };
            }
            {
              "Calibre-Web" = {
                href = "http://${config.networking.hostName}:${toString ports.cwa}";
                siteMonitor = "http://localhost:${toString ports.cwa}";
                description = "E-booki i wysyłka na Kindle";
                icon = "calibre-web.png";
              };
            }
          ];
        }
        {
          "Kuchnia" = [
            {
              "Radarr" = {
                href = "http://${config.networking.hostName}:${toString ports.radarr}";
                siteMonitor = "http://localhost:${toString ports.radarr}";
                description = "Kolejka i import";
                icon = "radarr.png";
              };
            }
            {
              "Sonarr" = {
                href = "http://${config.networking.hostName}:${toString ports.sonarr}";
                siteMonitor = "http://localhost:${toString ports.sonarr}";
                description = "Seriale: kolejka i import";
                icon = "sonarr.png";
              };
            }
            {
              "Lidarr" = {
                href = "http://${config.networking.hostName}:${toString ports.lidarr}";
                siteMonitor = "http://localhost:${toString ports.lidarr}";
                description = "Muzyka: kolejka i import";
                icon = "lidarr.png";
              };
            }
            {
              "Bazarr" = {
                href = "http://${config.networking.hostName}:${toString ports.bazarr}";
                siteMonitor = "http://localhost:${toString ports.bazarr}";
                description = "Napisy: polskie i angielskie";
                icon = "bazarr.png";
              };
            }
            {
              "Threadfin" = {
                href = "http://${config.networking.hostName}:${toString ports.threadfin}";
                siteMonitor = "http://localhost:${toString ports.threadfin}";
                description = "Proxy M3U/EPG dla Jellyfin Live TV";
                icon = "threadfin.png";
              };
            }
            {
              "Prowlarr" = {
                href = "http://${config.networking.hostName}:${toString ports.prowlarr}";
                siteMonitor = "http://localhost:${toString ports.prowlarr}";
                description = "Trackery";
                icon = "prowlarr.png";
              };
            }
            {
              "qBittorrent" = {
                href = "http://localhost:${toString ports.qbittorrent}";
                siteMonitor = "http://localhost:${toString ports.qbittorrent}";
                description = "Transfery — ssh -L (bez hasła, patrz komentarz)";
                icon = "qbittorrent.png";
              };
            }
            {
              "FlareSolverr" = {
                siteMonitor = "http://localhost:${toString ports.flaresolverr}";
                description = "Obejście Cloudflare — nic tu nie klikasz";
                icon = "flaresolverr.png";
              };
            }
          ];
        }
      ];

      # `disk` has to be a MOUNT POINT, not an arbitrary directory: the widget
      # resolves it through statfs and returns "Resource not available." (a
      # bare "API Error" tile in the UI) for anything else. ${mediaRoot} is a
      # plain directory on the root subvolume, so "/" is both the correct and
      # the accurate answer here — everything the stack writes lives on this
      # one filesystem by design, so its free space IS the media free space.
      # Per-directory usage is `dust ${mediaRoot}`, not a dashboard tile.
      widgets = [
        {
          resources = {
            cpu = true;
            memory = true;
            disk = "/";
          };
        }
      ];
    };

    # ---- one handle for the whole stack ----------------------------------
    # media.target exists so the nine services can be started and stopped as
    # a unit. Two dependency directions are doing the work:
    #
    #   wantedBy = [ "media.target" ]  (mkForce, replacing multi-user.target)
    #       nothing pulls these services in at boot except the target, so
    #       unhooking the target from boot is enough to keep them all down.
    #
    #   partOf = [ "media.target" ]
    #       stopping the target stops them too. Wants alone would not do
    #       this — it is a start-time dependency only.
    #
    # Whether the target itself is reached at boot is the autostart switch.
    # Deliberately NOT a ConditionPathExists on a flag file, which is the
    # obvious-looking runtime alternative: systemd resolves a unit's
    # dependencies when it enqueues the job and evaluates conditions only when
    # the job runs, so a skipped target still drags in everything it Wants.
    # The condition would gate the target and start the services anyway.
    systemd.targets.media = {
      description = "Media stack: Jellyfin, Seerr, Radarr, Sonarr, Bazarr, Prowlarr, qBittorrent";
      wantedBy = lib.optionals cfg.autostart [ "multi-user.target" ];
    };

    # Every unit above joins media.target instead of multi-user.target; see
    # the comment there for why both directions are needed. Written out as
    # attribute paths rather than a genAttrs block because `systemd.services =
    # {...}` would collide with the `systemd.services.radarr.serviceConfig`
    # definitions above. Nix happily merges a literal attrset with leaf paths
    # underneath it, but genAttrs returns a *computed* value, and a computed
    # value cannot be merged with anything — it fails with "attribute already
    # defined". Hence one explicit line per unit.
    systemd.services.jellyfin = { wantedBy = lib.mkForce [ "media.target" ]; partOf = [ "media.target" ]; };
    systemd.services.seerr = { wantedBy = lib.mkForce [ "media.target" ]; partOf = [ "media.target" ]; };
    systemd.services.radarr = { wantedBy = lib.mkForce [ "media.target" ]; partOf = [ "media.target" ]; };
    systemd.services.sonarr = { wantedBy = lib.mkForce [ "media.target" ]; partOf = [ "media.target" ]; };
    systemd.services.bazarr = { wantedBy = lib.mkForce [ "media.target" ]; partOf = [ "media.target" ]; };
    systemd.services.prowlarr = { wantedBy = lib.mkForce [ "media.target" ]; partOf = [ "media.target" ]; };
    systemd.services.qbittorrent = { wantedBy = lib.mkForce [ "media.target" ]; partOf = [ "media.target" ]; };
    systemd.services.flaresolverr = { wantedBy = lib.mkForce [ "media.target" ]; partOf = [ "media.target" ]; };
    systemd.services.homepage-dashboard = { wantedBy = lib.mkForce [ "media.target" ]; partOf = [ "media.target" ]; };
    systemd.services.lidarr = { wantedBy = lib.mkForce [ "media.target" ]; partOf = [ "media.target" ]; };
    systemd.services.navidrome = { wantedBy = lib.mkForce [ "media.target" ]; partOf = [ "media.target" ]; };

    # The oci-containers module names its units podman-<container>. They join
    # the target like everything else, so `media-down` still stops the whole
    # stack in one command — a container left running after media-down would
    # keep a lock on the library and be exactly the kind of surprise this
    # target exists to prevent.
    systemd.services.podman-cwa = { wantedBy = lib.mkForce [ "media.target" ]; partOf = [ "media.target" ]; };
    systemd.services.podman-threadfin = { wantedBy = lib.mkForce [ "media.target" ]; partOf = [ "media.target" ]; };
    systemd.services.podman-book-downloader = { wantedBy = lib.mkForce [ "media.target" ]; partOf = [ "media.target" ]; };
    systemd.services.slskd = { wantedBy = lib.mkForce [ "media.target" ]; partOf = [ "media.target" ]; };

    # ---- firewall --------------------------------------------------------
    # Only the BitTorrent peer port. Everything else is either loopback-bound
    # or reachable through the already-trusted tailscale0 interface.
    #
    # Incoming connections still need the router to forward 51413 to this
    # machine; without that you are connectable only to peers who can accept
    # your outgoing connections, which works but slows swarms down. Setting a
    # fixed port here rather than a random one is what makes that forwarding
    # rule possible at all.
    networking.firewall = {
      # Soulseek's listen port joins the BitTorrent one as the only things
      # open to the world. Both need the router forwarding to be useful;
      # without it you can still connect outwards, you are just harder for
      # other peers to reach, which on Soulseek shows up as queues that
      # never start.
      allowedTCPPorts = [ ports.torrenting ports.slskdListen ];
      allowedUDPPorts = [ ports.torrenting ]; # DHT and µTP
    };

    # ---- optional extras -------------------------------------------------
    # Bazarr fetches subtitles (including Polish ones) for whatever Radarr and
    # Sonarr have imported. Follows the same pattern as the services above;
    # uncomment and rerun the docs/MEDIA.md wiring for the new service.
    #
    # services.bazarr = {
    #   enable = true;
    #   group = "media";
    #   listenPort = 6767;
    # };
  };
}
