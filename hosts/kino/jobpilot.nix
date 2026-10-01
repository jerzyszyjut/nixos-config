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
    #   rsync the checkout to kino, `podman build --format docker --target
    #   app|browser -t ghcr.io/jerzyszyjut/jobpilot[-browser]:<rev> .`, bump
    #   the tag here. `--format docker` matters: podman's default OCI format
    #   drops the images' HEALTHCHECK.
    # Once the project tags releases and the GHCR packages are public, this
    # becomes a plain version string and the build step goes away.
    # 18e3663 is the head of the branch document-revisions (2026-10-01),
    # built on flaresolverr-browser-fetch: documents can be regenerated with
    # notes, offers corrected by hand and letters signed. The earlier branch
    # fetches browser-only hosts through FlareSolverr and reads job ids from
    # behind StepStone's and XING's tracking links. It also changes the NixOS
    # module (worker stop signal); that arrives with the flake input once
    # it is merged.
    imageTag = "18e3663";

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
