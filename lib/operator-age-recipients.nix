let
  usersDir = ../sops/users;
  entries = builtins.readDir usersDir;
  userNames = builtins.filter (name: entries.${name} == "directory") (builtins.attrNames entries);
  keyFiles = builtins.filter builtins.pathExists (builtins.map (user: usersDir + "/${user}/key.json") userNames);
  keys = builtins.concatLists (builtins.map (path: builtins.fromJSON (builtins.readFile path)) keyFiles);
  ageRecipients = builtins.map
    (entry: entry.publickey)
    (builtins.filter (entry: (entry.type or null) == "age" && entry ? publickey) keys);
in
builtins.attrNames (
  builtins.listToAttrs (
    builtins.map (recipient: {
      name = recipient;
      value = true;
    }) ageRecipients
  )
)
