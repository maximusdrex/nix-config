let
  recipients = import ../lib/operator-age-recipients.nix;
in
builtins.concatStringsSep "\n" recipients + "\n"
