{lib, ...}: {
  i18n = {
    defaultLocale = lib.mkDefault "es_ES.UTF-8"; # Spanish as default languaje
    supportedLocales = lib.mkDefault [
      "es_ES.UTF-8/UTF-8"
    ];
  };

  # Keyboard configuration
  console.keyMap = "es"; # Spanish keyboard for console (outside of X11/Wayland)

  time.timeZone = lib.mkDefault "Europe/Madrid"; 
}

