# Maintenance

## Daily commands

```bash
nrs                 # rebuild and switch (aliased)
nrt                 # rebuild and activate WITHOUT adding a boot entry
```

Use `nrt` when experimenting. If it breaks something, reboot and you're back to
the last known-good system — the broken config was never written to the
bootloader.

```bash
nixos-rebuild build --flake ~/nixos-config#thinkpad   # build only, don't apply
nix flake check                                        # evaluate without building
```

## Updating

```bash
cd ~/nixos-config
nix flake update            # bump every input
nrs

# or one at a time, which is easier to bisect when something breaks
nix flake update nixpkgs
nix flake update home-manager
```

`flake.lock` is committed. That's the point — the same commit produces the same
system on any machine, at any time. Commit the lock file change along with
whatever prompted the update.

## Rolling back

```bash
# From a running system
sudo nixos-rebuild switch --rollback

# List what you can go back to
nixos-rebuild list-generations

# Boot into an older generation: hold Space during boot for the systemd-boot
# menu, then pick an older entry
```

Nothing you do in this repo is unrecoverable. That's the main reason to be
adventurous with it.

## Disk space

The Nix store grows if left alone. Automatic GC runs weekly with 14-day
retention and store optimisation is on, but when you want to reclaim space
manually:

```bash
nix-store --gc --print-dead      # what would be freed
sudo nix-collect-garbage -d      # delete all old generations, aggressively
nix-tree                         # interactive: what's taking up space and why
du -sh /nix/store
docker system prune -a           # separately, Docker images add up fast
```

`sudo nix-collect-garbage -d` deletes your rollback targets. Don't run it right
after an upgrade you haven't confidence in yet.

## Btrfs snapshots

Independent of Nix generations — these cover `/home`, which Nix doesn't manage.

```bash
sudo btrfs subvolume snapshot -r /home /.snapshots/home-$(date +%F)
sudo btrfs subvolume list /
sudo btrfs filesystem usage /
```

Worth automating with `snapper` or a systemd timer once you care.

---

## Where do I change...

| Thing | File |
|---|---|
| Colour scheme, fonts, wallpaper | `modules/nixos/style.nix` |
| A system package | `modules/nixos/dev.nix` or `base.nix` |
| A user package or GUI app | `home/jerzy/packages.nix` |
| Terminal, PDF viewer, file manager settings | `home/jerzy/apps.nix` |
| Status bar layout and styling | `home/jerzy/waybar.nix` |
| WM keybinds, gaps, animations | `dotfiles/hypr/hyprland.conf` |
| SSH hosts and port forwards | `home/jerzy/ssh.nix` |
| Shell aliases, git identity | `home/jerzy/default.nix` |
| Neovim plugins | `dotfiles/nvim/lua/custom/plugins/init.lua` |
| Language servers | `home/jerzy/packages.nix` **and** the `servers` table in `dotfiles/nvim/init.lua` |
| Encrypted credentials | `secrets/secrets.yaml` via `sops` |
| Bootloader, power, battery thresholds | `hosts/thinkpad/default.nix` |
| VPN, Tailscale, WiFi | `modules/nixos/net.nix` |
| Private SSH hosts | `secrets/secrets.yaml` via `sops` |

Files under `dotfiles/` are symlinked with `mkOutOfStoreSymlink`, so editing
them takes effect **without a rebuild**. Everything else needs `nrs`.

---

## Per-project development environments

The point of `direnv` + `nix-direnv` is that you stop installing language
toolchains globally. In any project:

```bash
cd ~/dev/some-project
nix flake init -t templates#python    # or write flake.nix by hand
echo "use flake" > .envrc
direnv allow
```

Entering the directory now activates that project's toolchain; leaving it
deactivates. Add `.envrc` to your global gitignore if collaborators don't use
Nix.

For Python specifically, `uv` inside a plain venv is usually less friction than
a Nix devShell, and it works because of `programs.nix-ld`:

```bash
uv venv && uv pip install -r requirements.txt
```

---

## Adding a second machine

1. `mkdir -p hosts/newmachine` and write a `default.nix` — bootloader,
   hostname, power settings.
2. `nixos-generate-config --show-hardware-config > hosts/newmachine/hardware-configuration.nix`
   on that machine.
3. Add a `nixosConfigurations.newmachine` block in `flake.nix`, importing the
   shared `modules/nixos/*` and its own host directory.
