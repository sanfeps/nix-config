{
  pkgs,
  config,
  ...
}: {
  programs.vscode = {enable = true;};
  home.persistence = {
    "/persist" = {
      directories = [
        ".config/Code"
        ".config/VSCodium"
      ];
    };
  };
}
