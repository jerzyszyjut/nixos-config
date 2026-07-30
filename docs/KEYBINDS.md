# Keybinds

Everything in one place. `Super` is the Windows key.

**Caps Lock is Escape**, remapped by `keyd` at the system level — it works in
the TTY, in Hyprland, and inside every application, including over SSH once
you're in a remote Neovim.

---

## Hyprland — windows and workspaces

| Key | Action |
|---|---|
| `Super` `Return` | Terminal (kitty) |
| `Super` `D` | App launcher (fuzzel) |
| `Super` `W` | Firefox |
| `Super` `E` | File manager (yazi in a terminal) |
| `Super` `Q` | Close window |
| `Super` `Escape` | Lock screen |
| `Super` `Shift` `Q` | Exit Hyprland |
| `Super` `H` `J` `K` `L` | Move focus left/down/up/right |
| `Super` `Shift` `H/J/K/L` | Move the window itself |
| `Super` `F` | Fullscreen |
| `Super` `T` | Toggle floating |
| `Super` `P` | Pseudo-tile |
| `Super` `1`–`5` | Switch workspace |
| `Super` `Shift` `1`–`5` | Send window to workspace |
| `Super` `V` | Clipboard history (cliphist → fuzzel) |
| `Print` | Screenshot focused window → clipboard |
| `Shift` `Print` | Screenshot region → clipboard |
| `Super` + drag | Move window with mouse |
| `Super` + right-drag | Resize window with mouse |

Hardware keys (volume, brightness, media) work as labelled.

`hyprctl binds` lists every binding as Hyprland actually parsed it. Use it when
a key seems dead — a duplicate binding silently loses to whichever came last.

---

## kitty — terminal

| Key | Action |
|---|---|
| `Ctrl` `Shift` `Enter` | New window in the current directory |
| `Ctrl` `Shift` `Z` | Toggle stack layout (zoom current pane) |
| `Ctrl` `=` / `Ctrl` `-` | Font size |
| `Ctrl` `Shift` `B` | Broadcast — type into every pane at once |
| `Ctrl` `Shift` `G` | Send scrollback to Neovim |
| `Ctrl` `Shift` `H` | Send last command's output to Neovim |

**Hints — the mouse-free feature.** Press `Ctrl` `Shift` `P`, then:

| Then | Selects |
|---|---|
| `U` | URLs — opens in the browser |
| `F` | File paths |
| `L` | Whole lines |
| `H` | Git hashes |
| `W` | Words |

Every match gets a letter overlaid; press it. This is how you click a link in a
build log without touching the pointer.

**Useful commands** rather than keybinds:

```bash
s myhost                  # abbreviation for `kitten ssh` — ships terminfo
kitten icat plot.png      # display an image inline, works over SSH
kitten diff a.py b.py     # side-by-side diff with syntax highlighting
```

---

## zellij — multiplexer

Zellij shows its own keybinds in a status bar, so this is a starting point
rather than something to memorise. `Ctrl` `G` locks/unlocks input if it's
swallowing keys your editor wants.

| Key | Action |
|---|---|
| `Ctrl` `P` then `N` | New pane |
| `Ctrl` `P` then `D` | New pane, split down |
| `Ctrl` `P` then `X` | Close pane |
| `Ctrl` `P` then `F` | Fullscreen pane |
| `Ctrl` `T` then `N` | New tab |
| `Ctrl` `T` then `1`–`9` | Go to tab |
| `Ctrl` `N` | Resize mode |
| `Ctrl` `S` | Scroll/search mode |
| `Ctrl` `O` then `D` | Detach session |
| `Ctrl` `Q` | Quit |

```bash
zellij attach            # reattach to a running session
zellij ls                # list sessions
```

**On your remote hosts, use tmux** — it's what's already installed there. The
multiplexer that matters is the one running on the server, because that's the
one that survives your laptop suspending.

---

## Neovim

Leader is `Space`. Kickstart's own bindings plus the additions in
`lua/custom/plugins/init.lua`.

### Movement and search

| Key | Action |
|---|---|
| `s` + 2 chars | **Flash jump** — labels every match, press one to teleport |
| `S` | Flash treesitter — select a syntax node |
| `-` | Oil — edit the current directory as a buffer |
| `<leader>sf` | Search files |
| `<leader>sg` | Live grep across the project |
| `<leader>sh` | Search help |
| `<leader>sk` | Search keymaps |
| `<leader><leader>` | Open buffers |
| `<leader>e` | File explorer (snacks) |

Flash is the one worth building a habit around. It replaces most `w`/`b`/`f`
chains and counted motions.

### LSP

| Key | Action |
|---|---|
| `grd` | Go to definition |
| `grr` | References |
| `gri` | Implementation |
| `grn` | Rename symbol |
| `gra` | Code action |
| `gO` | Document symbols |
| `K` | Hover documentation |
| `<leader>q` | Diagnostics to location list |
| `<leader>th` | Toggle inlay hints |

