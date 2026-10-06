{ inputs, ... }:

# Opportunity radar (github:jerzyszyjut/opportunity-radar): finds funded
# internships, PhDs and scholarships, scores them with Claude, syncs them to
# Notion and mails a weekly digest. One-shot podman runs on systemd timers;
# this file is only what is specific to running it here.
{
  imports = [ inputs.opportunity-radar.nixosModules.default ];

  services.opportunity-radar = {
    enable = true;

    # Built ON kino from a checkout, like JobPilot; nothing is published. To
    # update: rsync the checkout to kino, `podman build --format docker -t
    # ghcr.io/jerzyszyjut/opportunity-radar:<rev> .`, bump the tag here.
    imageTag = "dfcadf8";

    # Root-only, created by hand: the Anthropic key and the Gmail app
    # password are the same ones JobPilot uses; plus the Notion token.
    # profile.yaml, sources.yaml and cv.md live beside it in config/.
    environmentFile = "/var/lib/opportunity-radar/radar.env";

    # Defaults: scan daily 07:30, web discovery Sunday 20:00, digest Monday 08:00.
  };
}
