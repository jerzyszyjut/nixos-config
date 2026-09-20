{ config, lib, pkgs, ... }:

# The media server: a Lenovo Legion 5 15ITH6H (82JH) that sits somewhere with
# its lid shut and stays on. Everything here is about that last sentence — a
# machine whose defaults all assume someone is sitting in front of it, told to
# stop assuming that.
#
# i5-11400H (Tiger Lake-H, 6c/12t), 16 GB, Intel UHD iGPU + RTX 3060 Mobile,
# and two NVMe disks. See docs/SERVER-INSTALL.md.

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
  # TWO DISKS, and which is which matters:
  #
  #   nvme1n1  477 GB Samsung  ESP at /boot + @ @home @nix
  #   nvme0n1  931 GB WD Blue  @media -> /var/lib/media
  #
  # The library gets its own disk, so a film being written never competes with
  # the system disk, and rebuilding NixOS never touches the disk holding the
  # only copy of anything.
  #
  # compress=zstd is deliberately absent on the library: films are already
  # compressed, and btrfs would spend CPU rediscovering that on every write —
  # CPU this box would rather spend transcoding. noatime matters more there
  # than anywhere else, because a Jellyfin library scan reads every file and
  # would otherwise write a metadata update for each one.
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

  # ---- power, heat and fan noise -----------------------------------------
  # This block used to pin everything to `performance`, on the theory that
  # transcoding a 4K stream is a bursty load a powersave governor ramps up
  # for too slowly. That theory turned out to be wrong ON THIS MACHINE, and
  # the evidence is in the QuickSync check: vainfo reports HEVC Main10
  # decode AND encode on the iGPU, so Jellyfin transcodes on fixed-function
  # video hardware and barely touches the CPU cores at all.
  #
  # What the CPU actually does here is *arr scans, a Navidrome library scan
  # once an hour and a monthly btrfs scrub. Not one of those is latency
  # critical, and none of them justify a machine that idles at 56 °C with
  # the fan audible in a quiet room.
  #
  # So: quiet by default, with headroom still available on demand.
  services.tlp = {
    enable = true;
    settings = {
      # THE FAN LEVER. platform_profile is the Legion firmware's own fan and
      # power curve, and it is the setting you actually hear — far more than
      # anything the governor does. It was on "performance", which keeps the
      # fan ready rather than keeps the chip cool; at load average 0.09 that
      # is noise bought for nothing.
      #
      # "balanced" rather than "low-power" deliberately: low-power caps the
      # package hard enough to make a library scan crawl, and the fan is
      # already near-silent at balanced with this thermal load. If it is
      # still too loud, low-power is the next step and costs nothing but
      # scan speed.
      PLATFORM_PROFILE_ON_AC = "balanced";

      # With intel_pstate, "powersave" is NOT a slow mode — it is the
      # governor that scales across the whole range, while "performance"
      # pins the floor to the top of it. This is the ordinary choice; the
      # previous value was the unusual one.
      CPU_SCALING_GOVERNOR_ON_AC = "powersave";

      # Bias the hardware's own P-state picker toward efficiency. Turbo is
      # deliberately LEFT ENABLED (no CPU_BOOST_ON_AC = 0) and the ceiling
      # stays at 100: when something does need the cores, it gets them, it
      # just does not sit there holding them.
      CPU_ENERGY_PERF_POLICY_ON_AC = "balance_power";
      CPU_MIN_PERF_ON_AC = 0;
      CPU_MAX_PERF_ON_AC = 100;

      # No START_CHARGE_THRESH_BAT0/STOP_… here: those are the ThinkPad
      # tp_smapi interface, and this machine does not have it — BAT0 exposes
      # no charge_control_* attributes at all. The Legion equivalent is
      # conservation mode, set below.
    };
  };
  services.power-profiles-daemon.enable = false;

  # The safety net, and the answer to "but will it cook itself". thermald
  # watches the package temperature and throttles before the firmware has
  # to, independently of everything above — so the worst case of a quieter
  # fan profile is a slower scan, not a damaged chip. The hardware's own
  # trip points sit at 100 °C on top of that and are not negotiable by any
  # of this.
  services.thermald.enable = true;

  # Deliberately NOT powertop.enable: it tunes for battery life by putting
  # devices into aggressive runtime power management, including the NIC and
  # the SATA/NVMe link. On a server that shows up as latency on the first
  # request after an idle period.

  # ---- the battery -------------------------------------------------------
  # A lithium cell held at 100% and kept warm swells, and on a laptop that is
  # mains-powered forever the battery is doing nothing else — so cap it.
  # `conservation_mode` is the ideapad_laptop driver's version of the
  # ThinkPad charge thresholds: write 1 and the firmware stops charging
  # around 60%, leaving the pack as a small UPS that rides out a brief cut.
  #
  # A oneshot rather than a udev rule because the attribute belongs to an
  # ACPI platform device that exists from boot; there is no hotplug event to
  # hang a rule on. Guarded on the path existing so a kernel that renames or
  # drops it degrades to a no-op instead of failing the boot.
  systemd.services.battery-conservation = {
    description = "Cap battery charge at ~60% (Lenovo conservation mode)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "battery-conservation" ''
        f=/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode
        if [ -w "$f" ]; then
          echo 1 > "$f"
          echo "conservation mode on"
        else
          echo "no conservation_mode attribute; battery will charge to 100%" >&2
        fi
      '';
    };
  };

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
    # The ThinkPad's ~/.ssh/default.pub. Leaving this list empty with
    # PasswordAuthentication off locks you out of your own server, so the
    # assertion below refuses to build rather than letting that happen.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEOerpFHIIRu7bzw5wFZENu0QY9tCecVj5MdCvxTUUq7 jerzy-pg@ivan"
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
    flake = "github:jerzyszyjut/nixos-config#kino";
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
  # Both filesystems, not just the root one: they are separate btrfs
  # filesystems on separate disks, and a scrub covers the filesystem it is
  # pointed at. The library is the half worth checking — it is the part with
  # no second copy anywhere.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" "/var/lib/media" ];
  };

  # Fail before the disk does. smartd mails nothing by default — check it
  # with `smartctl -a /dev/nvme0n1` when a tile on Homepage looks wrong.
  services.smartd.enable = true;

  system.stateVersion = "26.05";
}