`:checkhealth vim.lsp` shows which servers attached. `:LspInfo` no longer
exists in Neovim 0.11+.

### Claude Code

| Key | Action |
|---|---|
| `<leader>ac` | Toggle Claude Code |
| `<leader>af` | Focus the Claude pane |
| `<leader>as` | *(visual)* Send selection as context |
| `<leader>ab` | Add current buffer as context |
| `<leader>aa` | Accept proposed diff |
| `<leader>ad` | Reject proposed diff |

Proposed changes open in a normal Neovim diff — you can edit them before
accepting.

### Python / notebooks (molten)

| Key | Action |
|---|---|
| `<leader>mi` | Initialise a Jupyter kernel |
| `<leader>ml` | Evaluate current line |
| `<leader>mv` | *(visual)* Evaluate selection |
| `<leader>mr` | Re-evaluate cell |
| `<leader>mo` | Show output window |
| `<leader>vs` | Select a uv virtualenv |

Plots render **inline in the terminal** via kitty's graphics protocol, which
means this works unchanged over SSH on a remote box. Needs the one-time Python
env described in `lua/custom/plugins/init.lua`.

### Git

| Key | Action |
|---|---|
| `<leader>gn` | Neogit (staging, rebase, log — the magit equivalent) |
| `<leader>gg` | Lazygit |
| `<leader>hs` / `<leader>hr` | Stage / reset hunk (gitsigns) |
| `]c` / `[c` | Next / previous hunk |

### LaTeX (vimtex)

| Key | Action |
|---|---|
| `<leader>ll` | Start continuous compilation |
| `<leader>lv` | Forward search — jump to this line in zathura |
| `<leader>lc` | Clean auxiliary files |
| `<leader>le` | Show compile errors |
| `dse` / `cse` | Delete / change surrounding environment |
| `]]` / `[[` | Next / previous section |

Inverse search works too: `Ctrl` + click in zathura jumps to the source line.

### Sessions

| Key | Action |
|---|---|
| `<leader>qs` | Restore the session for this directory |

---

## yazi — file manager

| Key | Action |
|---|---|
| `h` `j` `k` `l` | Navigate |
| `Enter` | Open |
| `.` | Toggle hidden files |
| `y` / `x` / `p` | Copy / cut / paste |
| `d` | Trash |
| `D` | Delete permanently |
| `a` | Create file (end with `/` for a directory) |
| `r` | Rename |
| `Space` | Select |
| `/` | Search |
| `z` | Jump with zoxide |
| `q` | Quit |
| `Q` | Quit without changing directory |

`q` returns your shell to yazi's current directory. That's usually what you
want; `Q` is the escape hatch.

---

## zathura — PDFs

| Key | Action |
|---|---|
| `j` / `k` | Scroll |
| `J` / `K` | Next / previous page |
| `gg` / `G` | First / last page |
| `<n>G` | Go to page n |
| `/` | Search, `n`/`N` to cycle |
| `Tab` | Table of contents |
| `a` | Fit page |
| `s` | Fit width |
| `d` | Dual-page mode |
| `r` | Rotate |
| `Ctrl` `R` | Invert colours |
| `f` | Follow link |
| `Ctrl` + click | Jump to LaTeX source (SyncTeX) |
| `q` | Quit |

Dark recolouring is on by default, which is what you want for reading papers at
night. `Ctrl` `R` flips it when a figure looks wrong.

---

## Other TUIs

**lazygit** — `Space` stage, `c` commit, `P` push, `p` pull, `?` help.
**k9s** — `:pods`, `l` logs, `d` describe, `Ctrl` `D` delete, `?` help.
**btop** — `Esc` menu, `f` filter, `k` kill, `+`/`-` collapse.
**lazydocker** — arrows to navigate, `d` remove, `r` restart, `?` help.
**aerc** — `Enter` open, `D` delete, `a` archive, `Ctrl` `T` switch account.

---

## Shell

| Key | Action |
|---|---|
| `Ctrl` `R` | Atuin — searchable history across all your machines |
| `Ctrl` `T` | fzf file picker |
| `Alt` `C` | fzf directory jump |
| `Ctrl` `F` | Accept fish's autosuggestion |
| `Alt` `→` | Accept one word of the suggestion |

Aliases and abbreviations defined in `home/jerzy/default.nix`:

| Command | Expands to |
|---|---|
| `nrs` | `sudo nixos-rebuild switch --flake ~/nixos-config#thinkpad` |
| `nrt` | `sudo nixos-rebuild test --flake ...` (no boot entry added) |
| `s` | `kitten ssh` |
| `ls` / `ll` | `eza` / `eza -l --git` |
| `cat` | `bat` |

`z <partial-name>` jumps to any directory you've visited (zoxide).

---

## Input methods

`Ctrl` `Space` cycles between English and your Chinese input methods (Pinyin,
Cangjie, Chewing). `fcitx5-configtool` adds or reorders them.
