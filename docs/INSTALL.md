# Installing

Written for a ThinkPad E14 Gen 6 (Intel), machine type 21M7. Adapt the disk
device and hardware module for anything else.

Budget about two hours the first time, most of it waiting for downloads.

---

## 0. Before you wipe anything

The current machine holds state that exists nowhere else. Collect it first —
some of it is unrecoverable once the disk is gone.

```bash
# Your saved WiFi networks, including eduroam
sudo cp -r /etc/NetworkManager/system-connections ~/nm-backup
sudo chown -R $USER ~/nm-backup

# Git identity → goes in home/jerzy/default.nix
cat ~/.gitconfig

# Anything with credentials in it
tar czf ~/preserve.tar.gz \
  ~/.ssh ~/.kube ~/.config/gcloud ~/.s3cfg ~/certificates ~/.gitconfig

# Your existing shell/editor config, to move into dotfiles/
cp -r ~/.config/fish ~/.tmux.conf ~/.config/btop ~/.config/lazygit ~/preserve/

# A record of what was installed, as a safety net
apt-mark showmanual > ~/apt-final.txt

# Your SSH host blocks. These go into the encrypted secret rather than the
# repo, so keep a copy to paste in later — see docs/SECRETS.md.
cat ~/.ssh/config
```

Copy `~/preserve.tar.gz`, `~/nm-backup` and `~/apt-final.txt` **off the
machine** — another laptop, a USB stick, or a server you control.

Also decide two things now:

- **Which `.ovpn` do you actually need?** Save it. Rebuilding a university VPN
  profile from memory is miserable.
- **Full wipe or dual boot?** The Nix store is hungry — plan on 120 GB minimum
  for NixOS, and more if you keep many generations. A full wipe is much simpler
  and this guide assumes it.

---

## 1. Make the USB (from Windows)

**Download the ISO.** Get the *graphical GNOME* installer image from
<https://nixos.org/download/#nixos-iso>. The minimal ISO works too, but the
graphical one gives you a browser and a WiFi GUI, which matters if you need to
look something up mid-install or connect to a captive-portal network.

**Verify it.** In PowerShell, from your Downloads folder:

```powershell
Get-FileHash -Algorithm SHA256 .\nixos-gnome-*.iso
```

Compare against the `.sha256` file on the download page. Skipping this is how
people spend an afternoon debugging a corrupt image.

**Write it.** Use [Rufus](https://rufus.ie):

1. Device: your USB stick (**everything on it will be erased**)
2. Boot selection: the NixOS ISO
3. Rufus will ask ISO mode or DD mode — **choose DD mode**. ISO mode produces a
   stick that won't boot NixOS.
4. Partition scheme: GPT, Target system: UEFI
5. Start

Ventoy and balenaEtcher also work. Do not use unetbootin.

**If you're dual-booting Windows** (skip if you're wiping):

- **Suspend BitLocker first**, and save the recovery key somewhere off the
  machine. Changing the boot configuration with BitLocker active can lock you
  out of your own drive.
- Disable **Fast Startup** (Control Panel → Power Options → Choose what the
  power buttons do → Turn off fast startup). Otherwise Windows leaves the
  filesystem in a dirty state that Linux won't mount cleanly.
- Shrink the Windows partition from Disk Management, not from Linux.

---

## 2. BIOS

Reboot and press **F1** repeatedly to enter BIOS setup. (**F12** is the one-time
boot menu, useful once the USB is in.)

Set the following:

| Setting | Value | Why |
|---|---|---|
| Secure Boot | **Disabled** | NixOS doesn't ship signed boot chains by default. `lanzaboote` can re-enable it later; not worth it on install day. |
| UEFI/Legacy Boot | **UEFI Only** | The config uses systemd-boot, which is UEFI. |
| CSM Support | Disabled | Legacy compatibility, not needed. |
| Fast Boot | Disabled | Skips USB enumeration, so your stick may not appear. |
| Sleep State | Linux (if present) | Some ThinkPads default to a Windows-only S0ix mode. |
| Intel Virtualization Technology | **Enabled** | Under Security → Virtualization. Docker and QEMU need it, and leaving it off makes `kvm_intel` fail to load — which surfaces as a scary "Failed to start Load Kernel Modules" on boot. |
| Intel VT-d | Enabled | IOMMU. Same menu. |

Save and exit with **F10**. Insert the USB, reboot, press **F12**, choose the
USB device.

---

## 3. Network in the installer

Wired just works. For WiFi in the graphical installer, use the network applet.
In the minimal installer:

```bash
sudo systemctl start wpa_supplicant
wpa_cli
> add_network
> set_network 0 ssid "YourNetwork"
> set_network 0 psk "yourpassword"
> enable_network 0
> quit
```

