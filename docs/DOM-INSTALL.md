# Installing `dom` remotely

`dom` is an old desktop at the parents' in Poland. Nobody there installs
anything: they boot a USB stick, the stick joins the tailnet by itself, and
the install runs from the ThinkPad over SSH with
[nixos-anywhere](https://github.com/nix-community/nixos-anywhere). Their
side of it is a separate one-page guide (the Claude doc "Instalacja domowego
kina – instrukcja dla Taty").

## 1. Two Tailscale auth keys

In the admin console (Settings → Keys → Generate auth key):

| Key | Reusable | Ephemeral | Expiry | Goes into |
| --- | --- | --- | --- | --- |
| installer | yes | yes | 30 days | the ISO |
| dom | no | no | 7 days | `/var/lib/tailscale/authkey` on the installed disk |

The installer key is reusable because the live USB keeps no state: every boot
of the stick logs in again. Ephemeral removes `dom-installer` from the
tailnet once it goes offline. Revoke both after the install.

## 2. Build the stick and send it

```sh
DOM_TS_AUTHKEY=tskey-auth-… nix build --impure \
  .#nixosConfigurations.dom-installer.config.system.build.isoImage
ls result/iso/   # dom-installer.iso, ~1 GB
```

Share the ISO privately (Google Drive link, not public: it holds the key).

## 3. When `dom-installer` shows up

```sh
ssh root@dom-installer lsblk -o NAME,SIZE,MODEL,TRAN
ssh root@dom-installer 'lspci | grep -iE "vga|ethernet"; [ -d /sys/firmware/efi ] && echo UEFI || echo BIOS'
```

Set `device` in `hosts/dom/disko.nix` to the disk to wipe.

## 4. Secrets

dom decrypts sops secrets with its own age key, made here and copied in
during the install (same as kino, see `.sops.yaml`):

```sh
x=$(mktemp -d)
install -d -m 755 $x/var/lib/sops-nix $x/var/lib/tailscale
age-keygen -o $x/var/lib/sops-nix/key.txt   # prints the public key
printf %s 'tskey-auth-…' > $x/var/lib/tailscale/authkey   # the "dom" key
chmod 600 $x/var/lib/sops-nix/key.txt $x/var/lib/tailscale/authkey
```

Add the public key to `.sops.yaml` as `host_dom`, then
`sops updatekeys secrets/secrets.yaml`.

## 5. Install

```sh
git add -A   # flakes only see tracked files
nix run github:nix-community/nixos-anywhere -- \
  --flake .#dom \
  --generate-hardware-config nixos-generate-config hosts/dom/hardware-configuration.nix \
  --extra-files $x \
  root@dom-installer
```

It wipes the disk, installs, writes the real `hardware-configuration.nix`
here and reboots. Commit, push (autoUpgrade builds from GitHub), then
`ssh dom` and `sudo rm /var/lib/tailscale/authkey`. Revoke both keys and tell
them the stick can come out.

## 6. After the install

- Mullvad: a new device for dom in the Mullvad account, its private key at
  `/var/lib/mullvad/private.key` (mode 600), address / public key / endpoint
  in `flake.nix`, then `mediaServer.autostart = true`. Until then the stack
  stays off, so nothing downloads from the parents' own IP.
- Wire the services together: `docs/MEDIA.md`.
- Jellyfin accounts for the parents; the TV app finds the server on the LAN.
- Hardware: an Intel iGPU gets `nixos-hardware.nixosModules.common-cpu-intel`
  for QuickSync (as on kino); otherwise Jellyfin transcodes in software.
