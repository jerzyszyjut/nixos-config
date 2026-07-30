{ config, lib, pkgs, ... }:

{
  # You have ~30 saved WiFi networks. Deliberately NOT declared: you don't
  # want to edit Nix and rebuild to join hotel WiFi. NetworkManager keeps its
  # own mutable state in /etc/NetworkManager/system-connections, same as now,
  # so you can copy your backup straight into that path.
  networking.networkmanager = {
    enable = true;
    wifi.backend = "iwd"; # noticeably better roaming than wpa_supplicant
  };
  networking.wireless.iwd.enable = true;

  # ---- Tailscale ---------------------------------------------------------
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  # ---- OpenVPN -----------------------------------------------------------
  # You have openvpn installed, presumably for university/work access. Point
  # this at your .ovpn once you know which one you need.
  # services.openvpn.servers.uni = {
  #   config = "config /etc/openvpn/uni.ovpn";
  #   autoStart = false;
  # };

  environment.systemPackages = with pkgs; [
    wireguard-tools
    openvpn
    openconnect # in case anything uses Cisco AnyConnect
    mtr
    dig
    ethtool
    iperf3
  ];

  # ---- eduroam -----------------------------------------------------------
  # Declared so a fresh install connects on campus without any clicking. The
  # $EDUROAM_* placeholders are substituted at activation from the sops
  # template in secrets.nix, so no credentials appear in this repo.
  #
  # Commented out until you've populated secrets/secrets.yaml — see
  # docs/SECRETS.md. Until then, join once with `nmtui` and NetworkManager
  # remembers it.
  #
  # networking.networkmanager.ensureProfiles = {
  #   environmentFiles = [ config.sops.templates."eduroam.env".path ];
  #   profiles.eduroam = {
  #     connection = {
  #       id = "eduroam";
  #       type = "wifi";
  #       autoconnect = true;
  #     };
  #     wifi = {
  #       ssid = "eduroam";
  #       mode = "infrastructure";
  #     };
  #     wifi-security.key-mgmt = "wpa-eap";
  #     "802-1x" = {
  #       eap = "peap;";
  #       identity = "$EDUROAM_IDENTITY";
  #       password = "$EDUROAM_PASSWORD";
  #       phase2-auth = "mschapv2";
  #       # Your institution publishes the expected CA and server name. Setting
  #       # these is what stops you handing your password to a rogue AP
  #       # broadcasting "eduroam" — worth looking up.
  #       # ca-cert = "/etc/ssl/certs/ca-bundle.crt";
  #       # domain-suffix-match = "radius.pg.edu.pl";
  #     };
  #     ipv4.method = "auto";
  #     ipv6.method = "auto";
  #   };
  # };

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  # NordVPN dropped per your call.
}
