{ config, lib, pkgs, ... }:

# The media server: a laptop that sits somewhere with its lid shut and stays
# on. Everything here is about that last sentence — a machine whose defaults
# all assume someone is sitting in front of it, told to stop assuming that.
#
# Written before the hardware was in hand, so a few blocks are marked CHECK:
# they are correct for a ThinkPad and wrong or simply absent elsewhere. The
# build tells you — an option that does not exist is an evaluation error, not
# a silent no-op. See docs/SERVER-INSTALL.md.

{
  imports = [
    # Generated per-machine, never written by hand — it holds the real
    # filesystem UUIDs and the kernel modules needed to boot. It does not
    # exist until you run, ON THIS MACHINE:
    #   nixos-generate-config --root /mnt   (then copy it here)
    ./hardware-configuration.nix
  ];

  networking.hostName = "kino";

  # ---- filesystem options ------------------------------------------------
  # Same reasoning as hosts/thinkpad: nixos-generate-config records `subvol=`
  # and drops the performance options, so they are restored here rather than
  # by editing the generated file, which stays regenerable that way. These
  # MERGE with what the generated file declares, because the option is a list.
  #
  # @media is the one subvolume this machine has and the ThinkPad does not.
  # compress=zstd is deliberately NOT set on it: films are already compressed
  # and btrfs would spend CPU discovering that on every write, CPU this box
  # would rather spend transcoding.
  fileSystems."/".options = [ "compress=zstd:1" "noatime" ];
  fileSystems."/home".options = [ "compress=zstd:1" "noatime" ];
  fileSystems."/nix".options = [ "compress=zstd:1" "noatime" ];
  fileSystems."/var/lib/media".options = [ "noatime" ];

  fileSystems."/boot".options = lib.mkForce [ "fmask=0077" "dmask=0077" ];

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # ---- it must not fall asleep -------------------------------------------
  # THE most important block in this file. A laptop suspends when you close
  # the lid, and a suspended Jellyfin serves nothing. The symptom is
  # maddening to debug from another room because the machine looks fine when
  # you open it — the wake is what you are seeing.
  #
  # "ignore" rather than "lock": there is no session to lock, and logind
  # consults a different setting on external power and when docked, so all
  # three are set explicitly instead of relying on which one wins.
  #
  # These live under `settings.Login` because logind's NixOS module now writes
  # logind.conf directly; the old `services.logind.lidSwitch` spelling still
  # works through a rename but warns on every build.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  # The other half of the same problem: systemd will idle-suspend a machine
  # with no logged-in user regardless of the lid. Mask the targets outright —
  # this makes suspend not merely unconfigured but impossible, which is what
  # you want on a box whose whole job is being reachable.
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # ---- power -------------------------------------------------------------
  # Plugged in permanently, so the governor stays on performance: transcoding
  # a 4K stream is exactly the bursty load that a powersave governor ramps up
  # for too slowly, and the viewer sees it as a stall.
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_MIN_PERF_ON_AC = 0;
      CPU_MAX_PERF_ON_AC = 100;

      # CHECK: ThinkPad-only, via the tp_smapi/acpi_call interface. A battery
      # held at 100% and warm is a battery that swells within a year or two,
      # and this machine will never once run on it — so charge it to 60% and
      # leave it there as a UPS that survives a brief power cut.
      #
      # On a non-ThinkPad these two are accepted by TLP and silently do
      # nothing. Check with `sudo tlp-stat -b`; if the thresholds are not
      # supported, the honest alternative is to physically remove the battery
      # if the model allows it.
      START_CHARGE_THRESH_BAT0 = 55;
      STOP_CHARGE_THRESH_BAT0 = 60;
    };
  };
  services.power-profiles-daemon.enable = false;
  services.thermald.enable = true;

  # Deliberately NOT powertop.enable: it tunes for battery life by putting
  # devices into aggressive runtime power management, including the NIC and
  # the SATA/NVMe link. On a server that shows up as latency on the first
  # request after an idle period.

  # ---- getting back into it ----------------------------------------------
  # This box has no keyboard you will use. SSH is how you administer it, and
  # if this is wrong you are carrying a monitor to it.
  #
  # Password auth off, root login off: it is reachable over Tailscale from
  # anywhere you are logged in, which is a much wider door than the LAN.
  # Put your laptop's public key in the list below BEFORE installing —
  # docs/SERVER-INSTALL.md has the step.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
    # Only over Tailscale. The port is not opened in the firewall below, and
    # modules/nixos/net.nix marks tailscale0 trusted — so sshd listens, but
    # nothing on the café WiFi can reach it.
    openFirewall = false;
  };

  users.users.jerzy.openssh.authorizedKeys.keys = [
    # Paste the contents of ~/.ssh/id_ed25519.pub FROM THE THINKPAD here.
    # Leaving this list empty and PasswordAuthentication off locks you out of
    # your own server, so the assertion below refuses to build instead.
  ];

  assertions = [
    {
      assertion = config.users.users.jerzy.openssh.authorizedKeys.keys != [ ];
      message = ''
        hosts/kino: no SSH key for jerzy, and password auth is disabled — this
        configuration would be unreachable. Paste your laptop's
        ~/.ssh/id_ed25519.pub into openssh.authorizedKeys.keys first.
      '';
    }
  ];

  # ---- unattended --------------------------------------------------------
  # Nobody logs into this machine for weeks at a time, so security updates
  # have to arrive on their own. It rebuilds from the flake in git rather
  # than from a channel, so what it applies is what this repo says.
  #
  # `allowReboot = false` on purpose: a kernel update then stages a new
  # generation that takes effect at YOUR next reboot, rather than the machine
  # deciding to drop a stream at 04:40.
  system.autoUpgrade = {
    enable = true;
    flake = "github:jerzyszyjut/nixos-config#kino"; # CHECK: your repo URL
    # No --update-input: it rebuilds from whatever this repo's flake.lock
    # pins, so the server runs exactly what you last pushed and tested on the
    # laptop, rather than resolving nixpkgs to something nothing has run yet.
    # `nix flake update` on the ThinkPad, rebuild there, push — the server
    # picks it up that night.
    dates = "04:30";
    randomizedDelaySec = "45min";
    allowReboot = false;
  };

  # The flip side of auto-upgrading is that generations accumulate and /nix
  # fills up on a disk whose free space is meant for films. Nothing to do
  # here: modules/nixos/base.nix already runs a weekly gc at
  # --delete-older-than 14d and turns on nix.optimise.automatic, and both
  # apply to every host. Setting them again here is not additive — nix.gc.options
  # is a single string, so a second definition is a conflict, not an override.

  # ---- disk ---------------------------------------------------------------
  # btrfs scrub reads every block and verifies it against its checksum, which
  # is how you find out a film rotted BEFORE the night you sit down to watch
  # it. Monthly is the usual cadence; it is I/O-heavy, so it runs at night.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # Fail before the disk does. smartd mails nothing by default — check it
  # with `smartctl -a /dev/nvme0n1` when a tile on Homepage looks wrong.
  services.smartd.enable = true;

  system.stateVersion = "26.05";
}
