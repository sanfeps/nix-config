{config, ...}:
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

  vpnNamespaces.mullvad.portMappings = [
    {
      from = port;
      to = port;
      protocol = "tcp";
    }
  ];

  networking.firewall.extraCommands = ''
    iptables -I nixos-fw -p tcp --dport ${toString port} -s 192.168.1.55 -j nixos-fw-accept
  '';
}
