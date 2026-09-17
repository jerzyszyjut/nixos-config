{ pkgs }:

# Zotero bundles an older Firefox/Gecko runtime that renders a black window
# under native Wayland (the global MOZ_ENABLE_WAYLAND=1 in default.nix is
# meant for real Firefox). Forcing it onto XWayland fixes it.
#
# Its own file because it is used from home/jerzy/work.nix, which is where the
# study tools live now.
pkgs.symlinkJoin {
  name = "zotero-xwayland";
  paths = [ pkgs.zotero ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/zotero --unset MOZ_ENABLE_WAYLAND
  '';
}
