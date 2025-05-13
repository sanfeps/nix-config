{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = {
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --asterisks --time --time-format '%I:%M %p | %a • %h | %F' -s";
          user = "greeter";
        };
      };
    };
    
    users.extraUsers.greeter = {
      createHome = true;
      home = "/tmp/greeter-home"; 
    };
  };
}


