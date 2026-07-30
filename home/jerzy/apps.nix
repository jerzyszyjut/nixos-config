{ config, lib, pkgs, ... }:

{
  # ---- terminal: kitty ---------------------------------------------------
  # Two features here matter specifically for your workflow:
  #
  # 1. THE SSH KITTEN. `kitten ssh task` copies kitty's terminfo to the remote
  #    host automatically, so colors, Home/End, and Ctrl-arrow all behave on
  #    Ubuntu servers with no setup per host. The `s` abbreviation below makes
  #    it the default way you connect.
  #    Caveat: test it against the ControlMaster multiplexing in ssh.nix. If
  #    they interact badly, plain `ssh` still works fine.
  #
  # 2. THE GRAPHICS PROTOCOL. `kitten icat plot.png` displays images inline —
  #    including over SSH. You can look at matplotlib output on a compute node
  #    without copying files back or forwarding X11.
  programs.kitty = {
    enable = true;
    shellIntegration.enableFishIntegration = true;
    settings = {
      scrollback_lines = 10000;
      enable_audio_bell = false;
      window_padding_width = 8;
      confirm_os_window_close = 0;
      cursor_shape = "beam";
      cursor_trail = 1;
      # kitty has native tabs and splits, so zellij below is only really
      # needed for sessions that must survive a disconnect.
      tab_bar_edge = "top";
      tab_bar_style = "powerline";
      # Font, colours, and opacity all come from Stylix
      # (modules/nixos/style.nix). Don't set them here.
    };
    keybindings = {
      "ctrl+shift+enter" = "launch --cwd=current";
      "ctrl+shift+z" = "toggle_layout stack";

      # HINTS — the mouse-free killer feature. These overlay every match on
      # screen with a letter; press it to act. No pointer involved.
      "ctrl+shift+p>u" = "kitten hints --type url --program default";
      "ctrl+shift+p>f" = "kitten hints --type path --program -";
      "ctrl+shift+p>l" = "kitten hints --type line --program -";
      "ctrl+shift+p>h" = "kitten hints --type hash --program -";
      "ctrl+shift+p>w" = "kitten hints --type word --program -";

      # Type into every split at once — handy when driving several compute
      # nodes in parallel.
      "ctrl+shift+b" = "launch --allow-remote-control kitten broadcast";
    };

    extraConfig = ''
      # Scrollback into Neovim: browse and yank terminal history with vim
      # motions. Requires kitty-scrollback.nvim (see the nvim plugin file).
      allow_remote_control socket-only
      listen_on unix:/tmp/kitty
      action_alias kitty_scrollback_nvim kitten $HOME/.local/share/nvim/lazy/kitty-scrollback.nvim/python/kitty_scrollback_nvim.py
      map ctrl+shift+g kitty_scrollback_nvim
      map ctrl+shift+h kitty_scrollback_nvim --config ksb_builtin_last_cmd_output
    '';
  };

  # ---- multiplexer: zellij ----------------------------------------------
  # Discoverable — it shows you its own keybindings, which makes it much
  # gentler than tmux to start with. tmux is still installed (ssh.nix) because
  # it's what's already on the TASK nodes, and the multiplexer that matters
  # most is the one running on the *server*. kitty has native splits too, but
  # those don't survive a dropped connection.
  programs.zellij = {
    enable = true;
    enableFishIntegration = false; # don't auto-start; you'll want plain shells
    settings = {
      default_shell = "fish";
      copy_command = "wl-copy";
      pane_frames = false;
    };
  };

  # ---- PDF: zathura ------------------------------------------------------
  # Vim keys, and it speaks SyncTeX — with `latexmk -pvc` you get a live
  # preview that jumps between the rendered PDF and the source in Neovim.
  # Okular stays installed (packages.nix) for annotating.
  programs.zathura = {
    enable = true;
    options = {
      selection-clipboard = "clipboard";
      adjust-open = "best-fit";
      recolor = true; # dark mode for papers; the colours come from Stylix
      synctex = true;
      synctex-editor-command = "nvim --headless -c \"VimtexInverseSearch %{line} '%{input}'\"";
    };
  };

  # ---- file manager: yazi ------------------------------------------------
  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
    settings.mgr = {
      show_hidden = false;
      sort_by = "natural";
      sort_dir_first = true;
    };
  };

  # ---- mail: aerc --------------------------------------------------------
  # Enabled but unconfigured on purpose. Thunderbird stays as your daily
  # driver (packages.nix) — run `aerc` and let its setup wizard walk you
  # through adding an account when you're ready to try it. Then fill this in.
  programs.aerc = {
    enable = true;
    extraConfig = {
      general.unsafe-accounts-conf = false;
      ui = {
        threading-enabled = true;
        sidebar-width = 22;
      };
      viewer.pager = "less -R";
    };
    # extraAccounts = { ... };   # -> credentials belong in sops, not here
  };

  # ---- Neovim ------------------------------------------------------------
  # Deliberately NOT using programs.neovim: that module wants to generate
  # init.lua, which would collide with the dotfiles symlink and would make
  # your config unusable on the TASK nodes. Neovim itself is installed in
  # base.nix; the config comes from dotfiles/nvim/ as plain Lua.
  #
  # Bootstrap:
  #   git clone https://github.com/nvim-lua/kickstart.nvim dotfiles/nvim
  #   rm -rf dotfiles/nvim/.git      # you own it now
  #
  # Then add to dotfiles/nvim/lua/custom/plugins/claude.lua:
  #   return {
  #     { "coder/claudecode.nvim",
  #       dependencies = { "folke/snacks.nvim" },
  #       config = true,
  #       keys = {
  #         { "<leader>ac", "<cmd>ClaudeCode<cr>",     desc = "Claude Code" },
  #         { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send selection" },
  #         { "<leader>ad", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
  #       },
  #     },
  #   }
}
