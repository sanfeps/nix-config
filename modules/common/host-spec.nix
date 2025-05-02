# Specifications For Differentiating Hosts
{
  lib,
  ...
}:
{
  options.hostSpec = {
    # Data variables that don't dictate configuration settings
    username = lib.mkOption {
      type = lib.types.str;
      description = "The username of the host";
    };
    email = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = "The email of the user";
    };
    domain = lib.mkOption {
      type = lib.types.str;
      description = "The domain of the host";
    };
    persistFolder = lib.mkOption {
      type = lib.types.str;
      description = "The folder to persist data";
      default = "/persist";
    };
  };
}
