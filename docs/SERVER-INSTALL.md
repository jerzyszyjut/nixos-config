# Building the media server

Turning a spare laptop into `kino` — the always-on box that runs Jellyfin,
Radarr, Sonarr, Prowlarr, qBittorrent and Seerr — and taking that stack off
the ThinkPad.

This is the from-scratch version: writing the USB stick, BIOS, partitioning,
the first install, and then the part nobody writes down, which is moving an
existing library across without re-downloading it.

Budget an evening. Most of it is waiting, and the library copy can run
overnight.

> [INSTALL.md](INSTALL.md) is the same procedure for the ThinkPad and goes
> into more detail on a few shared steps. Where this guide says "as in
> INSTALL.md", that is where to look.

---

## What changes, and where

The repo already did most of this. `profiles.entertainment` used to mean both
the services and the players; it is now split:

| | what it is | where it goes |
|---|---|---|
| `profiles.mediaServer` | Jellyfin, Seerr, Radarr, Sonarr, Bazarr, Prowlarr, qBittorrent, FlareSolverr, Homepage | `kino` |
| `profiles.entertainment` | jellyfin-media-player, mpv, vlc, Spotify, Discord | the ThinkPad (and anything else with a screen) |

So the ThinkPad keeps Spotify, Discord and the players. What it loses is nine
systemd services, the `media` group, the BitTorrent port in the firewall, and
about 300 MB of packages it was building for no reason.

The `jf`, `seerr` and `media` abbreviations still work on the laptop — they
now open `http://kino:…` instead of `http://localhost:…`, which is what
`entertainment.serverHost = "kino"` in `flake.nix` sets.

---

## 0. Before you touch the new laptop

**Do not wipe the ThinkPad's `/var/lib/media` yet.** Nothing in this guide
deletes it, and it stays exactly where it is until step 8 — after the new
server is up and you have checked the films actually play from it. Disabling
the profile stops the services; it does not remove their data. That is the
safety net for this whole operation, so leave it intact.

Two things to decide now:

- **How big is the library?** `du -sh /var/lib/media` on the ThinkPad. This
  sets the disk you need in the new machine, and how you move it in step 7 —
  under ~200 GB an overnight copy over the network is fine, above that a USB
  disk is faster than any WiFi.
- **Where will the machine live?** It needs mains power and, ideally, ethernet.
  A laptop serving 4K over WiFi from behind a wardrobe is the most common
  cause of "Jellyfin keeps buffering" that is not Jellyfin's fault.

Collect the new laptop's details — you need them in step 4 and step 6:

```bash
# On the new laptop, booted into whatever is on it now, or from the installer:
lsblk                      # the disk you are about to erase
lscpu | grep -i 'model name'
```

---

## 1. Make the USB

Identical to [INSTALL.md §1](INSTALL.md), so the short version:

Download the **minimal** ISO from <https://nixos.org/download/#nixos-iso>.
INSTALL.md suggests the graphical one; for a server the minimal image is the
better pick — it boots straight to a root shell, which is all you need here,
and it is a third of the size.

Verify the hash against the `.sha256` on the download page, then write it:

```bash
# from the ThinkPad — no Rufus needed, this is what dd is for
lsblk                                  # find the stick, e.g. sdb. CHECK THIS.
sudo dd if=~/Downloads/nixos-minimal-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

`of=` is the whole disk (`/dev/sdb`), not a partition (`/dev/sdb1`). Getting
this wrong writes over the wrong disk, so run `lsblk` immediately before, and
read the output rather than remembering it from last time.

---

## 2. BIOS

The table in [INSTALL.md §2](INSTALL.md) applies — Secure Boot off, UEFI only,
CSM and Fast Boot off, virtualization on. **Three extra settings matter on a
machine that is supposed to stay up**, and they are the ones people forget:

| Setting | Value | Why |
|---|---|---|
| **AC power recovery** / "After Power Loss" / "Restore on AC/Power Loss" | **Power On** | Otherwise the machine stays off after a power cut until you walk to it and press the button. This is the single most valuable BIOS setting on a server. |
| **Wake on LAN** | Enabled | Gives you a way back in if it does shut down. Not a substitute for the above. |
| **Boot order** | Internal disk first | So a forgotten USB stick does not leave it sitting at an installer prompt. |

The key names vary by vendor; look under Power, or Advanced → Power
Management. Not every laptop BIOS exposes them — if yours does not, nothing
here breaks, you just lose the automatic recovery.

---

## 3. Network in the installer

Ethernet works with no setup. If it has to be WiFi:

```bash
systemctl start wpa_supplicant
wpa_cli
> add_network
> set_network 0 ssid "YourNetwork"
> set_network 0 psk "yourpassword"
> enable_network 0
> quit

