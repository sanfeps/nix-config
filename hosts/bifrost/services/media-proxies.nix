{...}: let
  asgardIp = "192.168.1.54";

  # Pattern-B fan-out: every media service listens directly on asgard, with
  # asgard's firewall locking the port to bifrost only. Caddy here terminates
  # TLS via the *.lan.valgrindr.net wildcard cert and reverse-proxies plain
  # HTTP across the LAN. Until ./media on asgard is activated, these handles
  # 502 cosmetically — that's expected during scaffold mode.
  services = {
    jellyfin = 8096;
    seerr = 5055;
    qbittorrent = 8080;
    prowlarr = 9696;
    sonarr = 8989;
    radarr = 7878;
  };
in {
  services.caddy.virtualHosts."*.lan.valgrindr.net".extraConfig = ''
    @jellyfin host jellyfin.lan.valgrindr.net
    handle @jellyfin {
      reverse_proxy ${asgardIp}:${toString services.jellyfin}
    }

    @seerr host seerr.lan.valgrindr.net
    handle @seerr {
      reverse_proxy ${asgardIp}:${toString services.seerr}
    }

    @qbittorrent host qbittorrent.lan.valgrindr.net
    handle @qbittorrent {
      reverse_proxy ${asgardIp}:${toString services.qbittorrent}
    }

    @prowlarr host prowlarr.lan.valgrindr.net
    handle @prowlarr {
      reverse_proxy ${asgardIp}:${toString services.prowlarr}
    }

    @sonarr host sonarr.lan.valgrindr.net
    handle @sonarr {
      reverse_proxy ${asgardIp}:${toString services.sonarr}
    }

    @radarr host radarr.lan.valgrindr.net
    handle @radarr {
      reverse_proxy ${asgardIp}:${toString services.radarr}
    }
  '';
}
