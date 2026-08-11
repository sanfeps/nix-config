{
  config,
  lib,
  ...
}:
# Radarr — movies counterpart to Sonarr. Same shape, same constraints,
# different port + root folder. See sonarr.nix for the design notes;
# only the deltas live here.
let
  port = 7878;
in {
  services.radarr = {
    enable = true;
    openFirewall = false;
  };

  users.users.radarr.extraGroups = ["media"];

  # Group-writable library (umask 0002 → dirs 0775 / files 0664). The library
  # tree is setgid group `media`; without this Radarr writes movie folders 0755
  # and files 0644, so other media-group members can't modify/delete them — in
  # particular Jellyfin (also in `media`) can't delete a movie from its UI. Same
  # umask the other writers use (qbittorrent.nix, music-dl.nix); see storage.nix.
  # mkForce overrides the servarr module's own UMask=0022 default.
  systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";

  environment.persistence."${config.hostSpec.persistFolder}".directories = [
    {
      directory = "/var/lib/radarr";
      user = "radarr";
      group = "radarr";
      mode = "0700";
    }
  ];

  systemd.services.radarr.vpnConfinement = {
    enable = true;
    vpnNamespace = "mullvad";
  };

  # See sonarr.nix / media/caddy.nix: portMappings stays for the in-namespace
  # veth INPUT ACCEPT rule; local Caddy reaches Radarr at 192.168.15.1:${toString port}.
  vpnNamespaces.mullvad.portMappings = [
    {
      from = port;
      to = port;
      protocol = "tcp";
    }
  ];
}