ping -c3 nixos.org
```

---

## 4. Partition

**This erases the disk.** Confirm the device name — it is `nvme0n1` on most
recent machines and `sda` on anything with a SATA SSD.

```bash
sudo -i
lsblk     # confirm the target, and that nothing else is mounted
```

Same shape as the ThinkPad — 2 GB ESP, btrfs for the rest — plus **one extra
subvolume for the library**:

```bash
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 2GiB
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart root btrfs 2GiB 100%

mkfs.fat -F 32 -n BOOT /dev/nvme0n1p1
mkfs.btrfs -L nixos /dev/nvme0n1p2

mount /dev/nvme0n1p2 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@media      # <- the library lives here
umount /mnt
```

### Why `@media` is its own subvolume, and why it must be one

`modules/profiles/media-server.nix` puts downloads and the finished library
under the same root on purpose: Radarr imports a finished download by
**hardlinking** it, so the file appears in the library and in qBittorrent's
download directory while taking the space once.

Hardlinks cannot cross a filesystem boundary, **and btrfs counts every
subvolume as its own boundary.** So the rule is: downloads and library
together on one subvolume. `/var/lib/media` is that subvolume, holding both
`torrents/` and `library/` inside it. Split them and Radarr silently falls
back to copying — no error, every film just quietly costs twice the disk.

Mount it, with different options from the rest:

```bash
OPTS="compress=zstd:1,noatime"
mount -o subvol=@,$OPTS     /dev/nvme0n1p2 /mnt
mkdir -p /mnt/{home,nix,boot,var/lib/media}
mount -o subvol=@home,$OPTS /dev/nvme0n1p2 /mnt/home
mount -o subvol=@nix,$OPTS  /dev/nvme0n1p2 /mnt/nix

# No compression on the library: films are already compressed, so zstd burns
# CPU rediscovering that on every write — CPU this machine would rather spend
# transcoding. noatime matters more here than anywhere: without it, Jellyfin
# scanning the library writes a metadata update for every file it reads.
mount -o subvol=@media,noatime /dev/nvme0n1p2 /mnt/var/lib/media

mount /dev/nvme0n1p1 /mnt/boot
```

The ESP goes at `/boot`, not `/boot/efi` — systemd-boot expects it there.

If the machine has **two disks** (a small SSD and a big HDD, say), put `@` and
`@nix` on the SSD and make the whole HDD one btrfs filesystem mounted at
`/var/lib/media`. The hardlink rule is unchanged: everything under
`/var/lib/media` must be one filesystem.

---

## 5. Get the repo onto it

```bash
nix-shell -p git
git clone https://github.com/jerzyszyjut/nixos-config /mnt/etc/nixos-config
cd /mnt/etc/nixos-config

# Generate the hardware config FOR THIS MACHINE. Never write it by hand.
# Run it with everything from step 4 still mounted — it reads your live mounts.
nixos-generate-config --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix hosts/kino/
```

Do **not** pass `--no-filesystems`. Check the result names five filesystems,
each btrfs one carrying its `subvol=`:

```bash
grep -A3 'fileSystems' hosts/kino/hardware-configuration.nix
```

```nix
fileSystems."/"               # subvol=@
fileSystems."/home"           # subvol=@home
fileSystems."/nix"            # subvol=@nix
fileSystems."/var/lib/media"  # subvol=@media   <- the one that is easy to miss
fileSystems."/boot"           # fsType = "vfat"
```

If `/var/lib/media` is absent it was not mounted when you ran the command.
Remount per step 4 and regenerate; do not patch this file by hand.

`compress=zstd:1` and `noatime` will be missing from the generated file — that
is expected. `nixos-generate-config` only records options it considers
structurally necessary. They are restored in `hosts/kino/default.nix`, which
merges extra options into the generated list.

---

## 6. Fill in the three things only you know

`hosts/kino/default.nix` is written but has three markers in it.

**a) Your SSH key.** This is the one that locks you out if you skip it. The
host disables password authentication, so without a key there is no way in
over the network.

```bash
# ON THE THINKPAD:
cat ~/.ssh/id_ed25519.pub
```

Paste that line into `users.users.jerzy.openssh.authorizedKeys.keys` in
`hosts/kino/default.nix`. The file carries an assertion that fails the build
with a readable message if the list is empty, rather than letting you install
an unreachable machine.

**b) The auto-upgrade URL.** `system.autoUpgrade.flake` points at
`github:jerzyszyjut/nixos-config#kino`. Correct it if your repo lives
elsewhere, or set `enable = false` if you would rather update by hand.

