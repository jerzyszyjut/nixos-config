{ lib, buildGoModule, fetchFromGitHub, makeWrapper, tmux, git, gh }:

# claude-squad (`cs`) — runs several Claude Code sessions side by side, each in
# its own tmux session and git worktree. Not in nixpkgs, hence packaged here.
# It shells out to tmux, git and gh, so the wrapper puts them on PATH.
buildGoModule rec {
  pname = "claude-squad";
  version = "1.0.20";

  src = fetchFromGitHub {
    owner = "smtg-ai";
    repo = "claude-squad";
    rev = "v${version}";
    hash = "sha256-VyZ6nU84pL4RPXDZDVGCcOh8FwId1XokImdI/i7uw7Y=";
  };

  vendorHash = "sha256-0EFCao5l9BNX6zdHVziV9ZwJX9v+BNu+e3tcFtYrDJ4=";

  # The tests start tmux sessions and git repos; not in the sandbox.
  doCheck = false;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    mv $out/bin/claude-squad $out/bin/cs
    wrapProgram $out/bin/cs --prefix PATH : ${lib.makeBinPath [ tmux git gh ]}
  '';

  meta = {
    description = "Manage multiple Claude Code agents in tmux and git worktrees";
    homepage = "https://github.com/smtg-ai/claude-squad";
    license = lib.licenses.agpl3Only;
    mainProgram = "cs";
  };
}
