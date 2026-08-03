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
  # WETI (Gdańsk Tech faculty) VPN. ca cert + tls-auth key are static VPN
  # material (not personal credentials), so they're plain files in this repo
  # under files/openvpn/, copied into the world-readable Nix store like any
  # other package. The username/password ARE personal credentials — those go
  # through sops instead of authUserPass's attrset form, which the module
  # docs warn writes plaintext into the store. See docs/SECRETS.md to add the
  # openvpn/uni_userpass value, then flip autoStart if you want it always on.
  services.openvpn.servers.uni = {
    config = ''
      dev tap
      proto tcp-client
      persist-key
      persist-tun
      replay-persist cur-replay-protection.cache
      nobind
      remote 153.19.55.234 1194
      pull
      tls-client
      cipher AES-256-CBC
      ns-cert-type server
      tls-auth ${./files/openvpn/ta_delli50.key} 1
      ca ${./files/openvpn/CA_WETI_2020.crt}
      verb 3
      tls-cipher "DEFAULT:@SECLEVEL=0"
    '';
    authUserPass = config.sops.secrets."openvpn/uni_userpass".path;
    autoStart = false;
  };

  # The openvpn module already sets Restart = "always" on this unit, but the
  # systemd default RestartSec (100ms) fires the retry before the WETI server
  # has let go of the previous handshake attempt, so it fails again straight
  # away. This is the "start it, wait, start it again" workaround you do by
  # hand — a longer RestartSec gives the server the moment it needs, and the
  # raised start-limit keeps a couple of expected failures from landing the
  # unit in "failed" before the automatic retry gets there.
  systemd.services."openvpn-uni" = {
    serviceConfig.RestartSec = "10s";
    startLimitIntervalSec = 120;
    startLimitBurst = 6;
  };

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
