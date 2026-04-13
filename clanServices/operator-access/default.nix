{
  directory,
  ...
}:
let
  trustedCAPath = "ssh/trusted-user-ca-keys.pub";
  trustedCAPubkey = builtins.readFile (directory + "/vars/shared/openssh-ca/id_ed25519.pub/value");
in
{
  _class = "clan.service";
  manifest.name = "operator-access";
  manifest.description = "Trusts the shared operator SSH CA for admin logins";
  manifest.categories = [
    "Security"
    "System"
  ];
  manifest.readme = builtins.readFile ./README.md;

  roles.server = {
    description = "Installs the trusted SSH user CA for operator logins.";

    perInstance = { ... }: {
      nixosModule = {
        environment.etc."${trustedCAPath}".text = trustedCAPubkey;
        services.openssh.settings.TrustedUserCAKeys = "/etc/${trustedCAPath}";
      };
    };
  };
}
