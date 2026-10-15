{ lib, buildNpmPackage, fetchFromGitHub, makeWrapper, yt-dlp, ffmpeg }:

# yoinks — a TUI over yt-dlp: paste a link, pick a resolution or mp3, and the
# file lands in ~/Downloads. Not in nixpkgs, hence packaged here.
#
# Upstream fetches the standalone yt-dlp binary into ~/.yoinks/bin on first run
# and falls back to the npm `ffmpeg-static` binary. Neither belongs on NixOS:
# a downloaded ELF won't find its loader, and a pinned yt-dlp goes stale fast.
# Both are looked up on PATH first, so the wrapper puts the nixpkgs ones there
# and the download paths are never reached. --ignore-scripts also stops
# ffmpeg-static's postinstall from trying to download during the build.
buildNpmPackage {
  pname = "yoinks";
  version = "0.3.1-unstable-2026-07-16";

  src = fetchFromGitHub {
    owner = "pablostanley";
    repo = "yoinks";
    rev = "6f03720813c22f907d3fb9ba98567f2169446b82";
    hash = "sha256-dU3Rrk3rxh4bbR0YHzBbeY2h+B+0S5r55T6JvFmLEtE=";
  };

  npmDepsHash = "sha256-PhzO6pKzSO+q1GHes3TQ74X0+sEYEhlbvT9MRHg98fg=";
  npmFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/yoinks \
      --prefix PATH : ${lib.makeBinPath [ yt-dlp ffmpeg ]}
  '';

  meta = {
    description = "Download videos from YouTube, X, Instagram and 1800+ sites from the terminal";
    homepage = "https://github.com/pablostanley/yoinks";
    license = lib.licenses.mit;
    mainProgram = "yoinks";
  };
}
