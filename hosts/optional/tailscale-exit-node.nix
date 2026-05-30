{
  lib,
  pkgs,
  ...
}: let
  tailscale = lib.getExe pkgs.tailscale;
in {
  # "server" enables IPv4/IPv6 forwarding sysctls, required for exit-node + subnet-router roles.
  # The base optional/tailscale.nix defaults to "client" via mkDefault.
  services.tailscale.useRoutingFeatures = lib.mkForce "server";

  # autoconnect only runs `tailscale up` on first enroll. To keep the exit-node
  # flag declarative on every boot/deploy we apply it via `tailscale set`,
  # which mutates the running daemon without re-auth.
  systemd.services.tailscale-advertise-exit-node = {
    description = "Advertise this host as a Tailscale exit node";
    after = [
      "tailscaled.service"
      "tailscale-autoconnect-valgrindr.service"
    ];
    requires = ["tailscaled.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${tailscale} set --advertise-exit-node=true";
    };
  };
}
