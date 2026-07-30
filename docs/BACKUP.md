# Backup

`home/jerzy/backup.nix` declares a systemd **user** service + timer
(`restic-backup.service` / `.timer`) that runs `restic backup` daily against
`~/Documents`, `~/Obsidian`, and `~/Zotero`, storing the repository on Google
Drive through `rclone`. Any of those three folders that doesn't exist yet is
skipped rather than failing the run.

restic encrypts and deduplicates before anything leaves the machine, and keeps
30 days / 4 weeks / 6 months of history (`restic forget --prune`, run after
every backup). None of this backs up code — that's what git remotes are for.

Two pieces can't be declared in Nix: the Google Drive OAuth token, and the
repository encryption password. Both are one-time manual steps.

---

## One-time setup

### 1. Make your own Google Cloud client_id

rclone's shared `client_id` for Google Drive is being retired during 2026 —
`rclone lsd` prints a warning about this. Leaving client_id/client_secret
blank will work today but stop working without notice, so set up your own
now rather than redoing this later:

1. https://console.cloud.google.com/ → new project (any name)
2. APIs & Services → Enabled APIs → enable **Google Drive API**
3. APIs & Services → OAuth consent screen → External → fill the required
   fields (app name, your email) → add yourself as a test user → publish to
   "Testing" is enough, no Google review needed for personal use
4. APIs & Services → Credentials → Create Credentials → OAuth client ID →
   Application type **Desktop app** → note the client ID and client secret

Full walkthrough with screenshots if any step is unclear:
https://rclone.org/drive/#making-your-own-client-id

### 2. Create the rclone remote

```bash
rclone config
```

- `n` for new remote
- name it **`gdrive`** — this has to match `remote` in `backup.nix` (change
  both if you want a different name)
- type: `drive` (Google Drive)
- client_id / client_secret: paste the two values from step 1 (don't leave
  these blank — that's the shared one being retired)
- scope: `drive` (full access) or `drive.file` (only files rclone creates —
  more restrictive, recommended)
- decline "advanced config"
- accept "auto config" — it opens a browser for the OAuth consent screen
- decline "shared drive"

Confirm it worked:

```bash
rclone lsd gdrive:
```

### 3. Generate the restic password

```bash
mkdir -p ~/.config/restic
head -c 32 /dev/urandom | base64 > ~/.config/restic/password
chmod 600 ~/.config/restic/password
```

**Back this up somewhere outside this machine** (a password manager entry is
fine). Lose it and the Drive backup is unrecoverable — restic never stores it
anywhere, by design.

### 4. Initialize the repository

Your login shell is fish (`export` is bash/zsh syntax and won't work), so
these pass everything as flags instead — works the same in any shell:

```bash
restic -r rclone:gdrive:restic-backup --password-file ~/.config/restic/password init
```

### 5. Start the timer

`nrs` already enables it (`Install.WantedBy = [ "timers.target" ]` in
`backup.nix`) — this just starts it for the current session without a
re-login:

```bash
systemctl --user start restic-backup.timer
systemctl --user list-timers restic-backup.timer   # confirm it's scheduled
```

Run it once by hand to check everything's wired up:

```bash
systemctl --user start restic-backup.service
journalctl --user -u restic-backup.service -f
```

---

## Restoring

```bash
restic -r rclone:gdrive:restic-backup --password-file ~/.config/restic/password snapshots
restic -r rclone:gdrive:restic-backup --password-file ~/.config/restic/password restore latest --target ~/restore
```

(Or set `RESTIC_REPOSITORY` / `RESTIC_PASSWORD_FILE` with `set -x` first in
fish, `export` in bash/zsh, if typing `-r`/`--password-file` every time gets
old.)

## Adding another folder

Add it to `backupPaths` in `home/jerzy/backup.nix` and `nrs`. Nothing else to
touch — the script filters to whatever actually exists on disk at run time.
