{ lib, pkgs, config, ... }:

let
  cfg = config.services.gitDeploy;
  runMode =
    if cfg.buildAll then "build-realize"
    else if cfg.validateMode == "dry-run" then "validate-dry-run"
    else "validate-eval";

  deployScript = pkgs.writeShellApplication {
    name = "nix-deploy-run";
    runtimeInputs = [
      pkgs.git
      pkgs.jq
      pkgs.nixVersions.stable
      pkgs.coreutils
      pkgs.openssh
      pkgs.git-crypt
    ];
    text = ''
      set -euo pipefail
      umask 0022

      RUN_ID="$(date +%Y%m%d-%H%M%S)"
      MODE="${runMode}"
      REPORT_FILE="${cfg.report.file}"

      BRANCH="''${1:-${cfg.branch}}"
      REPO="${cfg.repoUrl}"
      WORK="${cfg.workTree}"
      KEY_FILE="${cfg.gitCrypt.keyFilePath}"
      SSH_KEY=""
      ${lib.optionalString (cfg.sshKeyPath != null) ''SSH_KEY="${cfg.sshKeyPath}"''}

      COMMIT="unknown"
      FAILURE_COUNT=0
      declare -a RESULTS_JSON=()

      add_result() {
        local status="$1"
        local host="$2"

        RESULTS_JSON+=("$(jq -nc --arg status "$status" --arg host "$host" '{status:$status, host:$host}')")
      }

      write_summary() {
        local exit_code="$1"
        local timestamp
        timestamp="$(date -Is)"

        local overall_status="OK"
        if [ "''${exit_code}" -ne 0 ] || [ "''${FAILURE_COUNT}" -gt 0 ]; then
          overall_status="ERROR"
        fi

        local results_payload="[]"
        if [ "''${#RESULTS_JSON[@]}" -gt 0 ]; then
          results_payload="$(printf '%s\n' "''${RESULTS_JSON[@]}" | jq -s '.')"
        fi

        local report_dir
        report_dir="$(dirname "''${REPORT_FILE}")"
        mkdir -p "''${report_dir}"

        jq -n \
          --arg run_id "''${RUN_ID}" \
          --arg timestamp "''${timestamp}" \
          --arg branch "''${BRANCH}" \
          --arg commit "''${COMMIT}" \
          --arg mode "''${MODE}" \
          --argjson results "''${results_payload}" \
          '{run_id:$run_id, timestamp:$timestamp, branch:$branch, commit:$commit, mode:$mode, results:[ $results ]}' \
          > "''${REPORT_FILE}"

        if [ -n "''${HOME_SITE_DEPLOY_REPORT_PATH:-}" ]; then
          local telemetry_dir
          telemetry_dir="$(dirname "''${HOME_SITE_DEPLOY_REPORT_PATH}")"
          mkdir -p "''${telemetry_dir}"
          install -m 0644 "''${REPORT_FILE}" "''${HOME_SITE_DEPLOY_REPORT_PATH}"
        fi

        echo "[deploy] summary -> ''${REPORT_FILE} (''${overall_status})"
      }

      trap 'write_summary $?' EXIT
  
      echo "[deploy] start $(date -Is) branch=$BRANCH repo=$REPO"
      mkdir -p "$WORK"
  
      # Use provided SSH key explicitly (avoid relying on ssh_config includes)
      if [ -n "''${SSH_KEY}" ]; then
        export GIT_SSH_COMMAND="ssh -i ''${SSH_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
      else
        export GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new'
      fi
  
      if [ ! -d "$WORK/.git" ]; then
        git -C "$WORK" init
        git -C "$WORK" remote add origin "$REPO"
      fi
  
      git -C "$WORK" fetch --prune origin
      git -C "$WORK" checkout -qf "origin/$BRANCH"
      git -C "$WORK" reset --hard "origin/$BRANCH"

      COMMIT="$(git -C "$WORK" rev-parse HEAD || echo unknown)"
  
      # ----- git-crypt unlock (key-file mode, no GPG) -----
      ${lib.optionalString cfg.gitCrypt.enable ''
      if [ -n "''${KEY_FILE:-}" ] && [ -r "''${KEY_FILE}" ]; then
        echo "[deploy] unlocking repo with git-crypt key-file…"
        ( cd "$WORK" && git-crypt unlock "''${KEY_FILE}" )
      else
        echo "[deploy] WARNING: git-crypt key file missing or unreadable: ''${KEY_FILE}" >&2
      fi
      ''}
  
      echo "[deploy] nix flake check (eval only)…"
      nix --extra-experimental-features 'nix-command flakes' flake check "$WORK" --no-build || true
  
      echo "[deploy] enumerating nixosConfigurations…"
      mapfile -t HOSTS < <(nix --extra-experimental-features 'nix-command flakes' \
        eval --json "$WORK#nixosConfigurations" --apply builtins.attrNames | jq -r '.[]')
      echo "[deploy] found: ''${HOSTS[*]}"
  
      ${if cfg.buildAll then ''
        echo "[deploy] building every host (realize)…"
        for h in "''${HOSTS[@]}"; do
          echo "[deploy]   build $h"
          if nix --extra-experimental-features 'nix-command flakes' \
            build --print-out-paths "$WORK#nixosConfigurations.\"$h\".config.system.build.toplevel" >/dev/null; then
            add_result "OK" "$h"
          else
            FAILURE_COUNT=$((FAILURE_COUNT + 1))
            add_result "ERROR" "$h"
          fi
        done
      '' else if cfg.validateMode == "dry-run" then ''
        echo "[deploy] validating every host (dry-run, no outputs)…"
        for h in "''${HOSTS[@]}"; do
          echo "[deploy]   check $h"
          if nix --extra-experimental-features 'nix-command flakes' \
            build --no-link --dry-run "$WORK#nixosConfigurations.\"$h\".config.system.build.toplevel"; then
            add_result "OK" "$h"
          else
            FAILURE_COUNT=$((FAILURE_COUNT + 1))
            add_result "ERROR" "$h"
          fi
        done
      '' else ''
        echo "[deploy] eval-only validation of drvPaths…"
        for h in "''${HOSTS[@]}"; do
          if nix --extra-experimental-features 'nix-command flakes' \
            eval --raw "$WORK#nixosConfigurations.\"$h\".config.system.build.toplevel.drvPath" >/dev/null; then
            add_result "OK" "$h"
          else
            FAILURE_COUNT=$((FAILURE_COUNT + 1))
            add_result "ERROR" "$h"
          fi
        done
      ''}

      if [ "''${FAILURE_COUNT}" -gt 0 ]; then
        echo "[deploy] encountered ''${FAILURE_COUNT} failures; aborting"
        exit 1
      fi

      ${lib.optionalString cfg.switchSelf ''
        echo "[deploy] switching this VPS (${config.networking.hostName})…"
        /run/current-system/sw/bin/nixos-rebuild switch --flake "$WORK#${config.networking.hostName}"
        if systemctl is-active --quiet git-deploy-webhook.service; then
          systemctl try-restart git-deploy-webhook.service || true
        fi
      ''}
  
      echo "[deploy] done $(date -Is)"
    '';
  };


  # Tiny webhook server; reads a secret from a file in the *decrypted* work tree.
  webhookPy = pkgs.writeText "git-webhook.py" ''
    #!/usr/bin/env python3
    import hmac, hashlib, os
    from http.server import BaseHTTPRequestHandler, HTTPServer

    BRANCH = os.environ.get("WEBHOOK_BRANCH", "main")
    UNIT   = os.environ.get("WEBHOOK_UNIT", "nix-deploy@" + BRANCH + ".service")
    SECRET = os.environ.get("WEBHOOK_SECRET", "")  # optional fallback
    SECRET_FILE = os.environ.get("WEBHOOK_SECRET_FILE", "")

    def load_secret():
      if SECRET_FILE:
        try:
          with open(SECRET_FILE, "rb") as f:
            return f.read().strip()
        except Exception:
          return b""
      return SECRET.encode()

    def ok(w, code=200, body=b"OK"):
      w.send_response(code); w.end_headers(); w.wfile.write(body)

    def bad(w, code=403, body=b"FORBIDDEN"):
      ok(w, code, body)

    class H(BaseHTTPRequestHandler):
      def do_POST(self):
        length = int(self.headers.get('Content-Length','0') or 0)
        body = self.rfile.read(length) if length else b""
        secret = load_secret()

        # Generic shared header
        token = self.headers.get("X-Deploy-Token", "").encode()
        if secret and hmac.compare_digest(token, secret):
          os.system("systemctl start " + UNIT)
          return ok(self, 202, b"Triggered")

        # GitHub-style HMAC (harmless for other providers)
        sig = self.headers.get("X-Hub-Signature-256", "")
        if secret and sig.startswith("sha256="):
          mac = hmac.new(secret, body, hashlib.sha256).hexdigest()
          if hmac.compare_digest(sig.split("=",1)[1], mac):
            os.system("systemctl start " + UNIT)
            return ok(self, 202, b"Triggered")

        return bad(self)

      def log_message(self, *a): pass

    if __name__ == "__main__":
      addr = os.environ.get("WEBHOOK_ADDR","127.0.0.1")
      port = int(os.environ.get("WEBHOOK_PORT","9099"))
      HTTPServer((addr, port), H).serve_forever()
  '';
  telemetryReportPath =
    let
      teleCfg = lib.attrByPath [ "services" "homeSiteTelemetry" ] null config;
    in if teleCfg != null && teleCfg.enable && teleCfg.deployReport.enable then
      (if teleCfg.deployReport.sourceFile != null
       then teleCfg.deployReport.sourceFile
       else "${teleCfg.stateDir}/deploy-report.json")
    else null;
