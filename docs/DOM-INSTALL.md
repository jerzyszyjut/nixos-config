# Installing `dom` remotely

`dom` is an old desktop at the parents' in Poland. Nobody there installs
anything: they boot a USB stick, the stick joins the tailnet by itself, and
the install runs from the ThinkPad over SSH with
[nixos-anywhere](https://github.com/nix-community/nixos-anywhere). The
on-site side is a separate one-page guide (the Claude doc "Instalacja
domowego kina"), done while on the phone.

## 1. Two Tailscale auth keys

In the admin console (Settings → Keys → Generate auth key):

| Key | Reusable | Ephemeral | Goes into |
| --- | --- | --- | --- |
| installer | yes | ideally | the ISO |
| dom | yes | no | `/var/lib/tailscale/authkey` on the installed disk |

Both must be reusable: the live USB keeps no state, so every boot of the
stick (and any test boot in a VM) logs in afresh, and a single-use key dies
on the first one. As built on 2026-10-15 both use the same reusable,
non-ephemeral key, so `dom-installer` nodes stay in the tailnet after the
install: remove them in the admin console and revoke the key.

A leftover `dom-installer` makes the next one `dom-installer-1`, so connect
to the address printed under GOTOWE (`ssh root@100.x.y.z`), not the name.

## 2. Build the stick and send it

```sh
DOM_TS_AUTHKEY=tskey-auth-… nix build --impure \
  .#nixosConfigurations.dom-installer.config.system.build.isoImage
ls result/iso/   # dom-installer.iso, ~1 GB
```

Share the ISO privately (Google Drive link, not public: it holds the key).

## 3. When `dom-installer` shows up

```sh
ssh root@<address> lsblk -o NAME,SIZE,MODEL,TRAN
ssh root@<address> 'lspci | grep -iE "vga|ethernet"; [ -d /sys/firmware/efi ] && echo UEFI || echo BIOS'
```

Set `device` in `hosts/dom/disko.nix` to the disk to wipe.

## 4. Secrets

dom decrypts sops secrets with its own age key, made here and copied in
during the install (same as kino, see `.sops.yaml`). Everything that goes
onto the disk besides the system lives OUTSIDE the repo, in
`~/.local/share/dom-install/extra-files` (made 2026-10-15):

| File | What |
| --- | --- |
| `var/lib/sops-nix/key.txt` | dom's age key; its public half is `host_dom` in `.sops.yaml` |
| `var/lib/tailscale/authkey` | the one-off "dom" Tailscale key |
| `var/lib/mullvad/private.key` | dom's WireGuard key for Mullvad (from the site's config zip) |

To start over: `age-keygen -o …/key.txt`, replace `host_dom`, then
`sops updatekeys secrets/secrets.yaml`.

## 5. Install

```sh
git add -A   # flakes only see tracked files
nix run github:nix-community/nixos-anywhere -- \
  --flake .#dom \
  --generate-hardware-config nixos-generate-config hosts/dom/hardware-configuration.nix \
  --extra-files ~/.local/share/dom-install/extra-files \
  root@<address>
```

It wipes the disk, installs, writes the real `hardware-configuration.nix`
here and reboots. Commit, push (autoUpgrade builds from GitHub), then
`ssh dom` and `sudo rm /var/lib/tailscale/authkey`. Revoke both keys and tell
them the stick can come out.

## 6. After the install

- Mullvad is configured: device made on mullvad.net (2026-10-15), its key in
  extra-files, address and server in `flake.nix`.
- Wire the services together: `docs/MEDIA.md`.
- Jellyfin accounts for the parents; the TV app finds the server on the LAN.
- Hardware: an Intel iGPU gets `nixos-hardware.nixosModules.common-cpu-intel`
  for QuickSync (as on kino); otherwise Jellyfin transcodes in software.
