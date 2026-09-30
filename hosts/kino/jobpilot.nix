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
    imageTag = "c5c6b26";

    # Secrets stay on the server, like the other services here: this
    # repository is public. Root-only file, created by hand; see
    # docs/04-deploy-nixos.md in the jobpilot repo for its contents.
    # The YAML profile lives beside it in /var/lib/jobpilot/config.
    environmentFile = "/var/lib/jobpilot/jobpilot.env";

    # FlareSolverr already runs for Prowlarr; the module opens its port on
    # the jobpilot bridge only.
    flaresolverr.url = "http://host.containers.internal:${toString config.services.flaresolverr.port}/v1";

    # Off until HTTPS certificates are enabled for the tailnet (admin
    # console → DNS). `tailscale serve --https` cannot start without them,
    # and a unit that fails on every boot fails every rebuild with it.
    # Also read 4.9 in the jobpilot deploy guide first: kino is shared with
    # other tailnets, and noVNC (:6080) has no password of its own.
    tailscaleServe = false;
  };
}