in
{
  options.services.gitDeploy = {
    enable  = lib.mkEnableOption "provider-agnostic pull→unlock→check→build-all→switch";
    repoUrl = lib.mkOption { type = lib.types.str; description = "git URL (ssh or https)"; };
    branch  = lib.mkOption { type = lib.types.str; default = "main"; };
    workTree = lib.mkOption { type = lib.types.str; default = "/var/lib/nix-deploy/work"; };

    # RUNTIME string path → pure evaluation (no /etc reads at eval time)
    sshKeyPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Filesystem path to SSH key at runtime (e.g. /run/secrets/deploy_key).";
    };

    gitCrypt = {
      enable = lib.mkOption { type = lib.types.bool; default = true; };
      keyFilePath = lib.mkOption {
        type = lib.types.str;
        default = "/run/secrets/git-crypt.key";
        description = "Runtime path to 'git-crypt export-key' output.";
      };
    };

    webhook = {
      enable = lib.mkOption { type = lib.types.bool; default = true; };
      address = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; };
      port    = lib.mkOption { type = lib.types.port; default = 9099; };
      secretFilePath = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/nix-deploy/work/secrets/deploy/webhook_secret.txt";
        description = "Path to the shared secret file inside the decrypted repo.";
      };
    };

    timer = {
      enable = lib.mkOption { type = lib.types.bool; default = true; };
      onCalendar = lib.mkOption { type = lib.types.str; default = "daily"; };
    };

    # Control how aggressive the run is
    buildAll = lib.mkOption {
      type = lib.types.bool;
      default = false;   # set false to avoid materializing closures
      description = "If true, realize (build) all nixosConfigurations; otherwise only validate.";
    };
    switchSelf = lib.mkOption {
      type = lib.types.bool;
      default = false;   # set false to skip nixos-rebuild switch on the VPS
      description = "If true, switch this VPS after a successful run.";
    };
    validateMode = lib.mkOption {
      type = lib.types.enum [ "dry-run" "eval" ];
      default = "dry-run";
      description = "Validation style when buildAll=false: dry-run build (no outputs) or eval-only.";
    };

    report = {
      enable = lib.mkEnableOption "POST the last deploy summary JSON to a URL after each run";
      file   = lib.mkOption {
        type = lib.types.str;
        default = "/var/log/nix-deploy/last.json";
        description = "Path to the last deploy summary JSON.";
      };
      url    = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Destination endpoint (e.g. https://maxschaefer.me/api/deploy/report).";
      };
      extraHeaders = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "X-Deploy-Token=@/var/lib/nix-deploy/secrets/deploy_api_token" ];
        description = ''
          Extra curl -H headers. Use @file to read values from files, e.g.
          "X-Deploy-Token: $(cat /path/to/secret)" becomes "X-Deploy-Token=@/path/to/secret".
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.ssh.askPassword = false;

    # Point the ssh client at your runtime key (kept as a string => pure eval)
    environment.etc."ssh/ssh_config.d/99-gitdeploy.conf".text =
      lib.optionalString (cfg.sshKeyPath != null) ''
        Host *
          IdentityFile ${cfg.sshKeyPath}
          IdentitiesOnly yes
      '';

    # Working dir (owned by root)
    systemd.tmpfiles.rules =
      let
        # Pure string-based dirname (no path coercion)
        dirOf = s: lib.removeSuffix "/${lib.last (lib.splitString "/" s)}" s;

        secretDirs = lib.unique (
          lib.optional (cfg.sshKeyPath != null) (dirOf cfg.sshKeyPath)
          ++ [ (dirOf cfg.gitCrypt.keyFilePath) ]
        );
      in
        (map (d: "d ${d} 0700 root root - -") secretDirs)
        ++ [ "d ${cfg.workTree} 0755 root root - -" ];

    # Templated deploy service → systemctl start nix-deploy@main
    systemd.services."nix-deploy@" = {
      description = "Build all flakes and switch this VPS (branch: %i)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${deployScript}/bin/nix-deploy-run %i";
        ExecStartPost = [
          "${pkgs.curl}/bin/curl -H Content-Type:application/json -d @/var/log/nix-deploy/last.json https://maxschaefer.me/api/deploy/report"
        ];
        WorkingDirectory = cfg.workTree;
        Environment =
          lib.optionals (telemetryReportPath != null)
            [ "HOME_SITE_DEPLOY_REPORT_PATH=${telemetryReportPath}" ];
      };
    };

    # Daily timer (safety net)
    systemd.timers."nix-deploy@${cfg.branch}" = lib.mkIf cfg.timer.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnCalendar = cfg.timer.onCalendar; Persistent = true; };
    };
    systemd.services."nix-deploy@${cfg.branch}" = lib.mkIf cfg.timer.enable {
      description = "Scheduled deploy (pull/unlock/check/build/switch)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${deployScript}/bin/nix-deploy-run ${cfg.branch}";
        ExecStartPost = [
          "${pkgs.curl}/bin/curl -H Content-Type:application/json -d @/var/log/nix-deploy/last.json https://maxschaefer.me/api/deploy/report"
        ];
        Environment =
          lib.optionals (telemetryReportPath != null)
            [ "HOME_SITE_DEPLOY_REPORT_PATH=${telemetryReportPath}" ];
      };
    };

    # Webhook (reads secret from the decrypted repo)
    systemd.services.git-deploy-webhook = lib.mkIf cfg.webhook.enable {
      description = "Git deploy webhook listener (file-based secret in repo)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        User = "root";
        Environment = [
          "WEBHOOK_ADDR=${cfg.webhook.address}"
          "WEBHOOK_PORT=${toString cfg.webhook.port}"
          "WEBHOOK_BRANCH=${cfg.branch}"
          "WEBHOOK_UNIT=nix-deploy@${cfg.branch}.service"
          "WEBHOOK_SECRET_FILE=${cfg.webhook.secretFilePath}"
        ];
        ExecStart = "${pkgs.python3}/bin/python3 ${webhookPy}";
        Restart = "always";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
