#!/usr/bin/env bash
# Verify this repo is complete and visible to Nix before running a build.
#
#   ./scripts/check-tree.sh
#
# Two separate failure modes are checked, because they look identical from the
# error message but have different fixes:
#   1. a file is missing from disk        -> get it from the package
#   2. a file exists but is untracked     -> git add it
#
# Flakes only evaluate git-tracked files, so (2) produces
# "path '...' does not exist" even though ls shows the file plainly.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

REQUIRED=(
  flake.nix
  .sops.yaml
  .gitignore
  hosts/thinkpad/default.nix
  hosts/thinkpad/hardware-configuration.nix
  modules/nixos/base.nix
  modules/nixos/desktop.nix
  modules/nixos/dev.nix
  modules/nixos/net.nix
  modules/nixos/secrets.nix
  modules/nixos/style.nix
  home/jerzy/default.nix
  home/jerzy/apps.nix
  home/jerzy/waybar.nix
  home/jerzy/ssh.nix
  home/jerzy/packages.nix
  dotfiles/hypr/hyprland.conf
  dotfiles/tmux.conf
  dotfiles/nvim/init.lua
  dotfiles/nvim/lua/custom/plugins/init.lua
  docs/INSTALL.md
  docs/KEYBINDS.md
  docs/SECRETS.md
  docs/MAINTENANCE.md
  README.md
)

missing=0
untracked=0

echo "--- file presence ---"
for f in "${REQUIRED[@]}"; do
  if [ ! -f "$f" ]; then
    echo "  MISSING   $f"
    missing=$((missing + 1))
  fi
done
[ "$missing" -eq 0 ] && echo "  all ${#REQUIRED[@]} required files present"

if [ -d .git ]; then
  echo
  echo "--- git visibility (flakes ignore untracked files) ---"
  for f in "${REQUIRED[@]}"; do
    if [ -f "$f" ] && ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      echo "  UNTRACKED $f"
      untracked=$((untracked + 1))
    fi
  done
  if [ "$untracked" -eq 0 ]; then
    echo "  everything tracked"
  else
    echo
    echo "  fix: git add -A"
  fi

  echo
  echo "--- kickstart tree ---"
  ks=$(find dotfiles/nvim/lua/kickstart -name '*.lua' 2>/dev/null | wc -l)
  echo "  $ks lua files under dotfiles/nvim/lua/kickstart (expect 7)"
else
  echo
  echo "  not a git repo yet — run: git init && git add -A"
fi

echo
echo "--- things that must exist only if referenced ---"
if grep -q '^\s*image = \./wallpaper' modules/nixos/style.nix 2>/dev/null; then
  if [ -f modules/nixos/wallpaper.jpg ]; then
    echo "  wallpaper enabled and present"
  else
    echo "  ERROR: style.nix references ./wallpaper.jpg but it is missing."
    echo "         A Nix path literal must exist at evaluation time."
    missing=$((missing + 1))
  fi
else
  echo "  wallpaper disabled (fine — enable after first boot)"
fi

if grep -q '^\s*defaultSopsFile' modules/nixos/secrets.nix 2>/dev/null; then
  if [ -f secrets/secrets.yaml ]; then
    echo "  sops enabled and secrets.yaml present"
  else
    echo "  ERROR: secrets.nix references secrets/secrets.yaml but it is missing."
    echo "         See docs/SECRETS.md, or re-comment the sops block."
    missing=$((missing + 1))
  fi
else
  echo "  sops disabled (fine — enable after docs/SECRETS.md)"
fi

echo
if [ "$missing" -eq 0 ] && [ "$untracked" -eq 0 ]; then
  echo "READY. Build with:"
  echo "  nixos-install --flake .#thinkpad --root /mnt      # from the installer"
  echo "  sudo nixos-rebuild switch --flake .#thinkpad      # on a running system"
  exit 0
else
  echo "NOT READY: $missing missing, $untracked untracked."
  exit 1
fi