**c) The battery thresholds.** `START_CHARGE_THRESH_BAT0` / `STOP_…` are a
ThinkPad feature. On other hardware TLP accepts them and does nothing —
harmless, but then a battery sits at 100% and warm forever, which is how
laptops-as-servers end up with a swollen battery. Check after boot with
`sudo tlp-stat -b`; if unsupported and the model allows it, run the machine
with the battery removed.

Then uncomment the `kino` block in `flake.nix` — it is the commented entry
under `nixosConfigurations`, already written.

---

## 7. Install

```bash
# CRITICAL: flakes only see git-TRACKED files. hardware-configuration.nix is
# brand new and therefore invisible to Nix until you stage it. This is the
# single most confusing failure in this whole document — see INSTALL.md's
# "path ... does not exist" entry.
git add -A
git status --short          # nothing should show as ??

nixos-install --flake .#kino --root /mnt
```

It asks for a root password at the end.

```bash
nixos-enter --root /mnt -c 'passwd jerzy'
reboot     # pull the USB
```

### First boot

```bash
# Move the config where the tooling expects it
sudo mv /etc/nixos-config ~/nixos-config
sudo chown -R $USER:users ~/nixos-config

# Join the tailnet — this is how the laptop will reach it, and how `kino`
# becomes a name that resolves.
sudo tailscale up

# Confirm the name the ThinkPad will use
tailscale status
```

`entertainment.serverHost = "kino"` in `flake.nix` assumes the tailnet name is
`kino`, which it will be if `networking.hostName` is `kino` and MagicDNS is on
in the tailnet admin panel. If Tailscale picked something else, either rename
it there or change `serverHost` to match.

Check the stack came up:

```bash
media-status      # all nine should be active (running)
media             # opens Homepage
```

Then **shut the lid and make sure nothing happens.** `ssh kino` from the
ThinkPad should still answer. If it does not, the logind settings did not take
— `cat /etc/systemd/logind.conf` and look for `HandleLidSwitch=ignore`.

---

## 8. Move the library across

Only now, with the server working. The library is the part that is expensive
to lose and slow to re-acquire, so it moves before the old copy is deleted,
and it is verified before anything is deleted at all.

**Stop the old stack first**, so nothing is writing while you copy:

```bash
# ON THE THINKPAD, before rebuilding it:
sudo systemctl stop media.target
```

Then copy. Over the tailnet:

```bash
# ON THE THINKPAD. Note the trailing slash on the source — without it you get
# /var/lib/media/media on the far end.
sudo rsync -aHAX --info=progress2 \
  /var/lib/media/ jerzy@kino:/var/lib/media/staging/
```

`-H` is not optional: it preserves the hardlinks between `torrents/` and
`library/`. Drop it and the copy arrives at twice the size, with every film
duplicated.

Copying into `staging/` rather than straight into place is deliberate —
`systemd-tmpfiles` owns the directory tree under `/var/lib/media` and sets
specific users and setgid bits on it, and rsync landing on top of that would
fight it. Move the contents into place on the server, then fix ownership:

```bash
# ON KINO:
sudo systemctl stop media.target
sudo rsync -aHAX --remove-source-files /var/lib/media/staging/ /var/lib/media/
sudo rm -rf /var/lib/media/staging

# Re-apply the ownership and setgid bits the profile declares
sudo systemd-tmpfiles --create
sudo chown -R qbittorrent:media /var/lib/media/torrents
sudo chown -R radarr:media      /var/lib/media/library/movies
sudo chown -R sonarr:media      /var/lib/media/library/tv
sudo find /var/lib/media -type d -exec chmod 2775 {} +
sudo find /var/lib/media -type f -exec chmod 0664 {} +

sudo systemctl start media.target
```

**Verify before deleting anything.** Sizes should match, and hardlinks should
have survived:

```bash
# both machines should report the same number
du -sh /var/lib/media

# a film imported by Radarr should show a link count of 2, not 1
stat -c '%h %n' /var/lib/media/library/movies/*/*.mkv | head
```

If that second command prints `1` everywhere, the hardlinks were lost in the
copy. Nothing is broken — the films play fine — but they are taking twice the
space, and the fix is to recopy with `-H`.

### The service databases

The films are only half of it. Radarr, Sonarr, Prowlarr and Jellyfin each keep
a SQLite database — your quality profiles, your indexers with their API keys,
and in Jellyfin's case your watch history and "continue watching" positions.

Two options:

**Redo the wiring** (~10 minutes, and the honest default). Follow
[MEDIA.md](MEDIA.md) on the new machine. You get clean databases, and the
click-through is short because it is the same one you already did once.

**Or copy the databases.** Faster, but the services must be stopped on both
ends and the versions should match:

