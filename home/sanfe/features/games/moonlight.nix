{
  lib,
  pkgs,
  ...
}: let
  moonlight = lib.getExe pkgs.moonlight-qt;
  midgardHost = "midgard.ts.valgrindr.net";

  pairMidgard = pkgs.writeShellScriptBin "moonlight-pair-midgard" ''
    exec ${moonlight} pair ${lib.escapeShellArg midgardHost} "$@"
  '';

  streamMidgard = pkgs.writeShellScriptBin "moonlight-stream-midgard" ''
    exec ${moonlight} stream \
      --1080 \
      --fps 60 \
      --display-mode fullscreen \
      --quit-after \
      ${lib.escapeShellArg midgardHost} \
      "Steam Big Picture"
  '';
in {
  home.packages = [
    pkgs.moonlight-qt
    pairMidgard
    streamMidgard
  ];

  xdg.desktopEntries = {
    moonlight-midgard = {
      name = "Moonlight Midgard";
      genericName = "Remote Gaming";
      exec = lib.getExe streamMidgard;
      icon = "moonlight";
      terminal = false;
      categories = [
        "Game"
        "Network"
      ];
    };

    moonlight-pair-midgard = {
      name = "Pair Moonlight With Midgard";
      genericName = "Remote Gaming";
      exec = lib.getExe pairMidgard;
      icon = "moonlight";
      terminal = true;
      categories = [
        "Game"
        "Network"
      ];
    };
  };

  home.persistence."/persist".directories = [
    ".config/Moonlight Game Streaming Project"
  ];
}
