{
  description = "jerzy's machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # One color scheme + one font, applied to every app on the system.
    stylix = {
      url = "github:nix-community/stylix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, home-manager, nixos-hardware, stylix, sops-nix, ... }:
    let
      system = "x86_64-linux";

      # Anything you want newer than stable is reachable as pkgs.unstable.<name>.
      overlayUnstable = final: prev: {
        unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      };
    in
    {
      nixosConfigurations.thinkpad = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          { nixpkgs.overlays = [ overlayUnstable ]; }

          # ThinkPad E14 Gen 6 (Intel), machine type 21M7 — exact match exists.
          nixos-hardware.nixosModules.lenovo-thinkpad-e14-intel-gen6

          stylix.nixosModules.stylix
          sops-nix.nixosModules.sops

          ./hosts/thinkpad
          ./modules/nixos/base.nix
          ./modules/nixos/style.nix
          ./modules/nixos/desktop.nix
          ./modules/nixos/dev.nix
          ./modules/nixos/net.nix
          ./modules/nixos/secrets.nix

          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.jerzy = import ./home/jerzy;
              backupFileExtension = "hm-bak";
            };
          }
        ];
      };
    };
}
