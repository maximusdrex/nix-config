{ config, lib, pkgs, ... }:

let
  cfg = config.security.unifiedAuth;
  fido2Cfg = config.security.unifiedAuth.fido2;
  sshAgentSudoCfg = config.security.unifiedAuth.sshAgentSudo;
in
{
  options.security.unifiedAuth.fido2 = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Enable FIDO2 PAM authentication";
    };

    pamServices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "login" "sudo" "polkit-1" ];
      description = "PAM services to enable FIDO2 authentication for";
    };

    requireTouch = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Require touch confirmation for FIDO2 authentication";
    };

    requirePin = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Require PIN for FIDO2 authentication";
    };

    fallbackPassword = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow password fallback if FIDO2 fails";
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Emit verbose pam_u2f logging (via journald) for troubleshooting authentication failures.";
    };

    enableOptionalAuth = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable optional FIDO2 authentication when not enforcing hardware keys";
    };

    credentialPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/fido2-credentials";
      description = "Path to store FIDO2 credentials";
    };

    expandCredentialPath = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Expand %u/%h tokens in credentialPath so per-user files like /etc/fido2-credentials/%u resolve correctly.";
    };

    sshIntegration = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Integrate FIDO2 authentication with OpenSSH when the service is enabled.";
      };

      requirePam = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enforceHardwareKeys;
        description = "Require a keyboard-interactive PAM challenge backed by FIDO2 after public key authentication.";
      };

      authenticationMethods = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "publickey,keyboard-interactive:pam" ];
        description = "AuthenticationMethods entries to enforce when FIDO-backed keyboard-interactive auth is required.";
        example = [ "publickey,keyboard-interactive:pam" "publickey,keyboard-interactive" ];
      };
    };
  };

  options.security.unifiedAuth.sshAgentSudo = {
    enable = lib.mkEnableOption "forwarded SSH agent sudo authentication using pam_ssh_agent_auth";

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "max" ];
      description = "Users allowed to satisfy sudo via their forwarded SSH agent.";
    };

    extraAuthorizedKeys = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = {};
      description = "Optional map of additional authorized keys per user for the forwarded-agent sudo flow.";
    };

    authorizedKeysDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/security/authorized_keys.d";
      description = "Directory (under /etc) where pam_ssh_agent_auth will read authorized keys.";
    };

    control = lib.mkOption {
      type = lib.types.str;
      default = "sufficient";
      description = "PAM control flag to use for the ssh-agent sudo rule.";
    };

    pamOrder = lib.mkOption {
      type = lib.types.int;
      default = 9000;
      description = "Order value for the ssh-agent sudo PAM rule.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf fido2Cfg.enable (
      let
        sshIntegrationActive =
          config.services.openssh.enable && fido2Cfg.sshIntegration.enable;

        pamTargets = lib.unique (
          fido2Cfg.pamServices
          ++ lib.optionals sshIntegrationActive [ "sshd" ]
        );

        pamRuleEnabled = cfg.enforceHardwareKeys || fido2Cfg.enableOptionalAuth;

        pamControl =
          if fido2Cfg.fallbackPassword then
            "sufficient"
          else
            "required";

        pamRuleArgs =
          [ "authfile=${fido2Cfg.credentialPath}/%u" ]
          ++ lib.optionals fido2Cfg.requireTouch [ "cue" "touch=1" ]
          ++ lib.optionals fido2Cfg.requirePin [ "pin=1" ]
          ++ lib.optionals fido2Cfg.expandCredentialPath [ "expand" ]
          ++ lib.optionals fido2Cfg.debug [ "debug" ];

        pamRule = {
          order = 10000;
          control = pamControl;
          modulePath = "${pkgs.pam_u2f}/lib/security/pam_u2f.so";
          args = pamRuleArgs;
        };

        hasAuthMethods = fido2Cfg.sshIntegration.authenticationMethods != [];
        authMethodsValue = lib.concatStringsSep " " fido2Cfg.sshIntegration.authenticationMethods;
      in
      {
        # Install required packages and helper scripts
        environment.systemPackages = with pkgs; [
          libfido2
          pam_u2f
        ] ++ [
          (pkgs.writeShellScriptBin "fido2-register" ''
            set -euo pipefail

            USER="''${1:-$USER}"
            CRED_FILE="${fido2Cfg.credentialPath}/$USER"

            if [ "$EUID" -ne 0 ] && [ "$USER" != "$USER" ]; then
              echo "Run as root or specify your own username"
              exit 1
            fi

            echo "Registering FIDO2 device for user: $USER"
            echo "Touch your security key when it blinks..."

            mkdir -p "${fido2Cfg.credentialPath}"

            ${pkgs.libfido2}/bin/fido2-token -L
            echo
            read -p "Enter device path (or press enter for auto): " DEVICE
            DEVICE="''${DEVICE:-auto}"

            if [ "$DEVICE" = "auto" ]; then
              ${pkgs.pam_u2f}/bin/pamu2fcfg -u "$USER" > "$CRED_FILE"
            else
              ${pkgs.pam_u2f}/bin/pamu2fcfg -u "$USER" -d "$DEVICE" > "$CRED_FILE"
            fi

            chmod 644 "$CRED_FILE"
            echo "FIDO2 credential registered for $USER"
            echo "Credential stored in: $CRED_FILE"
          '')

          (pkgs.writeShellScriptBin "fido2-test" ''
            set -euo pipefail

            USER="''${1:-$USER}"
            CRED_FILE="${fido2Cfg.credentialPath}/$USER"

            if [ ! -f "$CRED_FILE" ]; then
              echo "No FIDO2 credential found for $USER"
              echo "Run: fido2-register $USER"
              exit 1
            fi

            echo "Testing FIDO2 authentication for $USER"
            echo "Touch your security key when it blinks..."

            ${pkgs.pam_u2f}/bin/pamu2fcfg -u "$USER" -v
          '')
        ];

        # Create credentials directory
        systemd.tmpfiles.rules = [
          "d ${fido2Cfg.credentialPath} 0755 root root - -"
        ];

        # Environment for FIDO2 tools
        environment.sessionVariables = {
          FIDO_DEBUG = lib.mkIf (lib.elem "debug" config.boot.kernelParams) "1";
        };

        # Udev rules for FIDO2 devices
        services.udev.extraRules = ''
          # Allow users to access FIDO2 devices
          SUBSYSTEM=="hidraw", ATTRS{idVendor}=="2581", MODE="0664", GROUP="users", TAG+="uaccess"
          SUBSYSTEM=="usb", ATTRS{idVendor}=="2581", MODE="0664", GROUP="users", TAG+="uaccess"

          # General FIDO2 device rules
          KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idUsage}=="3f", ATTRS{idUsagePage}=="f1d0", MODE="0664", GROUP="users", TAG+="uaccess"
        '';

        # Systemd service for credential backup (when we have the keys)
        systemd.services.fido2-credential-backup = {
          description = "Backup FIDO2 credentials to encrypted storage";
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            ExecStart = "${pkgs.writeShellScript "backup-fido2-creds" ''
              set -euo pipefail

              BACKUP_DIR="/var/backups/fido2-credentials"
              CRED_DIR="${fido2Cfg.credentialPath}"

              mkdir -p "$BACKUP_DIR"

              if [ -d "$CRED_DIR" ] && [ -n "$(ls -A "$CRED_DIR" 2>/dev/null)" ]; then
                tar -czf "$BACKUP_DIR/fido2-credentials-$(date +%Y%m%d).tar.gz" -C "$CRED_DIR" .

                # Keep only last 30 days of backups
                find "$BACKUP_DIR" -name "fido2-credentials-*.tar.gz" -mtime +30 -delete

                echo "FIDO2 credentials backed up to $BACKUP_DIR"
              else
                echo "No FIDO2 credentials to backup"
              fi
            ''}";
          };
        };

        # Daily backup timer
        systemd.timers.fido2-credential-backup = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
          };
        };

        # Configure PAM services for hardware-backed auth
        security.pam.services =
          lib.mkIf (pamRuleEnabled && pamTargets != [])
            (lib.genAttrs pamTargets (_: {
              rules.auth.fido2 = pamRule;
            }));

        # SSH FIDO2 support (touch+verification + MFA enforcement)
        services.openssh.settings =
          lib.mkIf config.services.openssh.enable (
            (lib.optionalAttrs cfg.enforceHardwareKeys {
              PubkeyAuthOptions = "touch-required,verify-required";
            })
            // (lib.optionalAttrs (sshIntegrationActive && fido2Cfg.sshIntegration.requirePam) (
              {
                KbdInteractiveAuthentication = true;
                ChallengeResponseAuthentication = true;
              }
              // (lib.optionalAttrs (sshIntegrationActive && fido2Cfg.sshIntegration.requirePam && hasAuthMethods) {
                AuthenticationMethods = authMethodsValue;
              })
            ))
            // (lib.optionalAttrs sshIntegrationActive {
              UsePAM = true;
            })
          );
      }
    ))

    (lib.mkIf sshAgentSudoCfg.enable (
      let
        dirIsEtc = lib.hasPrefix "/etc/" sshAgentSudoCfg.authorizedKeysDir;
        authorizedDirRel =
          if dirIsEtc then lib.removePrefix "/etc/" sshAgentSudoCfg.authorizedKeysDir
          else sshAgentSudoCfg.authorizedKeysDir;

        userCfg = user: lib.attrByPath [ user ] null config.users.users;

        baseKeys = user:
          let u = userCfg user;
          in if u != null && u ? openssh && u.openssh ? authorizedKeys && u.openssh.authorizedKeys ? keys
            then u.openssh.authorizedKeys.keys
            else [];

        extraKeys = user: lib.attrByPath [ user ] [] sshAgentSudoCfg.extraAuthorizedKeys;
        effectiveKeys = user: lib.unique (baseKeys user ++ extraKeys user);

        usersWithKeys = lib.filter (user: (effectiveKeys user) != []) sshAgentSudoCfg.users;

        etcEntries =
          lib.listToAttrs (map (user: {
            name = "${authorizedDirRel}/${user}";
            value = {
              mode = "0644";
              user = "root";
              group = "root";
              text = lib.concatStringsSep "\n" (effectiveKeys user ++ [ "" ]);
            };
          }) usersWithKeys);
      in
      {
        assertions = [
          {
            assertion = dirIsEtc;
            message = "security.unifiedAuth.sshAgentSudo.authorizedKeysDir must live under /etc";
          }
        ];

        environment.etc = etcEntries;

        systemd.tmpfiles.rules = [
          "d ${sshAgentSudoCfg.authorizedKeysDir} 0755 root root - -"
        ];

        security.pam.services.sudo.rules.auth.forwarded-ssh-agent = {
          order = sshAgentSudoCfg.pamOrder;
          control = sshAgentSudoCfg.control;
          modulePath = "${pkgs.pam_ssh_agent_auth}/lib/security/pam_ssh_agent_auth.so";
          args = [ "file=${sshAgentSudoCfg.authorizedKeysDir}/%u" ];
        };
      }
    ))
  ];
}
