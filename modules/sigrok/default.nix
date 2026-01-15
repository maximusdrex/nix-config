{ lib, ... }:

let
  sigrokOverlay = final: prev: {
    libsigrok = prev.libsigrok.overrideAttrs (old: {
      version = "${old.version}-slogic-dev";
      src = prev.fetchFromGitHub {
        owner = "sipeed";
        repo = "libsigrok";
        rev = "0ce0720421b6bcc8e65a0c94c5b2883cbfe22d7e";
        hash = "sha256-4aqX+OX4bBsvvb7b1XHKqG6u1Ek3floXDfjr27usZwo=";
      };
    });
  };
in
{
  nixpkgs.overlays = lib.mkAfter [ sigrokOverlay ];
}
