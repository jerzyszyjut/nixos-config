{ config, lib, pkgs, inputs, ... }:

# The parents' home cinema: an old desktop in Poland, wired to their router,
# with kino's film and series stack (flake.nix turns off music and books).
#
# Nobody there administers it. It was installed over Tailscale with
# nixos-anywhere (docs/DOM-INSTALL.md), updates itself from GitHub, and SSH
# over the tailnet is the only way in. Where a choice has a reason already
# written down in hosts/kino, it is the same choice here.

{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "dom";

  # eth0 rather than enp3s0-or-whatever: the firewall opens Jellyfin to the
  # living room by interface name (mediaServer.lanInterfaces), and this name
  # is known before anyone has seen the hardware.
  networking.usePredictableInterfaceNames = false;

  # GRUB, not systemd-boot: it boots the disk whether the old firmware starts
  # it as UEFI or as legacy BIOS (disko.nix has a partition for each).
  # efiInstallAsRemovable writes the fallback EFI path, which older UEFI
  # firmware boots without being told about it.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    configurationLimit = 10;
  };

  zramSwap.enable = true;

  # Seerr and the dashboard on the home network too, so the parents can
  # request films from the browser (Jellyfin is opened there by
  # mediaServer.lanInterfaces). Their own LAN, unlike kino's dorm WiFi.
  networking.firewall.interfaces.eth0.allowedTCPPorts = [ 5055 8082 ];

  # The dashboard's tiles link to the LAN address, which the parents' phones
  # and TV can reach; the name "dom" only resolves over Tailscale. Assigned by
  # the router's DHCP, so it should be reserved there for 88:a4:c2:de:0b:fb.
  profiles.mediaServer.dashboardHost = "192.168.0.118";

  # The parents' line does ~830/70 Mbit/s (~285 through Mullvad, 2026-10-19),
  # far more than kino's three-at-a-time queue uses. Stalled torrents (old
  # Polish releases with one seeder) no longer hold a slot either.
  services.qbittorrent.serverConfig.BitTorrent.Session = {
    MaxActiveDownloads = lib.mkForce 12;
    MaxActiveTorrents = lib.mkForce 20;
    MaxConnections = lib.mkForce 600;
    IgnoreSlowTorrentsForQueueing = true;
  };

  # Rare old releases often have no seeder reachable without a forwarded
  # port; swap those for another release instead of waiting for ever.
  profiles.mediaServer.stalledCleanup.enable = true;

  # Machine-translated Polish where providers have nothing (yet).
  profiles.mediaServer.subtitleFallback.enable = true;

  # Films downloaded from Jellyfin to a phone keep their subtitles.
  profiles.mediaServer.embedSubtitles.enable = true;

  # ---- GPU: RTX 2060 Super (Turing) ---------------------------------------
  # The Ryzen 5 3600 has no iGPU, so Jellyfin transcodes on NVENC instead of
  # kino's QuickSync. The open kernel module supports Turing and up.
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    open = true;
    modesetting.enable = true;
    nvidiaSettings = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  services.jellyfin = {
    # The device stays /dev/dri/renderD128: with modesetting on, the NVIDIA
    # driver provides that render node too.
    hardwareAcceleration.type = lib.mkForce "nvenc";
    # Turing's NVDEC has no AV1; everything else media-server.nix turns on
    # it decodes.
    transcoding.hardwareDecodingCodecs.av1 = lib.mkForce false;
  };

  # ---- always on ---------------------------------------------------------
  # A desktop does not suspend on a lid, but systemd will idle-suspend a
  # machine nobody is logged into. Same block as kino.
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # ---- getting in --------------------------------------------------------
  # The first login to the tailnet happens with nobody at the keyboard: the
  # install drops a one-off auth key here (nixos-anywhere --extra-files), and
  # autoconnect uses it only while the machine is logged out. Delete the file
  # once `dom` shows up in the tailnet.
  services.tailscale.authKeyFile = "/var/lib/tailscale/authkey";


  # Key-only SSH, reachable over Tailscale only (tailscale0 is trusted in
  # net.nix, port 22 is not opened to the LAN).
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
    openFirewall = false;
  };

  users.users.jerzy.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEOerpFHIIRu7bzw5wFZENu0QY9tCecVj5MdCvxTUUq7 jerzy-pg@ivan"
  ];

  # jerzy has no password here, by design: a password hash would have to go
  # into this public repo, and nobody types at this machine anyway. With SSH
  # keys as the only way in, sudo without a password is the same door.
  security.sudo.wheelNeedsPassword = lib.mkForce false;

  # ---- unattended --------------------------------------------------------
  # As on kino: rebuild from the pushed flake every night, never reboot on
  # its own.
  system.autoUpgrade = {
    enable = true;
    flake = "github:jerzyszyjut/nixos-config#dom";
    dates = "04:30";
    randomizedDelaySec = "45min";
    allowReboot = false;
  };

  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
  services.smartd.enable = true;
  services.fstrim.enable = true;

  system.stateVersion = "26.05";
}
