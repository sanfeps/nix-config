{pkgs, ...}: {
  programs.gh = {
    enable = true;
    extensions = with pkgs; [gh-markdown-preview];
  };
  home.persistence = {
    "/persist".files = [
      ".config/gh/hosts.yml"
      ".config/gh/config.yml"
    ];
  };
}
