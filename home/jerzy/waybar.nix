{ config, lib, pkgs, ... }:

let
  # Stylix exposes the active scheme here, so the bar follows automatically if
  # you change base16Scheme in modules/nixos/style.nix.
  #
  # If this attribute path ever errors, replace `c` with a literal set:
  #   c = { base00 = "#282828"; base01 = "#32302f"; base02 = "#45403d";
  #         base03 = "#5a524c"; base04 = "#928374"; base05 = "#d4be98";
  #         base08 = "#ea6962"; base09 = "#e78a4e"; base0A = "#d8a657";
  #         base0B = "#a9b665"; base0C = "#89b482"; base0D = "#7daea3";
  #         base0E = "#d3869b"; };
  c = config.lib.stylix.colors.withHashtag;
in
{
  # NOTE: this replaces the dotfiles/waybar symlink. Waybar config is
  # machine-specific and never needed on the TASK nodes, so managing it in Nix
  # buys us the Stylix colors for free — worth the tradeoff here.
  programs.waybar = {
    enable = true;
    systemd.enable = false; # Hyprland starts it via exec-once

    settings.main = {
      layer = "top";
      position = "top";
      height = 34;
      spacing = 0;
      margin-top = 6;
      margin-left = 8;
      margin-right = 8;

      modules-left = [ "hyprland/workspaces" "hyprland/submap" "hyprland/window" ];
      modules-center = [ "clock" ];
      modules-right = [
        "idle_inhibitor"
        "cpu"
        "memory"
        "temperature"
        "pulseaudio"
        "backlight"
        "network"
        "bluetooth"
        "battery"
        "tray"
      ];

      "hyprland/workspaces" = {
        format = "{name}";
        on-click = "activate";
        sort-by-number = true;
      };

      "hyprland/submap".format = "  {}";

      "hyprland/window" = {
        format = "{title}";
        max-length = 60;
        separate-outputs = true;
        rewrite = {
          "(.*) — Mozilla Firefox" = "󰈹  $1";
          "(.*) - NVIM" = "  $1";
          "kitty" = "  terminal";
        };
      };

      clock = {
        format = "  {:%H:%M}";
        format-alt = "  {:%a %d %b  %H:%M}";
        tooltip-format = "<tt><small>{calendar}</small></tt>";
        calendar = {
          mode = "month";
          weeks-pos = "left";
          format = {
            months = "<span color='${c.base0A}'><b>{}</b></span>";
            weekdays = "<span color='${c.base0D}'><b>{}</b></span>";
            today = "<span color='${c.base08}'><b>{}</b></span>";
          };
        };
      };

      idle_inhibitor = {
        format = "{icon}";
        format-icons = {
          activated = "󰅶";
          deactivated = "○";
        };
        tooltip-format-activated = "Idle inhibited — screen won't lock";
        tooltip-format-deactivated = "Idle normal";
      };

      cpu = {
        format = "  {usage}%";
        interval = 5;
        on-click = "kitty -e btop";
      };

      memory = {
        format = "  {percentage}%";
        tooltip-format = "{used:0.1f} GiB of {total:0.1f} GiB";
        interval = 5;
      };

      temperature = {
        critical-threshold = 85;
        format = "{icon} {temperatureC}°";
        format-icons = [ "" "" "" ];
        interval = 5;
      };

      pulseaudio = {
        format = "{icon}  {volume}%";
        format-muted = "󰝟  muted";
        format-icons.default = [ "" "" "" ];
        on-click = "pavucontrol";
        on-click-right = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        scroll-step = 5;
      };

      backlight = {
        format = "󰃠  {percent}%";
        scroll-step = 5;
      };

      network = {
        format-wifi = "  {essid}";
        format-ethernet = "󰈀  wired";
        format-disconnected = "󰤭  offline";
        tooltip-format-wifi = "{essid}  {signalStrength}%\n{ipaddr}";
        tooltip-format-ethernet = "{ifname}\n{ipaddr}";
        on-click = "kitty -e nmtui";
      };

      bluetooth = {
        format = "";
        format-disabled = "";
        format-connected = "  {num_connections}";
        tooltip-format-connected = "{device_enumerate}";
        on-click = "blueman-manager";
      };

      battery = {
        states = {
          warning = 25;
          critical = 12;
        };
        format = "{icon}  {capacity}%";
        format-charging = "󰂄  {capacity}%";
        format-plugged = "󰚥  {capacity}%";
        format-icons = [ "󰁺" "󰁼" "󰁾" "󰂀" "󰂂" "󰁹" ];
        tooltip-format = "{timeTo}  ({power:0.1f}W)";
      };

      tray = {
        icon-size = 16;
        spacing = 10;
      };
    };

    # Floating pill islands rather than one edge-to-edge slab. Reads as
    # deliberate without needing blur, which matters on your integrated GPU.
    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size: 13px;
        font-weight: 500;
        border: none;
        border-radius: 0;
        min-height: 0;
        padding: 0;
        margin: 0;
      }

      window#waybar {
        background: transparent;
      }

      /* every group gets its own rounded island */
      .modules-left, .modules-center, .modules-right {
        background: ${c.base01};
        border-radius: 10px;
        padding: 0 6px;
        border: 1px solid ${c.base02};
      }

      #workspaces button {
        color: ${c.base04};
        padding: 0 9px;
        margin: 4px 2px;
        border-radius: 7px;
        background: transparent;
        transition: background 120ms ease, color 120ms ease;
      }

      #workspaces button:hover {
        background: ${c.base02};
        color: ${c.base06};
      }

      #workspaces button.active {
        background: ${c.base0B};
        color: ${c.base00};
      }

      #workspaces button.urgent {
        background: ${c.base08};
        color: ${c.base00};
      }

      #window {
        color: ${c.base04};
        padding: 0 10px;
      }

      #submap {
        color: ${c.base0A};
        padding: 0 10px;
      }

      #clock {
        color: ${c.base0D};
        padding: 0 14px;
        font-weight: 500;
      }

      #cpu, #memory, #temperature, #pulseaudio, #backlight,
      #network, #bluetooth, #battery, #idle_inhibitor {
        color: ${c.base05};
        padding: 0 9px;
      }

      #cpu        { color: ${c.base0C}; }
      #memory     { color: ${c.base0E}; }
      #temperature{ color: ${c.base09}; }
      #pulseaudio { color: ${c.base0D}; }
      #backlight  { color: ${c.base0A}; }
      #network    { color: ${c.base0B}; }
      #bluetooth  { color: ${c.base0D}; }
      #battery    { color: ${c.base0B}; }

      #temperature.critical,
      #battery.critical {
        color: ${c.base08};
      }

      #battery.warning {
        color: ${c.base0A};
      }

      #idle_inhibitor.activated {
        color: ${c.base08};
      }

      #tray {
        padding: 0 8px;
      }

      #tray menu {
        background: ${c.base01};
        color: ${c.base05};
        border: 1px solid ${c.base02};
        border-radius: 8px;
      }

      tooltip {
        background: ${c.base00};
        border: 1px solid ${c.base02};
        border-radius: 8px;
      }

      tooltip label {
        color: ${c.base05};
        padding: 4px;
      }
    '';
  };

  # Stylix would otherwise generate its own waybar stylesheet and fight the one
  # above. The colors still come from Stylix via `c` — only the layout is ours.
  stylix.targets.waybar.enable = false;
}
