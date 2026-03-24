All files in this directory either need to be empty and not tracked by git (e.g. wireguard private keys) or encrypted by git crypt.

PRIVATE KEYS SHOULD NOT BE UPLOADED ANYWHERE!! They need to be tracked by git (sadly) for flakes to build correctly, which means they will be moved to the nix store.
Because of this, the security model includes preventing any other users from accessing my machines AT ALL
