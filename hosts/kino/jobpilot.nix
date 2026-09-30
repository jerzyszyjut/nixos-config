{ config, lib, pkgs, inputs, ... }:

# JobPilot (github:jerzyszyjut/jobpilot): collects job offers, scores them
# against a CV, drafts documents. Seven podman containers from the project's
# own NixOS module; this file is only what is specific to running it here.
{
  imports = [ inputs.jobpilot.nixosModules.default ];

  services.jobpilot = {
    enable = true;

    # The images are built ON kino from a checkout, not pulled: the project
    # has no release tag yet, so nothing is published on GHCR. The tag is the
    # commit they were built from. oci-containers only pulls an image that is
    # missing locally, so these are used as they are. To update:
    #   rsync the checkout to kino, `podman build --target app|browser -t
    #   ghcr.io/jerzyszyjut/jobpilot[-browser]:<rev> .`, bump the tag here.
    # Once the project tags releases and the GHCR packages are public, this
    # becomes a plain version string and the build step goes away.
    # e7a403c is on the local branch flaresolverr-browser-fetch (not pushed
    # as of 2026-09-30): browser-only hosts such as devjobs.at are fetched
    # through FlareSolverr. The NixOS module is unchanged, so the flake input
    # can stay on the older commit.
    imageTag = "e7a403c";

    # Secrets stay on the server, like the other services here: this
    # repository is public. Root-only file, created by hand; see
    # docs/04-deploy-nixos.md in the jobpilot repo for its contents.
    # The YAML profile lives beside it in /var/lib/jobpilot/config.
    environmentFile = "/var/lib/jobpilot/jobpilot.env";

    # FlareSolverr already runs for Prowlarr; the module opens its port on
    # the jobpilot bridge only.
    flaresolverr.url = "http://host.containers.internal:${toString config.services.flaresolverr.port}/v1";

    # Publishes the UI on https://kino.<tailnet>.ts.net and noVNC on :6080,
    # tailnet only. Needs HTTPS certificates enabled for the tailnet (admin
    # console → DNS); enabled 2026-09-30. noVNC has no password of its own,
    # and kino is shared with other tailnets — a known, accepted exposure;
    # 4.9 in the jobpilot deploy guide has the ACL that closes it.
    tailscaleServe = true;
  };
}
