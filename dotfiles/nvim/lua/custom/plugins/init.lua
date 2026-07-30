-- Loaded by init.lua via `require 'custom.plugins'`.
--
-- IMPORTANT: kickstart uses Neovim's built-in `vim.pack`, not lazy.nvim. So
-- plugins are added imperatively with vim.pack.add and configured immediately
-- afterwards — there is no spec table to return and no `opts`/`keys` fields.
--
-- vim.pack requires Neovim 0.12 or newer. Check with `nvim --version`; if
-- you're on 0.11, see the note in home/jerzy/packages.nix about pulling neovim
-- from nixpkgs-unstable.

local function gh(repo) return 'https://github.com/' .. repo end
local map = vim.keymap.set

-- ===========================================================================
-- COLORSCHEME — Gruvbox Material
-- ===========================================================================
-- Matches what Stylix applies to the rest of the system, and travels to
-- the remote boxes, where Stylix doesn't exist. Kickstart installs tokyonight and
-- sets it in SECTION 4; this runs later and overrides it.
vim.pack.add { gh 'sainnhe/gruvbox-material' }
vim.g.gruvbox_material_background = 'medium' -- soft | medium | hard
vim.g.gruvbox_material_foreground = 'material' -- material | mix | original
vim.g.gruvbox_material_better_performance = 1
vim.g.gruvbox_material_enable_italic = 1
vim.cmd.colorscheme 'gruvbox-material'

-- ===========================================================================
-- CLAUDE CODE
-- ===========================================================================
vim.pack.add {
  gh 'folke/snacks.nvim',
  gh 'coder/claudecode.nvim',
}
require('snacks').setup {
  bigfile = { enabled = true },
  quickfile = { enabled = true },
  notifier = { enabled = true },
  lazygit = { enabled = true },
  explorer = { enabled = true },
  picker = { enabled = true },
}
require('claudecode').setup {}

map('n', '<leader>ac', '<cmd>ClaudeCode<cr>', { desc = 'Claude: toggle' })
map('n', '<leader>af', '<cmd>ClaudeCodeFocus<cr>', { desc = 'Claude: focus' })
map('v', '<leader>as', '<cmd>ClaudeCodeSend<cr>', { desc = 'Claude: send selection' })
map('n', '<leader>ab', '<cmd>ClaudeCodeAdd %<cr>', { desc = 'Claude: add buffer' })
map('n', '<leader>aa', '<cmd>ClaudeCodeDiffAccept<cr>', { desc = 'Claude: accept diff' })
map('n', '<leader>ad', '<cmd>ClaudeCodeDiffDeny<cr>', { desc = 'Claude: deny diff' })

map('n', '<leader>gg', function() Snacks.lazygit() end, { desc = 'Lazygit' })
map('n', '<leader>e', function() Snacks.explorer() end, { desc = 'Explorer' })

-- ===========================================================================
-- NAVIGATION — the keyboard-only payoff
-- ===========================================================================
-- flash: press `s`, then two characters, then a label to jump anywhere on
-- screen. Biggest single reduction in keystrokes of anything here.
vim.pack.add { gh 'folke/flash.nvim' }
require('flash').setup {}
map({ 'n', 'x', 'o' }, 's', function() require('flash').jump() end, { desc = 'Flash jump' })
map({ 'n', 'x', 'o' }, 'S', function() require('flash').treesitter() end, { desc = 'Flash treesitter' })

-- oil: edit the filesystem as a buffer. `cw` to rename, `dd` to delete, type a
-- new line to create, then `:w` to apply.
vim.pack.add { gh 'stevearc/oil.nvim' }
require('oil').setup { view_options = { show_hidden = true } }
map('n', '-', '<cmd>Oil<cr>', { desc = 'Open parent directory' })

