[
  {
    hostname = "max-hetzner-nix";
    ip = "10.20.0.1";
    pubkeyFile = "/public/max-hetzner-nix";
    server = builtins.true;
  }
  
  {
    hostname = "max-xps-modal"; 
    ip = "10.20.0.4";
    pubkeyFile = "/public/max-xps-modal";
    server = builtins.false;
  }

  {
    hostname = "max-g14-nix"; 
    ip = "10.20.0.5";
    pubkeyFile = "/public/max-g14-nix";
    server = builtins.false;
  }

  {
    hostname = "max-iphone"; 
    ip = "10.20.0.3";
    pubkeyFile = "/public/max-iphone";
    server = builtins.false;
  }
]
