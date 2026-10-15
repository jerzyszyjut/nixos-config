# The whole disk of the old PC, wiped and laid out by nixos-anywhere.
#
# Same btrfs subvolumes as kino, on one disk instead of two: @media holds the
# torrents AND the library, so Radarr's hardlink import keeps working (a
# hardlink cannot cross a subvolume).
#
# Both a BIOS boot partition and an ESP: nobody here knows yet whether the
# PC boots UEFI or legacy BIOS, and with both GRUB (hosts/dom) boots either.
{
  disko.devices.disk.main = {
    type = "disk";
    # TODO(dom): check with `lsblk` on the installer before installing; an
    # NVMe disk is /dev/nvme0n1.
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          size = "1M";
          type = "EF02";
        };
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes = {
              "@" = {
                mountpoint = "/";
                mountOptions = [ "compress=zstd:1" "noatime" ];
              };
              "@home" = {
                mountpoint = "/home";
                mountOptions = [ "compress=zstd:1" "noatime" ];
              };
              "@nix" = {
                mountpoint = "/nix";
                mountOptions = [ "compress=zstd:1" "noatime" ];
              };
              # No compression: films are already compressed (see kino).
              "@media" = {
                mountpoint = "/var/lib/media";
                mountOptions = [ "noatime" ];
              };
            };
          };
        };
      };
    };
  };
}
