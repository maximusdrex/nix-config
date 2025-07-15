# This expression represents a list of SSH public keys my servers should authenticate for the 'max' user

# Read directory secrets/ssh/public

# Filter out all non-regular entries

# Convert set to list of keys

# map list with readFile to get contents

{ pkgs }:

(builtins.map (filename: builtins.readFile (../../secrets/ssh/public + ("/" + filename)))
  (builtins.attrNames
    (pkgs.lib.attrsets.filterAttrs (n: v: v == "regular")
      (builtins.readDir ../../secrets/ssh/public)
    )  
  )
)
