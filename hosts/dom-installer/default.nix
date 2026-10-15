{ lib, pkgs, modulesPath, ... }:

# The USB stick for dom. Booted on the old PC with a network cable in, it
# joins the tailnet as `dom-installer` and lets jerzy in over SSH; nothing
# has to be typed at the machine. The install itself then runs from the
# laptop (docs/DOM-INSTALL.md).
#
# The Tailscale auth key comes from the environment at build time
# (DOM_TS_AUTHKEY, with --impure) and ends up only in this ISO and the local
# store. Make it single-use and short-lived, and revoke it after the install.

let
  authKey = builtins.getEnv "DOM_TS_AUTHKEY";
in
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  networking.hostName = "dom-installer";
  image.baseName = lib.mkForce "dom-installer";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  services.tailscale = {
    enable = true;
    authKeyFile = pkgs.writeText "dom-tailscale-authkey" authKey;
    extraUpFlags = [ "--hostname=dom-installer" ];
  };

  warnings = lib.optional (authKey == "") ''
    dom-installer: DOM_TS_AUTHKEY is empty (forgot --impure?); this ISO will
    not join the tailnet and is useless for a remote install.
  '';

  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEOerpFHIIRu7bzw5wFZENu0QY9tCecVj5MdCvxTUUq7 jerzy-pg@ivan"
  ];

  # What the person at the screen sees. Written in Polish for them: first
  # that it is still working, then a clear "done" once the tailnet is up.
  services.getty.helpLine = lib.mkForce ''

    Instalator domowego kina. Nic tu nie wpisuj.
    Gdy pojawi się napis GOTOWE, zadzwoń do Jurka.
  '';

  systemd.services.dom-ready = {
    description = "Tell the person at the screen that the PC is reachable";
    wantedBy = [ "multi-user.target" ];
    after = [ "tailscaled.service" "getty@tty1.service" ];
    path = [ pkgs.tailscale pkgs.coreutils ];
    serviceConfig = {
      Type = "simple";
      StandardOutput = "tty";
      TTYPath = "/dev/tty1";
    };
    script = ''
      until ip=$(tailscale ip -4 2>/dev/null) && [ -n "$ip" ]; do sleep 5; done
      printf '\n\n'
      printf '   ###########################################\n'
      printf '   #                                         #\n'
      printf '   #   GOTOWE - komputer jest połączony.     #\n'
      printf '   #   Zadzwoń do Jurka. Nie wyłączaj go.    #\n'
      printf '   #                                         #\n'
      printf '   ###########################################\n'
      printf '\n   (adres: %s)\n\n' "$ip"
    '';
  };
}