Or more simply, `nmtui` if NetworkManager is running. Confirm with `ping
nixos.org`.

Note: eduroam in a live installer is painful. Use a phone hotspot for the
install and set up eduroam afterwards.

---

## 4. Partition

**This erases the disk.** Check the device name first — `nvme0n1` is correct on
this machine but confirm with `lsblk` before running anything.

```bash
sudo -i
lsblk    # confirm the target is nvme0n1 and nothing else is mounted
```

A 2 GB ESP and btrfs for everything else. The ESP is deliberately larger than
the usual 512 MB because each NixOS generation keeps a kernel and initrd there,
and running out is an annoying failure mode.

```bash
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 2GiB
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart root btrfs 2GiB 100%

mkfs.fat -F 32 -n BOOT /dev/nvme0n1p1
mkfs.btrfs -L nixos /dev/nvme0n1p2
```

Btrfs subvolumes. These give you cheap filesystem snapshots on top of the
rollback you already get from Nix generations — two independent safety nets.

```bash
mount /dev/nvme0n1p2 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@snapshots
umount /mnt

OPTS="compress=zstd:1,noatime,ssd,discard=async"
mount -o subvol=@,$OPTS      /dev/nvme0n1p2 /mnt
mkdir -p /mnt/{home,nix,.snapshots,boot}
mount -o subvol=@home,$OPTS  /dev/nvme0n1p2 /mnt/home
mount -o subvol=@nix,$OPTS   /dev/nvme0n1p2 /mnt/nix
mount -o subvol=@snapshots,$OPTS /dev/nvme0n1p2 /mnt/.snapshots
mount /dev/nvme0n1p1 /mnt/boot
```

**The ESP goes at `/boot`, not `/boot/efi`.** systemd-boot expects it there;
the `/boot/efi` layout is a GRUB convention and will fail to install.

No swap partition. `zramSwap` in `hosts/thinkpad/default.nix` gives you
compressed swap in RAM instead. The tradeoff is that **hibernate won't work** —
suspend does. If you want hibernate, add a swap partition at least as large as
your RAM and set `boot.resumeDevice`.

---

## 5. Install

```bash
nix-shell -p git
git clone https://github.com/YOURNAME/nixos /mnt/etc/nixos-config
cd /mnt/etc/nixos-config

# Generate the hardware config for THIS machine. Never write this by hand —
# it contains your real filesystem UUIDs and the kernel modules needed to boot.
# Run it with everything from step 4 still mounted: it reads your live mounts.
nixos-generate-config --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix hosts/thinkpad/

cat hosts/thinkpad/hardware-configuration.nix
```

**Do not pass `--no-filesystems`.** It omits the `fileSystems` block, and
`nixos-install` then fails with *"The 'fileSystems' option does not specify your
root file system"*.

You should see five `fileSystems` entries. Verify each btrfs one carries its
`subvol=` option:

```nix
fileSystems."/"           # subvol=@
fileSystems."/home"       # subvol=@home
fileSystems."/nix"        # subvol=@nix
fileSystems."/.snapshots" # subvol=@snapshots
fileSystems."/boot"       # fsType = "vfat", short UUID
```

If a subvolume is missing, it wasn't mounted when you ran the command. Remount
per step 4 and regenerate — don't patch this file by hand. It's the one place
where a mistake produces an unbootable system.

**Expect `compress=zstd:1` and `noatime` to be missing.** `nixos-generate-config`
only records options it considers structurally necessary, so `subvol=` survives
and the performance options don't. They're restored in
`hosts/thinkpad/default.nix`, which merges additional options into the generated
list — no need to touch this file. Same file also tightens the ESP mount from
the generated `fmask=0022` to `0077`.

Three things must be resolved before the build will succeed:

1. **A wallpaper** at `modules/nixos/wallpaper.jpg`, or comment out
   `stylix.image` in `modules/nixos/style.nix`.
2. **Your username and git identity** — the config assumes `jerzy`. If yours
   differs, change it in `modules/nixos/base.nix`, `flake.nix`,
   `modules/nixos/secrets.nix`, and `home/jerzy/default.nix`.
3. **Your SSH hosts.** `home/jerzy/ssh.nix` deliberately contains no private
   hostnames — they live in an encrypted secret. Until you set that up
   (`docs/SECRETS.md`), only `github.com` will resolve by alias.

Then:

```bash
# Verify the tree is complete and visible to Nix before building.
./scripts/check-tree.sh

# CRITICAL: flakes only see git-TRACKED files. Anything untracked is invisible
# to evaluation, even though it's plainly there on disk. Stage everything first.
git add -A
git status --short          # nothing should show as ??

nixos-install --flake .#thinkpad --root /mnt
```

