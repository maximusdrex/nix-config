{ config, pkgs, self, ... }:

########################
#  Base Configuration
#  1. Boot settings (for all devices)
#       systemd-boot + (plymouth for desktops)
#  2. Kernel
#       all should use latest available
#  3. Networking
#       firewall
#       networkmanager for desktops
#       systemd-networkd for servers
#  4. General Linux Config
#  5. Nix
#  6. Other
########################

let
  sourceInfo = self.sourceInfo or {};
  configurationRevision =
    if sourceInfo ? rev then sourceInfo.rev
    else if sourceInfo ? dirtyRev then sourceInfo.dirtyRev
    else if self ? rev then self.rev
    else if self ? dirtyRev then self.dirtyRev
    else "";
in
{

  imports = [
    ../modules/home-site-telemetry
    ../modules/security
    # ../modules/wireguard
  ];
  ######################
  # 1. Bootloader
  ######################

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot = {
    consoleLogLevel = 3;
    initrd.verbose = false;
    kernelParams = [
      "quiet"
      "splash"
      "boot.shell_on_fail"
      "udev.log_priority=3"
      "rd.systemd.show_status=auto"
    ];
    loader.timeout = 0;
  };

  boot.initrd.systemd.enable = true;
  
  ######################
  # 2. Kernel
  ######################

  boot.kernelPackages = pkgs.linuxPackages_latest;

  ######################
  # 3. Networking
  ######################

  # TODO: move to desktop config (disable or customize firewall for server)
  networking.firewall = rec {
    allowedTCPPortRanges = [ { from = 1714; to = 1764; } ];
    allowedUDPPortRanges = allowedTCPPortRanges;
  };

  ######################
  # 4. General Linux Config
  ######################

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Very basic package set (home manager for the rest)
  # TODO: consider home manager managing vim
  environment.systemPackages = with pkgs; [
    git
    vim 
    wget
    git-crypt
  ];

  environment.variables.EDITOR = "vim";

  # TODO: this may also need desktop/server split
  virtualisation.containers.enable = true;
  virtualisation = {
    podman = {
      enable = true;

      # Create a `docker` alias for podman, to use it as a drop-in replacement
      dockerCompat = true;

      # Required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  ######################
  # 5. Nix Config
  ######################

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.configurationRevision = configurationRevision;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  ######################
  # 6. Security (Unified Authentication)
  ######################

  # Enable unified FIDO2/OpenPGP authentication (non-enforcing mode for now)
  security.unifiedAuth = {
    enable = true;
    enforceHardwareKeys = false;  # Set to true once security keys are set up

    # FIDO2 Configuration
    fido2 = {
      enable = true;
      pamServices = [ "login" "sudo" "polkit-1" ];
      requireTouch = true;
      requirePin = false;
      fallbackPassword = true;  # Keep password authentication available
    };

    # OpenPGP Configuration (per-device keys)
    openpgp = {
      enable = true;
      keyringPath = "/etc/gpg";
      deviceKeyId = config.networking.hostName;
      publicKeysPath = "secrets/pgp/public-keys";
      autoImport = true;
      cardReaderSupport = true;
    };

    # Device Provisioning
    deviceProvision = {
      enable = true;
      repoPath = "/var/lib/nix-deploy/work";
      generateSSHKeys = true;
      generateWireGuardKeys = true;
      keyRotationDays = 90;
      autoCommit = false;  # Manual commits for now
    };

    # Key Rotation (dry-run mode initially)
    keyRotation = {
      enable = true;
      dryRun = true;  # Set to false once workflow is tested
      backupPath = "/var/backups/key-rotation";
      repoPath = "/var/lib/nix-deploy/work";

      schedules = {
        monthly = {
          keyType = "all";
          intervalDays = 90;
          calendar = "monthly";
          hostPattern = "*";
        };
      };
    };
  };

  ######################
  # 7. Other
  ######################

  # services.homeSiteTelemetry = {
  #   enable = true;
  #   baseUrl = "https://maxschaefer.me";
  #   deviceStatus = {
  #    enable = true;
  #    repoPath = "/etc/nixos";
  #   };
  # };

}