-- ===========================================================================
-- PYTHON / ML — the reason kitty was the right terminal
-- ===========================================================================
-- molten runs code cells against a Jupyter kernel and renders matplotlib
-- output INLINE via kitty's graphics protocol. Because it goes through the
-- terminal, it works unchanged over SSH on the TASK nodes — no port
-- forwarding, no browser.
--
-- Setup, once:
--   uv venv ~/.venvs/nvim
--   ~/.venvs/nvim/bin/python -m ensurepip
--   VIRTUAL_ENV=~/.venvs/nvim uv pip install \
--     pynvim jupyter_client cairosvg pnglatex plotly kaleido pyperclip ipykernel
--   then uncomment python3_host_prog below and run :UpdateRemotePlugins
vim.pack.add {
  gh '3rd/image.nvim',
  gh 'benlubas/molten-nvim',
}
require('image').setup {
  backend = 'kitty',
  max_width = 100,
  max_height = 20,
  integrations = { markdown = { enabled = true } },
}
vim.g.molten_image_provider = 'image.nvim'
vim.g.molten_output_win_max_height = 24
vim.g.molten_auto_open_output = false
vim.g.molten_virt_text_output = true
-- vim.g.python3_host_prog = vim.fn.expand '~/.venvs/nvim/bin/python3'

map('n', '<leader>mi', '<cmd>MoltenInit<cr>', { desc = 'Molten: init kernel' })
map('n', '<leader>ml', '<cmd>MoltenEvaluateLine<cr>', { desc = 'Molten: eval line' })
map('n', '<leader>mr', '<cmd>MoltenReevaluateCell<cr>', { desc = 'Molten: re-eval cell' })
map('v', '<leader>mv', ':<C-u>MoltenEvaluateVisual<cr>gv', { desc = 'Molten: eval selection' })
map('n', '<leader>mo', '<cmd>MoltenShowOutput<cr>', { desc = 'Molten: show output' })

-- Pick the right uv venv per project so pyright resolves imports.
vim.pack.add { gh 'linux-cultist/venv-selector.nvim' }
require('venv-selector').setup {}
map('n', '<leader>vs', '<cmd>VenvSelect<cr>', { desc = 'Select venv' })

-- ===========================================================================
-- TYPST
-- ===========================================================================
vim.pack.add { gh 'chomosuke/typst-preview.nvim' }
require('typst-preview').setup { dependencies_bin = { tinymist = 'tinymist' } }
map('n', '<leader>tp', '<cmd>TypstPreviewToggle<cr>', { desc = 'Typst: toggle preview' })

-- ===========================================================================
-- GIT — the magit-equivalent
-- ===========================================================================
vim.pack.add {
  gh 'nvim-lua/plenary.nvim',
  gh 'sindrets/diffview.nvim',
  gh 'NeogitOrg/neogit',
}
require('neogit').setup { graph_style = 'unicode' }
map('n', '<leader>gn', '<cmd>Neogit<cr>', { desc = 'Neogit' })

-- ===========================================================================
-- QUALITY OF LIFE
-- ===========================================================================
-- Restore buffers, windows and cursor positions per directory.
vim.pack.add { gh 'folke/persistence.nvim' }
require('persistence').setup {}
map('n', '<leader>qs', function() require('persistence').load() end, { desc = 'Restore session' })

-- Markdown rendered in-buffer.
vim.pack.add { gh 'MeanderingProgrammer/render-markdown.nvim' }
require('render-markdown').setup {}

-- Postgres from inside the editor; you already have psql and libpq.
vim.g.db_ui_use_nerd_fonts = 1
vim.pack.add {
  gh 'tpope/vim-dadbod',
  gh 'kristijanhusak/vim-dadbod-ui',
  gh 'kristijanhusak/vim-dadbod-completion',
}

-- Debug adapter for Python. debugpy comes from Nix, not mason.
vim.pack.add {
  gh 'mfussenegger/nvim-dap',
  gh 'mfussenegger/nvim-dap-python',
}
require('dap-python').setup 'python3'

-- Send kitty's scrollback into Neovim so you can search and yank terminal
-- history with vim motions. Paired with the kitty keybinds in apps.nix.
vim.pack.add { gh 'mikesmithgh/kitty-scrollback.nvim' }
require('kitty-scrollback').setup {}