The first build downloads a lot and takes a while. It will ask for a root
password at the end.

```bash
# Set your own user's password before rebooting, or you can't log in
nixos-enter --root /mnt -c 'passwd jerzy'

reboot   # remove the USB
```

---

## 6. First boot

You'll land at `tuigreet`. Log in; Hyprland starts.

Nothing is configured yet beyond what's in the repo, so:

```bash
# Move the config somewhere you own — the aliases assume ~/nixos-config
sudo mv /etc/nixos-config ~/nixos-config
sudo chown -R $USER:users ~/nixos-config
cd ~/nixos-config

# Restore your WiFi networks
sudo cp ~/nm-backup/* /etc/NetworkManager/system-connections/
sudo chmod 600 /etc/NetworkManager/system-connections/*
sudo systemctl restart NetworkManager

# Authenticate Tailscale
sudo tailscale up

# Restore your keys
tar xzf ~/preserve.tar.gz -C ~
chmod 700 ~/.ssh && chmod 600 ~/.ssh/*
```

**Verify the parts most likely to be broken**, in this order:

```bash
# 1. Does the Python/ML workflow actually work? This is the big one — if
#    nix-ld is doing its job, binary wheels import cleanly.
uv venv /tmp/t && cd /tmp/t && uv pip install numpy torch \
  && ./.venv/bin/python -c "import torch; print(torch.__version__)"

# 2. Is Neovim new enough for vim.pack?
nvim --version | head -1     # needs 0.12+

# 3. Do the language servers attach?
nvim ~/nixos-config/flake.nix   # then :checkhealth vim.lsp

# 4. Does screen sharing work? (portals + pipewire)
#    Open Slack or Discord and try to share a window.

# 5. Chinese input
#    Ctrl+Space should switch to fcitx5; run fcitx5-configtool to add layouts.
```

Then read [SECRETS.md](SECRETS.md) — until you've done that step, your SSH
hosts and eduroam won't exist, since both live in the encrypted secret. Then
[KEYBINDS.md](KEYBINDS.md) to learn the keyboard.

---

## Troubleshooting the install

**USB won't boot.** Fast Boot still enabled in BIOS, or Rufus wrote in ISO mode
instead of DD mode.

**"FAILED to start Load Kernel Modules" while booting the installer.** Almost
always cosmetic — the boot continues and you can install normally. The service
fails if *any* module in its list can't be loaded. Identify which:

```bash
systemctl status systemd-modules-load.service
journalctl -b -u systemd-modules-load --no-pager
```

If it names `kvm_intel`, virtualization is disabled in BIOS — see the BIOS table
above. Other common answers are modules already compiled into the kernel, or
modules for hardware this laptop doesn't have; both are safe to ignore.

If the boot actually *hangs* rather than continuing, press `e` on the entry in
the boot menu and append `nomodeset` to get a text-mode installer, then report
what the journal says.

**`nixos-install` fails with a hash mismatch.** Your flake.lock references
something that moved. `nix flake update` and retry.

**"error: file 'wallpaper.jpg' was not found".** Add the file or comment out
`stylix.image`. Mentioned twice because it catches everyone.

**Build fails on an unknown option.** Usually `programs.ssh.enableDefaultConfig`
(only in newer home-manager) or a renamed Stylix option. Delete the offending
line; the error message names the file and line.

**`error: path '«git+file:///...»/hosts/thinkpad' does not exist`** — but `ls`
shows the file is right there. This is the single most confusing flake
behaviour: **Nix evaluates the git tree, not your working directory**, and
untracked files are invisible to it. Note the `rev=` in the error path — it
resolved to a commit that doesn't contain those files.

```bash
git add -A
git status --short     # ?? means invisible to Nix
```

Staging is enough; no commit needed. The same trap applies to
`modules/nixos/wallpaper.jpg` later — copying it in isn't enough, you must
`git add` it.

**Unknown option `hardware.cpu.intel.npu.enable`.** The installer ISO is newer
than the nixpkgs this flake pins, so `nixos-generate-config` emitted an option
that doesn't exist yet in 26.05. Comment out that line in
`hosts/thinkpad/hardware-configuration.nix`; it only enables the Meteor Lake NPU
driver, which nothing here uses.

**Package not found.** A handful of names in this repo are unverified. Search
with `nix search nixpkgs <name>` and fix. Likely candidates: `wiremix`,
`hyprshot`, `tinymist`, `nvtopPackages.intel`, `bibata-cursors`.

**Boots to a black screen.** Pick the previous generation from the boot menu —
on a fresh install there isn't one, so boot the USB again, mount as in step 4,
and `nixos-enter` to fix the config.

**No sound.** `systemctl --user status pipewire wireplumber`. If they're dead,
`systemctl --user restart pipewire wireplumber`.
