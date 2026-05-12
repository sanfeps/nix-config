{lib, ...}: {
  i18n = {
    defaultLocale = lib.mkDefault "en_US.UTF-8"; # English UI, Spanish regional formats via LC_*
    supportedLocales = lib.mkDefault [
      "en_US.UTF-8/UTF-8"
      "es_ES.UTF-8/UTF-8"
    ];

    extraLocaleSettings = {
      LC_ADDRESS = "es_ES.UTF-8";
      LC_IDENTIFICATION = "es_ES.UTF-8";
      LC_MEASUREMENT = "es_ES.UTF-8";
      LC_MONETARY = "es_ES.UTF-8";
      LC_NAME = "es_ES.UTF-8";
      LC_NUMERIC = "es_ES.UTF-8";
      LC_PAPER = "es_ES.UTF-8";
      LC_TELEPHONE = "es_ES.UTF-8";
      LC_TIME = "es_ES.UTF-8";
    };
  };

  # Keyboard configuration
  console.keyMap = "es"; # Spanish keyboard for console (outside of X11/Wayland)

  time.timeZone = lib.mkDefault "Europe/Madrid";
}
