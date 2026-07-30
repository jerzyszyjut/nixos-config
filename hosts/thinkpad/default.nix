{ config, lib, pkgs, ... }:

{
  imports = [
    # Generated per-machine, never written by hand — it holds the real
    # filesystem UUIDs and the kernel modules needed to boot.
    # Regenerate for a different machine:
    #   nixos-generate-config --root /mnt   (then copy it here)
    ./hardware-configuration.nix
  ];

  networking.hostName = "thinkpad";

  # ---- filesystem options ------------------------------------------------
  # nixos-generate-config records `subvol=` but drops performance options, so
  # they're restored here rather than by editing the generated file — which
  # stays regenerable this way.
  #
  # These MERGE with what hardware-configuration.nix already declares: the
  # option is a list, and NixOS concatenates list definitions. Adding new
  # options is therefore safe; overriding a conflicting one needs mkForce.
  #
  # `ssd` and `discard=async` are omitted deliberately — btrfs autodetects both
  # on NVMe with current kernels.
  fileSystems."/".options = [ "compress=zstd:1" "noatime" ];
  fileSystems."/home".options = [ "compress=zstd:1" "noatime" ];
  fileSystems."/nix".options = [ "compress=zstd:1" "noatime" ];
  fileSystems."/.snapshots".options = [ "compress=zstd:1" "noatime" ];

  # The generated config mounts the ESP world-readable (fmask=0022). Current
  # practice is 0077, which matters if you ever use initrd secrets. This is a
  # conflicting value rather than an addition, so mkForce replaces the list
  # instead of appending to it.
  fileSystems."/boot".options = lib.mkForce [ "fmask=0077" "dmask=0077" ];

  # systemd-boot rather than GRUB: simpler, and it expects the ESP at /boot.
  # Each generation keeps a kernel and initrd there, so the count is capped.
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # No swap partition (`swapDevices = [ ]` in the generated config), so zram
  # provides compressed swap in RAM instead. Consequence: no hibernate.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # ThinkPad fan control. Usually unnecessary on modern models — enable only if
  # you find the firmware curve too aggressive.
  # services.thinkfan.enable = true;

  # Battery care. Adjust or drop if you leave it plugged in permanently.
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

      CPU_MIN_PERF_ON_AC = 0;
      CPU_MAX_PERF_ON_AC = 100;
      CPU_MIN_PERF_ON_BAT = 0;
      CPU_MAX_PERF_ON_BAT = 20;

      START_CHARGE_THRESH_BAT0 = 40; # Starts charging when below 40%
      STOP_CHARGE_THRESH_BAT0 = 80;  # Stops charging when reaching 80
    };
  };
  # tlp and power-profiles-daemon fight each other. Only one.
  services.power-profiles-daemon.enable = false;
  powerManagement.powertop.enable = true;
  services.thermald.enable = true;

  system.stateVersion = "26.05";
}
