# Study tools: Obsidian, Anki, Zotero

`obsidian`, `anki`, and `zotero` are installed as plain packages
(`home/jerzy/packages.nix`) — nothing about them is declared beyond that, so
setup is the normal first-run wizard for each. Two things are worth doing
deliberately: where things live on disk (backup depends on it), and wiring
Zotero's citation library into Typst.

## Vault / library locations

`home/jerzy/backup.nix` backs up `~/Documents`, `~/Obsidian`, and `~/Zotero`
daily. Use those exact paths for the backup to actually cover them:

- **Obsidian**: when it asks for a vault location on first run, create it at
  `~/Obsidian`.
- **Zotero**: `~/Zotero` is Zotero's own default data directory, so no change
  needed — just confirm it under Edit → Settings → Advanced → Files and
  Folders.

If you'd rather use different paths, that's fine — just update `backupPaths`
in `backup.nix` to match (see docs/BACKUP.md).

## Zotero → Typst citations (Better BibTeX)

Typst can cite from a `.bib` or Hayagriva `.yaml` file directly
(`#bibliography("refs.bib")`), but Zotero doesn't keep one on disk on its
own — the **Better BibTeX** plugin adds live-exported `.bib`/`.yaml` files
that update automatically as your library changes.

This isn't packaged in nixpkgs — Zotero doesn't support Firefox-style
enterprise policy install, and the extension storage format has changed
across Zotero versions, so hand-installing the `.xpi` is the reliable path:

1. Download the latest release from
   https://github.com/retorquere/zotero-better-bibtex/releases (the `.xpi`
   file, not the source archive).
2. In Zotero: Tools → Add-ons → gear icon → Install Add-on From File → pick
   the downloaded `.xpi`. Restart Zotero when prompted.
3. Right-click a collection (or "My Library") → Export Collection → format
   **Better BibLaTeX** (`.bib`) or **Better CSL YAML** (`.yaml` — what
   Hayagriva/Typst prefers) → check **Keep updated** → save it somewhere
   under your project or notes directory.
4. In the `.typ` file: `#bibliography("refs.bib")`, then cite with
   `@citekey`.

"Keep updated" means the export file rewrites itself whenever the library
changes — no manual re-export per project.
