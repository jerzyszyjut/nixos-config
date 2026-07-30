{ config, lib, pkgs, ... }:

let
  # Folders under $HOME to back up. Anything that doesn't exist yet (e.g. you
  # haven't created an Obsidian vault) is skipped rather than failing the run.
  backupPaths = [
    "Documents"
    "Obsidian"
    "Zotero"
  ];

  # Must match the remote name you pick when running `rclone config` — see
  # docs/BACKUP.md. "restic-backup" is just the folder restic creates inside
  # that remote; rename it there too if you change it here.
  remote = "gdrive";
  repoFolder = "restic-backup";

  backupScript = pkgs.writeShellApplication {
    name = "restic-gdrive-backup";
    runtimeInputs = [ pkgs.restic pkgs.rclone ];
    text = ''
      cd "$HOME"

      existing=()
      for p in ${lib.concatStringsSep " " backupPaths}; do
        if [ -d "$p" ]; then
          existing+=("$p")
        fi
      done

      if [ "''${#existing[@]}" -eq 0 ]; then
        echo "restic-gdrive-backup: none of ${lib.concatStringsSep ", " backupPaths} exist yet — skipping." >&2
        exit 0
      fi

      export RESTIC_REPOSITORY="rclone:${remote}:${repoFolder}"
      export RESTIC_PASSWORD_FILE="$HOME/.config/restic/password"

      restic backup --exclude-caches --tag automated "''${existing[@]}"
      restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
    '';
  };
in
{
  # One-time setup (rclone OAuth remote, restic password, restic init) is
  # manual and documented in docs/BACKUP.md — none of it can be declared in
  # Nix because the Google Drive OAuth flow needs a browser.
  systemd.user.services.restic-backup = {
    Unit.Description = "Backup Documents/Obsidian/Zotero to Google Drive (restic + rclone)";
    Service = {
      Type = "oneshot";
      ExecStart = "${backupScript}/bin/restic-gdrive-backup";
    };
  };

  systemd.user.timers.restic-backup = {
    Unit.Description = "Daily restic backup to Google Drive";
    Timer = {
      OnCalendar = "daily";
      Persistent = true; # runs on next login if the laptop was off/asleep
      RandomizedDelaySec = "30m";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
