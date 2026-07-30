{ config, lib, pkgs, ... }:

{
  # =======================================================================
  # NO PRIVATE HOSTNAMES IN THIS FILE.
  #
  # This repo is public, so real addresses live in a sops-encrypted secret and
  # are pulled in with an `Include` at runtime. Only genuinely public hosts
  # (github.com) and the global defaults are declared here.
  #
  # The encrypted fragment is plain ssh_config text, decrypted to
  # /run/secrets/ssh/hosts on tmpfs — never written to disk unencrypted.
  # Populate it with `sops secrets/secrets.yaml`; docs/SECRETS.md has a
  # ready-to-paste template.
  # =======================================================================
  programs.ssh = {
    enable = true;

    # Recent home-manager injects an opinionated default Match block. If your
    # version doesn't have this option yet, delete the line.
    enableDefaultConfig = false;

    # Order matters: ssh uses the FIRST value it finds for any given option, so
    # includes come before the blocks below and win on conflicts.
    includes = [
      "/run/secrets/ssh/hosts" # sops — real hosts and addresses
      "config.d/*" # anything that writes its own config
    ];

    matchBlocks = {
      # ---- global defaults -------------------------------------------
      "*" = {
        # Connection multiplexing: the second and subsequent connections to a
        # host are instant, and scp/rsync reuse the existing tunnel. The single
        # biggest quality-of-life change if you SSH all day.
        controlMaster = "auto";
        controlPath = "~/.ssh/control-%r@%h:%p";
        controlPersist = "10m";

        serverAliveInterval = 30;
        serverAliveCountMax = 3;
        compression = true;
        addKeysToAgent = "yes";

        # accept-new records an unknown host key on first contact but still
        # warns loudly if a known key ever changes. `no` would disable MITM
        # detection entirely.
        extraOptions.StrictHostKeyChecking = "accept-new";
      };

      # ---- public hosts ----------------------------------------------
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/default";
      };
    };
  };

  # ControlPath needs its directory to exist, and config.d is where tools that
  # insist on writing their own ssh config should be pointed.
  home.file.".ssh/config.d/.keep".text = "";

  # Remote-work toolkit.
  home.packages = with pkgs; [
    mosh # survives suspend, IP changes, and train wifi
    rsync
    rclone
    sshfs
    autossh
    tmux # what's already installed on the remote boxes
  ];
}
