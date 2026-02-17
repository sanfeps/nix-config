# Service to allow mounting NAS storage folders using NFS
{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    nfs-utils
  ];

  services.rpcbind.enable = true;
}
