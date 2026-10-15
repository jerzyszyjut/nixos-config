# Placeholder so `dom` evaluates before the machine has been seen.
# nixos-anywhere --generate-hardware-config overwrites this file with the
# real one during the install (docs/DOM-INSTALL.md); commit that version.
{ lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ehci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" "kvm-amd" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
