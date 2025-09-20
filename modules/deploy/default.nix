{ lib, pkgs, config, ... }:
let
  cfg = config.services.gitDeploy;

  deployScript = pkgs.writeShellApplication {
    name = "nix-deploy-run";
    runtimeInputs = [ pkgs.git pkgs.jq pkgs.nixVersions.stable pkgs.coreutils ];
    text = ''
      set -euo pipefail
      umask 0022

      BRANCH="''${1:-${cfg.branch}}"
      REPO="${cfg.repoUrl}"
      WORK="${cfg.workTree}"

      echo "[deploy] start $(date -Is) branch=$BRANCH repo=$REPO"
      mkdir -p "$WORK"

      if [ ! -d "$WORK/.git" ]; then
        git -C "$WORK" init
        git -C "$WORK" remote add origin "$REPO"
      fi

      git -C "$WORK" fetch --prune origin
      git -C "$WORK" checkout -qf "origin/$BRANCH"
      git -C "$WORK" reset --hard "origin/$BRANCH"

      echo "[deploy] nix flake check…"
      nix --extra-experimental-features 'nix-command flakes' flake check "$WORK"

      echo "[deploy] enumerating nixosConfigurations…"
      mapfile -t HOSTS < <(nix --extra-experimental-features 'nix-command flakes' \
        eval --json "$WORK#nixosConfigurations" | jq -r 'keys[]')
      echo "[deploy] found: ''${HOSTS[*]}"

      echo "[deploy] building every host…"
      for h in "''${HOSTS[@]}"; do
        echo "[deploy]   build $h"
        nix --extra-experimental-features 'nix-command flakes' \
          build --print-out-paths "$WORK#nixosConfigurations.\"$h\".config.system.build.toplevel" >/dev/null
      done

      echo "[deploy] switching this VPS ($(hostname))…"
      nixos-rebuild switch --flake "$WORK#${config.networking.hostName}"

      if systemctl is-active --quiet git-deploy-webhook.service; then
        systemctl try-restart git-deploy-webhook.service || true
      fi

      echo "[deploy] done $(date -Is)"
    '';
  };

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

    def bad(w, code=403, body=b"FORBIDDEN"): ok(w, code, body)

    class H(BaseHTTPRequestHandler):
      def do_POST(self):
        length = int(self.headers.get('Content-Length','0') or 0)
        body = self.rfile.read(length) if length else b""
        secret = load_secret()

        # Provider-agnostic shared header
        token = self.headers.get("X-Deploy-Token", "").encode()
        if secret and hmac.compare_digest(token, secret):
          os.system("systemctl start " + UNIT)
          return ok(self, 202, b"Triggered")

        # GitHub-style HMAC (harmless if other providers send it too)
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

in
{
  options.services.gitDeploy = {
    enable  = lib.mkEnableOption "provider-agnostic pull→check→build-all→switch";
    repoUrl = lib.mkOption { type = lib.types.str; description = "git URL (ssh or https)"; };
    branch  = lib.mkOption { type = lib.types.str; default = "main"; };
    workTree = lib.mkOption { type = lib.types.str; default = "/var/lib/nix-deploy/work"; };

    sshKeyPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str; default = null;
      description = "Optional private key to pull a private repo via SSH.";
    };

    webhook = {
      enable = lib.mkOption { type = lib.types.bool; default = true; };
      address = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; };
      port    = lib.mkOption { type = lib.types.port; default = 9099; };
      # Point to the secret **inside the repo** (already decrypted by your setup)
      secretFilePath = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/nix-deploy/work/secrets/deploy/webhook_secret.txt";
        description = "Path to shared-secret file within the work tree.";
      };
    };

    timer = {
      enable = lib.mkOption { type = lib.types.bool; default = true; };
      onCalendar = lib.mkOption { type = lib.types.str; default = "daily"; };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.ssh.askPassword = false;

    # Use a deploy key for pulling (if needed)
    environment.etc."ssh/ssh_config.d/99-gitdeploy.conf".text =
      lib.optionalString (cfg.sshKeyPath != null) ''
        Host *
          IdentityFile ${cfg.sshKeyPath}
          IdentitiesOnly yes
      '';

    systemd.tmpfiles.rules = [ "d ${cfg.workTree} 0755 root root - -" ];

    # Templated service → systemctl start nix-deploy@main
    systemd.services."nix-deploy@" = {
      description = "Build all flakes and switch this VPS (branch: %i)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${deployScript}/bin/nix-deploy-run %i";
        WorkingDirectory = cfg.workTree;
      };
    };

    # Timer fallback
    systemd.timers."nix-deploy@${cfg.branch}" = lib.mkIf cfg.timer.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnCalendar = cfg.timer.onCalendar; Persistent = true; };
    };
    systemd.services."nix-deploy@${cfg.branch}" = lib.mkIf cfg.timer.enable {
      description = "Scheduled deploy (pull/check/build/switch)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${deployScript}/bin/nix-deploy-run ${cfg.branch}";
      };
    };

    # Webhook (reads secret from the repo path)
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

