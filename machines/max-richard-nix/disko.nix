{ ... }:
let
  # Replace this after booting the Clan installer ISO and running:
  #   lsblk --output NAME,ID-LINK,FSTYPE,SIZE,MODEL,SERIAL,MOUNTPOINT
  installDisk = "/dev/disk/by-id/ata-ASint_AS606_512GB_606512GHSMT25C170752";
in
{
  disko.devices = {
    disk.main = {
      device = installDisk;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1M";
            type = "EF02";
            priority = 1;
          };

          ESP = {
            size = "500M";
            type = "EF00";
            priority = 2;
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
              extraArgs = [ "-n" "ESP" ];
            };
          };

          root = {
            size = "100%";
            priority = 3;
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              extraArgs = [ "-L" "nixos" ];
            };
          };
        };
      };
    };
  };
}
