{ config, lib, pkgs, ... }:

{
  # =======================================================================
  # SECRETS — INACTIVE UNTIL YOU FOLLOW docs/SECRETS.md
  #
  # The sops block below is commented out on purpose. `defaultSopsFile` is a
  # Nix path literal, and a path literal must exist at EVALUATION time — so
  # referencing secrets/secrets.yaml before you've created it fails the entire
  # build, not just the secrets.
  #
  # That's fine, because secrets are inherently a step-two task: the machine
  # decrypts using a key derived from its SSH host key, which doesn't exist
  # until after the first boot.
  #
  # ORDER OF OPERATIONS
  #   1. install and boot                          (this file stays as-is)
  #   2. work through docs/SECRETS.md steps 1-3    (creates secrets.yaml)
  #   3. uncomment the block below
  #   4. uncomment the eduroam profile in net.nix
  #   5. nrs
  #
  # Nothing breaks in the meantime. ssh silently ignores a missing `Include`,
  # so home/jerzy/ssh.nix works fine with no encrypted hosts file.
  # =======================================================================

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    validateSopsFiles = false;

    # Derive the decryption key from the host's SSH key: nothing extra to
    # manage, no passphrase at boot.
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = true;
    };

    secrets = {
      # ---- ssh hosts -------------------------------------------------
      # Plain ssh_config text, Included by home/jerzy/ssh.nix. Keeps real
      # hostnames and aliases out of a public repo while still versioning
      # them. Decrypted to /run/secrets/ssh/hosts on tmpfs.
      "ssh/hosts" = {
        owner = config.users.users.jerzy.name;
        mode = "0400";
      };

      # ---- openvpn ------------------------------------------------------
      # Two lines, decrypted to /run/secrets/openvpn/uni_userpass: username
      # on line 1, password on line 2 — exactly what OpenVPN's
      # `auth-user-pass <file>` wants. Owned by root since the openvpn
      # systemd service runs as root. Referenced by net.nix.
      "openvpn/uni_userpass" = {
        mode = "0400";
      };
    };
  };

  # These are needed to DO the setup, so they're installed unconditionally.
  environment.systemPackages = with pkgs; [
    sops
    age
    ssh-to-age # turns an SSH host key into an age key
  ];

  # ---- reading tokens once secrets are live ------------------------------
  # sops decrypts into /run/secrets, which is tmpfs — never written to disk
  # unencrypted, gone on reboot. Read the file rather than exporting a
  # plaintext env var from a dotfile; an env var is visible in /proc to
  # anything running as you.
  #
  #   set -x HF_TOKEN (cat /run/secrets/tokens/huggingface)
  #
  # Better still, many tools accept a path directly — WANDB_API_KEY_FILE,
  # --token-file, and so on. Prefer those.
}
