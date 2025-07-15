[
  {
    hostname = "max-hetzner-nix";
    ip = "10.20.10.1";
    pubkeyFile = "/public/max-hetzner-nix";
    server = builtins.true;
  }
  
  {
    hostname = "max-xps-modal"; 
    ip = "10.20.10.4";
    pubkeyFile = "/public/max-xps-modal";
    server = builtins.false;
  }

  {
    hostname = "max-g14-nix"; 
    ip = "10.20.10.5";
    pubkeyFile = "/public/max-g14-nix";
    server = builtins.false;
  }
]
