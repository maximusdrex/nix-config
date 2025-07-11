# Max's NixOS Configuration

This repository is meant to generate Nix configurations for all hosts I manage.

## Directory Structure

```
.
├── common
│   ├── common.nix
│   ├── desktop
│   │   ├── default.nix
│   │   └── home.nix
│   └── server
│       ├── default.nix
│       └── home.nix
├── flake.lock
├── flake.nix
├── hosts
│   ├── g14
│   │   └── default.nix
│   └── xps
│       ├── default.nix
│       └── hardware-configuration.nix
├── modules
│   └── ...
│       └── default.nix
├── packages
│   ├── ...
│   │   └── default.nix
│   └── README.md
├── programs
│   ├── default.nix
│   ├── desktop
│   │   ├── default.nix
│   │   └── (...).nix
│   └── ...
│       └── default.nix
├── secrets (ENCRYPTED BY git-crypt)
│   ├── wireguard
│   │   ├── private
│   │   └── public
│   └── README.md
└── README.md
```

### Flake

`flake.nix` is the entrypoint for the build, all hosts need a configuration to be declared in `nixosConfigurations`. Those configurations need to declare a `system` type, and include at least two modules: the matching `hosts/host` and the home-manager config to use, which should be one of `common/desktop/home.nix` or `common/server/home.nix`. If a different configuration is necessary, create a `/hosts/x/home.nix` and use that instead. 

### Hosts

`hosts` contains all host-specific configuration. Each host should have its own directory `hosts/host` and a `default.nix` which must minimally import the generated `hardware-configuration.nix` and optionally use one of the `common/desktop` or `common/server` modules. If neither of the desktop or server configurations are relevant, the `common/common.nix` module contains a very minimal configuration.
The `hosts/host` module also needs to define the `networking.hostName` and `system.stateVersion` attributes.

### Common

`common` contains minimal modules for configuring either desktops or servers, and matching home-manager modules.

### Programs

`programs` contains modules for home-manager to setup any program or set of programs. The `programs` modules itself contains a very minimal package set. A desktop setup would likely want to import all of the modules declared in this directory.

### Packages

`packages` declares any custom derivations to be included in the system. These should be added using the nixpkgs.config.packageOverrides attribute. And added to the system packages where required.

### Modules

`modules` contains any custom program-specific modules which should be placed in their own directory and generally included by the host modules.

## Adding a system

Add the host configuration to flake.nix, start by copying an existing `nixosConfigurations` attribute and modifying the host module and home-manager module.

Add the `hosts/host` module, copy the generated `hardware-configuration.nix` into that directory. The minimal module definition follows:

```nix
{ config, pkgs, ... }:
{
  imports =
    [ 
       ./hardware-configuration.nix
       ../../common/desktop
    ];
  networking.hostName = "max-xps-modal"; # Define your hostname.

  # Warning!
  system.stateVersion = "24.11"; # Did you read the comment?
}
```

Build the system by running `sudo nixos-rebuild switch --flake <hostname-here>` in the /etc/nixos directory. If the hostname has been set already, you can just run `sudo nixos-rebuild switch`.

## Limitations

Currently only built for one `max` user. Can be added as an argument later if different user names become necessary.

Currently the git email is globally defined and can't be changed. This needs to depend on the machine.
