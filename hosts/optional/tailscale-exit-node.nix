{
  config,
  lib,
  pkgs,
  ...
}: let
  tailscale = lib.getExe pkgs.tailscale;
  cfg = config.services.tailscaleExitNode;
  # Advertised in the SAME `tailscale set` as the exit-node flag: tailscale tracks
  # the exit node as 0.0.0.0/0 + ::/0 inside the advertised-route set, so a second
  # `set --advertise-routes=…` call would clobber the exit-node routes. Keep them
  # in one invocation.
  routesFlag =
    lib.optionalString (cfg.advertiseRoutes != [])
    " --advertise-routes=${lib.concatStringsSep "," cfg.advertiseRoutes}";
in {
  options.services.tailscaleExitNode.advertiseRoutes = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    example = ["192.168.1.0/24"];
    description = ''
      Subnet CIDRs to advertise as a Tailscale subnet router, in addition to this
      host's exit-node role. Lets tailnet members reach those LAN ranges through
      this node. Must also be approved in the headscale policy (`autoApprovers.routes`
      or a manual `headscale nodes approve-routes`) before traffic flows.
    '';
  };

  config = {
    # "server" enables IPv4/IPv6 forwarding sysctls, required for exit-node + subnet-router roles.
    # The base optional/tailscale.nix defaults to "client" via mkDefault.
    services.tailscale.useRoutingFeatures = lib.mkForce "server";

    # autoconnect only runs `tailscale up` on first enroll. To keep the exit-node
    # flag (and any subnet routes) declarative on every boot/deploy we apply them
    # via `tailscale set`, which mutates the running daemon without re-auth.
    systemd.services.tailscale-advertise-exit-node = {
      description = "Advertise this host as a Tailscale exit node (+ subnet routes)";
      after = [
        "tailscaled.service"
        "tailscale-autoconnect-valgrindr.service"
      ];
      requires = ["tailscaled.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${tailscale} set --advertise-exit-node=true${routesFlag}";
      };
    };
  };
}
