# Secrets

Encrypted values live in `secrets/secrets.yaml`, **which is committed to this
repo**. That sounds alarming and isn't: sops encrypts each value individually
and leaves the keys in plaintext, so the file is safe to publish and diffs stay
reviewable.

```yaml
eduroam:
    identity: ENC[AES256_GCM,data:Xk9...,type:str]
    password: ENC[AES256_GCM,data:pQ2...,type:str]
```

Two things can decrypt it: **your personal key** (so you can edit secrets from
any machine) and **the machine's own key** (so it can decrypt at boot with no
passphrase). Both are listed in `.sops.yaml`.

There's a chicken-and-egg problem: the machine's key derives from its SSH host
key, which doesn't exist until after the first boot. So this is a step-two task.
The system builds and boots fine with no secrets file at all — `eduroam` is
commented out in `net.nix` until you're ready.

---

## One-time setup

### 1. Your personal key

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

**Back this file up somewhere safe and offline.** Lose it and you can't edit
your own secrets. It is not in this repo and never should be — `.gitignore`
blocks `keys.txt`, but check before pushing.

Print the public half:

```bash
age-keygen -y ~/.config/sops/age/keys.txt
# age1abc123...
```

Paste that into `.sops.yaml` replacing `age1REPLACE_WITH_YOUR_PERSONAL_PUBLIC_KEY`.

### 2. The machine's key

Derived from the SSH host key, so there's nothing new to manage:

```bash
ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
# age1xyz789...
```

Paste that into `.sops.yaml` replacing `age1REPLACE_WITH_HOST_PUBLIC_KEY`.

If `/etc/ssh/ssh_host_ed25519_key.pub` doesn't exist, you haven't enabled
sshd. Either turn it on (`services.openssh.enable = true;`) or let sops-nix
generate its own key — `age.generateKey = true` in `secrets.nix` already
handles that, in which case use:

```bash
age-keygen -y /var/lib/sops-nix/key.txt
```

### 3. Create the secrets file

```bash
cd ~/nixos-config
sops secrets/secrets.yaml
```

This opens `$EDITOR` on a decrypted buffer. Fill in the values the config
expects:

```yaml
eduroam:
    identity: your.login@pg.edu.pl
    password: your-eduroam-password
tokens:
    huggingface: hf_xxxxxxxxxxxx
    wandb: xxxxxxxxxxxxxxxx
    github: ghp_xxxxxxxxxxxx
```

```yaml
eduroam:
    identity: your.login@pg.edu.pl
    password: your-eduroam-password
tokens:
    huggingface: hf_xxxxxxxxxxxx
    wandb: xxxxxxxxxxxxxxxx
    github: ghp_xxxxxxxxxxxx
ssh:
    hosts: |
        Host gradient
            HostName 10.x.x.x
            User jerzy
            IdentityFile ~/.ssh/default
            # Declared forwards: `ssh gradient` now makes a remote Jupyter
            # appear at localhost:8888 and TensorBoard at localhost:6006,
            # with no flags to remember.
            LocalForward 8888 localhost:8888
            LocalForward 6006 localhost:6006

        Host ovh
            HostName x.x.x.x
            User ubuntu
            IdentityFile ~/.ssh/digitalocean

        Host kask-gitlab
            HostName kask.example.edu
            User git
            IdentityFile ~/.ssh/default
```

The `ssh.hosts` value is **plain ssh_config text**, indented under `hosts: |`.
It gets decrypted to `/run/secrets/ssh/hosts` and pulled in by the `Include`
at the top of `home/jerzy/ssh.nix`, so neither the addresses nor the alias
names ever appear in the repo. Replace the placeholder addresses with your
real ones.

Two things to watch:

- **Indentation matters.** Everything under `hosts: |` must be indented
  consistently, and ssh_config's own indentation is decorative — only the
  YAML block indent is structural.
- **`Include` is read first**, and ssh uses the first value it finds for any
  option. So anything you put here wins over the global defaults in `ssh.nix`.

Save and close. Sops encrypts on write. Check what got committed:

```bash
git diff secrets/secrets.yaml   # every value should read ENC[AES256_GCM,...]
```

If you see plaintext, stop — `.sops.yaml` isn't being picked up. Run `sops` from
the repo root.

### 4. Turn on the things that need secrets

In `modules/nixos/net.nix`, uncomment the
`networking.networkmanager.ensureProfiles` block. Then:

```bash
nrs   # sudo nixos-rebuild switch --flake ~/nixos-config#thinkpad
```

Verify:

```bash
sudo ls -l /run/secrets/          # decrypted, tmpfs, root-owned
cat /run/secrets/tokens/wandb     # yours to read
nmcli connection show eduroam     # the profile exists
```

---

## Day to day

```bash
sops secrets/secrets.yaml     # edit (decrypt, open editor, re-encrypt on save)
sops -d secrets/secrets.yaml  # print decrypted to stdout, don't redirect to a file
```

**Adding a secret** is two edits: the value in `secrets/secrets.yaml`, and a
declaration in `modules/nixos/secrets.nix`:

```nix
"tokens/openai" = { owner = config.users.users.jerzy.name; };
```

It then appears at `/run/secrets/tokens/openai`.

**Using one in a shell.** Read the file rather than exporting a plaintext env
var from a dotfile:

```fish
set -x HF_TOKEN (cat /run/secrets/tokens/huggingface)
```

Better still, many tools take a path directly — `WANDB_API_KEY_FILE`,
`--token-file`, and so on. Prefer that; an env var is visible in `/proc` to
anything running as you.

---

## Adding a second machine

Each machine needs its own key added to `.sops.yaml`, and every existing secret
re-encrypted so the new key can read it:

```bash
# on the new machine
ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub

# on any machine that can already decrypt, after adding the key to .sops.yaml
sops updatekeys secrets/secrets.yaml
```

`updatekeys` is the step people forget. Without it the new host has a listed
key that no existing secret was encrypted to, and decryption fails at boot with
a confusing error.

---

## What does not belong here

- **Your age private key.** Back it up outside the repo.
- **SSH private keys.** Technically possible, but a hardware key or just
  copying them in by hand is simpler and less to go wrong.
- **Anything needed at evaluation time.** Sops secrets are only decrypted at
  runtime, so they can't be used for values Nix must read while building — a
  hostname in `joinNetworks`, a package name, a port number in the firewall.
  Only runtime consumers work: files read by a service, an env file, an
  `Include`d config fragment.

---

## If you lose your key

The secrets are unrecoverable. That's the design. Recovery means rotating every
credential at its source — regenerate the API tokens, change the eduroam
password — then creating a fresh `secrets.yaml` with a new key.

This is a good argument for keeping the number of secrets small, and for
treating the backup of `~/.config/sops/age/keys.txt` as seriously as you'd treat
a password manager export.
