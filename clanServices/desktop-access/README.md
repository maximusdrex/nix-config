`desktop-access` provides recoverable SSH client keys for desktop machines.

The service generates one dedicated `max@<machine>` Ed25519 keypair per desktop
client machine using Clan vars. On the client, activation installs the private
key as:

```text
/home/max/.ssh/id_clan_desktop
```

On server machines, the public keys for all desktop clients in the same service
instance are appended to `users.users.max.openssh.authorizedKeys.keys`.

This intentionally does not reuse Clan's OpenSSH host key. Host identity and
user login identity stay separate, while the login key remains recoverable after
a home directory loss.