```bash
# ON THE THINKPAD, with media.target stopped:
sudo tar czf ~/media-state.tar.gz \
  /var/lib/jellyfin /var/lib/radarr /var/lib/sonarr \
  /var/lib/prowlarr /var/lib/bazarr /var/lib/qbittorrent
scp ~/media-state.tar.gz kino:

# ON KINO, with media.target stopped:
sudo systemctl stop media.target
sudo tar xzf ~/media-state.tar.gz -C /
sudo systemctl start media.target
```

Then fix the paths inside each service. Radarr and Sonarr store **absolute**
root folder paths, and qBittorrent stores an absolute save path for every
torrent — if `/var/lib/media` means the same thing on both machines, which it
does if you followed step 4, these are already correct. If you put the library
somewhere else, each service's settings need updating by hand or it will
report every film as missing.

Jellyfin additionally remembers its own server URL for remote clients: in
Dashboard → Networking, clear any leftover LAN address from the old machine.

---

## 9. Strip the ThinkPad

Once films play from the server, on the laptop:

```bash
cd ~/nixos-config
git pull                    # or you are already on this commit
sudo nixos-rebuild switch --flake .#thinkpad
```

`flake.nix` already says `mediaServer.enable = false` for `thinkpad`, so this
is the rebuild that actually removes the services. What it does:

- stops and removes all nine units
- drops the `media` group and takes `jerzy` out of it
- closes port 51413 in the firewall
- removes `intel-compute-runtime`, installed only for Jellyfin transcoding
- keeps jellyfin-media-player, mpv, vlc, Spotify and Discord

What it does **not** do is delete any data. NixOS never removes `/var/lib`
state for a service you disable — a deliberate design choice, and the reason
your library is still sitting there as a fallback while you test the server.

Check what is left, then reclaim the space when you are ready:

```bash
systemctl list-units 'jellyfin*' 'radarr*' 'sonarr*' 'prowlarr*' 'qbittorrent*'
# should print nothing

du -sh /var/lib/media /var/lib/{jellyfin,radarr,sonarr,prowlarr,bazarr,qbittorrent}
```

**Only after you have watched something from the server**, and ideally a week
later rather than the same evening:

```bash
sudo rm -rf /var/lib/media
sudo rm -rf /var/lib/{jellyfin,radarr,sonarr,prowlarr,bazarr,qbittorrent}

# The old generations still reference the packages; this is what frees the GB
sudo nix-collect-garbage --delete-older-than 7d
```

Note that deleting old generations also deletes your ability to roll back to
a ThinkPad that ran the stack. That is the point, but do it in that order.

---

## Troubleshooting

**`ssh kino` times out.** Tailscale is how you reach it — `openFirewall =
false` on sshd means nothing on the LAN can. From the ThinkPad,
`tailscale status` should list kino as online. If it does not, the server is
not up, or `tailscale up` was never run on it.

**The machine sleeps anyway.** Two mechanisms, and both are handled in
`hosts/kino/default.nix`: the lid (`services.logind.settings.Login`) and
systemd's idle suspend (the masked `sleep`/`suspend` targets). If it still
sleeps, something else is doing it — check `journalctl -b | grep -i suspend`
for who requested it.

**Jellyfin buffers on 4K.** Almost always the network, not transcoding.
`iperf3` between the two machines; anything under ~100 Mbit will struggle with
a high-bitrate remux. The fix is ethernet, not a config change. If it really
is transcoding, `hardware.graphics.extraPackages` in the profile enables
Intel QuickSync — confirm Jellyfin is using it in Dashboard → Playback.

**Radarr says "file already exists" or imports are slow.** The hardlink check
from step 8: if link counts are 1, `/var/lib/media/torrents` and
`/var/lib/media/library` ended up on different filesystems or subvolumes.
`btrfs subvolume show /var/lib/media/torrents` and compare with the library
path — they must be the same subvolume.

**Permission denied writing to the library.** The three-user dance is
explained at the top of `modules/profiles/media-server.nix`: qBittorrent
writes, Radarr hardlinks, Jellyfin reads, and they meet in the `media` group
with setgid directories and `UMask=0002`. `stat` on a file should show group
`media` and `rw-rw-r--`. If not, re-run the ownership block in step 8.

**`error: path '«git+file:///…»/hosts/kino' does not exist`** — but the file
is plainly there. Nix evaluates the git tree, not your working directory.
`git add -A`, no commit needed.

**The build pulls in Hyprland and a whole desktop.** It does — `mkHost` gives
every machine `modules/nixos/desktop.nix`, and kino is a laptop with a screen
you will occasionally open. If you would rather it were headless, that is a
change to `mkHost` in `flake.nix` (move `desktop.nix` behind a profile), not
to `hosts/kino`. Worth doing eventually; not worth doing on install day.