4. Move anything host-specific out of the shared modules as you discover it.
5. Add the new machine's age key to `.sops.yaml` and run
   `sops updatekeys secrets/secrets.yaml` — see [SECRETS.md](SECRETS.md).
   Without this the new host can't decrypt your SSH hosts or WiFi credentials.

Deploying to another machine over SSH once it exists:

```bash
nixos-rebuild switch --flake .#newmachine --target-host root@newmachine
```

---

## Using this config on the remote hosts

If Nix is available on a remote host, Home Manager works standalone there — same
shell, same Neovim, same everything:

```bash
nix run home-manager/master -- switch --flake ~/nixos-config#jerzy
```

That needs a `homeConfigurations` output added to `flake.nix`, which this repo
doesn't have yet. If Nix isn't available, the fallback is why `dotfiles/`
contains plain files rather than Nix-generated ones:

```bash
git clone https://github.com/YOURNAME/nixos ~/nixos-config
ln -s ~/nixos-config/dotfiles/nvim ~/.config/nvim
ln -s ~/nixos-config/dotfiles/fish ~/.config/fish
ln -s ~/nixos-config/dotfiles/tmux.conf ~/.tmux.conf
```

Neovim's config is deliberately not themed by Stylix for exactly this reason —
it looks identical everywhere.

---

## Debugging evaluation errors fast

`nixos-install` and `nixos-rebuild` re-download and rebuild before they tell you
about a config mistake. Evaluate only — seconds instead of minutes:

```bash
nix eval .#nixosConfigurations.thinkpad.config.system.build.toplevel.drvPath 2>&1 | tail -40
```

Nix truncates stack traces by default, and the useful part is the **last** few
lines, not the first. Always pipe through `tail`:

```bash
nix eval .#nixosConfigurations.thinkpad.config.system.build.toplevel.drvPath \
  --show-trace 2>&1 | tail -60
```

To find which module is at fault, disable suspects one at a time. Stylix touches
the most surface area, so it's the usual first thing to rule out:

```nix
stylix.enable = false;   # in modules/nixos/style.nix
```

If evaluation then succeeds, the problem is a Stylix option; if it still fails,
Stylix is innocent and you've eliminated the largest variable in one step.

## Troubleshooting

**Rebuild fails with "unknown option".** An option was renamed upstream, or
belongs to a newer home-manager/Stylix than your pinned version. The error names
the file and line. Known candidate: `programs.ssh.enableDefaultConfig`.

**Rebuild fails with "conflicting definition".** The same option is set in two
places. Common causes: Stylix and a manual `gtk.theme`, or `system.stateVersion`
in two modules.

**Home Manager: "file exists, would be clobbered".** `backupFileExtension` is
set to `hm-bak`, so it moves the old file aside. If it still fails, delete the
offending path by hand.

**Python import errors about missing `.so` files.** A library is missing from
`programs.nix-ld.libraries` in `dev.nix`. Find which one:

```bash
ldd .venv/lib/python3*/site-packages/<pkg>/_something.so | grep 'not found'
```

Then add the corresponding Nix package to the list.

**Screen sharing shows a black window.** Portals aren't running:

```bash
systemctl --user status xdg-desktop-portal xdg-desktop-portal-hyprland
```

**Neovim: no language servers.** `:checkhealth vim.lsp`. Confirm the binary is
on `PATH` (`which pyright`), then that it's in the `servers` table in
`dotfiles/nvim/init.lua`. Both are required.

**Neovim: plugins don't load.** Check `nvim --version` is 0.12+ — kickstart uses
`vim.pack`, which doesn't exist in 0.11. Switch to `unstable.neovim` in
`packages.nix` if needed.

**Chinese input not working.** Confirm `fcitx5` is running (`pgrep fcitx5`), that
the environment variables in `home/jerzy/default.nix` are set (`env | grep IM`),
and add the layouts with `fcitx5-configtool`.

**Waybar is blank or unstyled.** `pkill waybar && waybar` in a terminal prints
CSS parse errors, which are otherwise silent.

**Battery drains fast.** Check `powertop`, confirm `tlp` is active
(`systemctl status tlp`) and that `power-profiles-daemon` is *not* — they
conflict. Blur is off in `hyprland.conf` for the same reason; leave it that way
on battery.

**A file you just added is "not found".** Flakes only see git-tracked files.
`git add` it. This catches everyone, repeatedly, forever.

**Something broke and you don't know what.** `git diff` — every change to this
system is a change to a tracked file. That's the whole point.
