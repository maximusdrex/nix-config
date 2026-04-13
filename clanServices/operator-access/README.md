`operator-access` is a minimal Clan service that teaches machines to trust the
shared SSH user CA used for operator logins.

It is intentionally small:

- the service installs the CA public key on each target machine
- OpenSSH is configured to trust user certificates signed by that CA
- certificate issuance remains an explicit repo-side workflow
- static operator `authorized_keys` can remain as a temporary fallback while the cert flow is being tested

Example:

```nix
modules.operator-access = ./clanServices/operator-access;

inventory.instances.operator-access = {
  module = {
    input = "self";
    name = "operator-access";
  };

  roles.server.tags.all = { };
};
```

Once testing is complete, servers can rely on the CA alone and drop the static
operator `authorized_keys` fallback.
