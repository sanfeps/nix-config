{
  inputs,
  pkgs,
  lib,
  config,
  ...
}: let
  stateDir = "${config.home.homeDirectory}/.local/state/quickshell/user/generated";
  templatesDir = "${config.xdg.configHome}/matugen/templates";

  # Catppuccin Mocha fallback palette
  fallbackColors = {
    primary = "#cba6f7";
    on_primary = "#11111b";
    primary_container = "#585b70";
    on_primary_container = "#cdd6f4";
    secondary = "#89b4fa";
    on_secondary = "#1e1e2e";
    secondary_container = "#313244";
    on_secondary_container = "#cdd6f4";
    tertiary = "#94e2d5";
    on_tertiary = "#1e1e2e";
    tertiary_container = "#45475a";
    on_tertiary_container = "#cdd6f4";
    error = "#f38ba8";
    on_error = "#11111b";
    error_container = "#45475a";
    on_error_container = "#f38ba8";
    background = "#1e1e2e";
    on_background = "#cdd6f4";
    surface = "#181825";
    on_surface = "#cdd6f4";
    surface_variant = "#313244";
    on_surface_variant = "#bac2de";
    outline = "#585b70";
    outline_variant = "#45475a";
    shadow = "#11111b";
    scrim = "#11111b";
    inverse_surface = "#cdd6f4";
    inverse_on_surface = "#1e1e2e";
    inverse_primary = "#7c3aed";
    surface_dim = "#11111b";
    surface_bright = "#313244";
    surface_container_lowest = "#0d0d1a";
    surface_container_low = "#1e1e2e";
    surface_container = "#24273a";
    surface_container_high = "#313244";
    surface_container_highest = "#45475a";
  };

  fallbackColorsJson = builtins.toJSON fallbackColors;

  # Alacritty fallback colors (Catppuccin Mocha)
  fallbackAlacrittyToml = ''
    [colors.primary]
    background = "#1e1e2e"
    foreground = "#cdd6f4"

    [colors.cursor]
    text = "#1e1e2e"
    cursor = "#f5e0dc"

    [colors.normal]
    black   = "#45475a"
    red     = "#f38ba8"
    green   = "#a6e3a1"
    yellow  = "#f9e2af"
    blue    = "#89b4fa"
    magenta = "#f5c2e7"
    cyan    = "#94e2d5"
    white   = "#bac2de"

    [colors.bright]
    black   = "#585b70"
    red     = "#f38ba8"
    green   = "#a6e3a1"
    yellow  = "#f9e2af"
    blue    = "#89b4fa"
    magenta = "#f5c2e7"
    cyan    = "#94e2d5"
    white   = "#a6adc8"
  '';

  pamHelper = pkgs.writeTextFile {
    name = "qs-pam-auth";
    executable = true;
    destination = "/bin/qs-pam-auth";
    text = ''
      #!${
        pkgs.python3.withPackages (p: [p.python-pam])
      }/bin/python3
      import sys
      import pam

      p = pam.pam()
      password = sys.stdin.readline().rstrip('\n')
      user = sys.argv[1] if len(sys.argv) > 1 else '${config.home.username}'
      result = p.authenticate(user, password, service='qs-lock')
      sys.exit(0 if result else 1)
    '';
  };
in {
  imports = [inputs.stylix.homeModules.stylix];

  home.packages = with pkgs; [
    matugen
    awww
    pamHelper
  ];

  # Stylix: build-time fonts, cursor, icons only
  # Colors are managed at runtime by matugen
  stylix = {
    enable = true;
    autoEnable = false;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.fira-mono;
        name = "FiraMono Nerd Font Mono";
      };
      sansSerif = {
        package = pkgs.fira;
        name = "Fira Sans";
      };
      serif = {
        package = pkgs.fira;
        name = "Fira Sans";
      };
      emoji = {
        package = pkgs.noto-fonts-emoji;
        name = "Noto Color Emoji";
      };
    };
    cursor = {
      package = pkgs.catppuccin-cursors.mochaBlue;
      name = "catppuccin-mocha-blue-cursors";
      size = 24;
    };
    targets.gtk.enable = false;
  };

  # Matugen configuration
  xdg.configFile."matugen/config.toml".text = ''
    [config]
    reload_gtk_theme = true

    [templates.quickshell]
    input_path  = "${templatesDir}/colors.json.jinja"
    output_path = "${stateDir}/colors.json"

    [templates.gtk4]
    input_path  = "${templatesDir}/gtk4.css.jinja"
    output_path = "${config.xdg.configHome}/gtk-4.0/gtk.css"

    [templates.gtk3]
    input_path  = "${templatesDir}/gtk3.css.jinja"
    output_path = "${config.xdg.configHome}/gtk-3.0/gtk.css"

    [templates.alacritty]
    input_path  = "${templatesDir}/alacritty.toml.jinja"
    output_path = "${stateDir}/alacritty-colors.toml"
  '';

  # Matugen: colors.json template for quickshell
  xdg.configFile."matugen/templates/colors.json.jinja".text = ''
    {
      "primary":                   "{{colors.primary.default.hex}}",
      "on_primary":                "{{colors.on_primary.default.hex}}",
      "primary_container":         "{{colors.primary_container.default.hex}}",
      "on_primary_container":      "{{colors.on_primary_container.default.hex}}",
      "secondary":                 "{{colors.secondary.default.hex}}",
      "on_secondary":              "{{colors.on_secondary.default.hex}}",
      "secondary_container":       "{{colors.secondary_container.default.hex}}",
      "on_secondary_container":    "{{colors.on_secondary_container.default.hex}}",
      "tertiary":                  "{{colors.tertiary.default.hex}}",
      "on_tertiary":               "{{colors.on_tertiary.default.hex}}",
      "tertiary_container":        "{{colors.tertiary_container.default.hex}}",
      "on_tertiary_container":     "{{colors.on_tertiary_container.default.hex}}",
      "error":                     "{{colors.error.default.hex}}",
      "on_error":                  "{{colors.on_error.default.hex}}",
      "error_container":           "{{colors.error_container.default.hex}}",
      "on_error_container":        "{{colors.on_error_container.default.hex}}",
      "background":                "{{colors.background.default.hex}}",
      "on_background":             "{{colors.on_background.default.hex}}",
      "surface":                   "{{colors.surface.default.hex}}",
      "on_surface":                "{{colors.on_surface.default.hex}}",
      "surface_variant":           "{{colors.surface_variant.default.hex}}",
      "on_surface_variant":        "{{colors.on_surface_variant.default.hex}}",
      "outline":                   "{{colors.outline.default.hex}}",
      "outline_variant":           "{{colors.outline_variant.default.hex}}",
      "shadow":                    "{{colors.shadow.default.hex}}",
      "scrim":                     "{{colors.scrim.default.hex}}",
      "inverse_surface":           "{{colors.inverse_surface.default.hex}}",
      "inverse_on_surface":        "{{colors.inverse_on_surface.default.hex}}",
      "inverse_primary":           "{{colors.inverse_primary.default.hex}}",
      "surface_dim":               "{{colors.surface_dim.default.hex}}",
      "surface_bright":            "{{colors.surface_bright.default.hex}}",
      "surface_container_lowest":  "{{colors.surface_container_lowest.default.hex}}",
      "surface_container_low":     "{{colors.surface_container_low.default.hex}}",
      "surface_container":         "{{colors.surface_container.default.hex}}",
      "surface_container_high":    "{{colors.surface_container_high.default.hex}}",
      "surface_container_highest": "{{colors.surface_container_highest.default.hex}}"
    }
  '';

  # Matugen: GTK4 CSS template (libadwaita-compatible)
  xdg.configFile."matugen/templates/gtk4.css.jinja".text = ''
    @define-color accent_color {{colors.primary.default.hex}};
    @define-color accent_bg_color {{colors.primary.default.hex}};
    @define-color accent_fg_color {{colors.on_primary.default.hex}};
    @define-color destructive_color {{colors.error.default.hex}};
    @define-color destructive_bg_color {{colors.error_container.default.hex}};
    @define-color destructive_fg_color {{colors.on_error.default.hex}};
    @define-color success_color {{colors.tertiary.default.hex}};
    @define-color success_bg_color {{colors.tertiary_container.default.hex}};
    @define-color success_fg_color {{colors.on_tertiary.default.hex}};
    @define-color warning_color {{colors.secondary.default.hex}};
    @define-color warning_bg_color {{colors.secondary_container.default.hex}};
    @define-color warning_fg_color {{colors.on_secondary.default.hex}};
    @define-color error_color {{colors.error.default.hex}};
    @define-color error_bg_color {{colors.error_container.default.hex}};
    @define-color error_fg_color {{colors.on_error.default.hex}};
    @define-color window_bg_color {{colors.background.default.hex}};
    @define-color window_fg_color {{colors.on_background.default.hex}};
    @define-color view_bg_color {{colors.surface.default.hex}};
    @define-color view_fg_color {{colors.on_surface.default.hex}};
    @define-color headerbar_bg_color {{colors.surface_container_high.default.hex}};
    @define-color headerbar_fg_color {{colors.on_surface.default.hex}};
    @define-color headerbar_border_color {{colors.outline_variant.default.hex}};
    @define-color headerbar_backdrop_color {{colors.surface_container.default.hex}};
    @define-color headerbar_shade_color alpha({{colors.shadow.default.hex}}, 0.36);
    @define-color popover_bg_color {{colors.surface_container_high.default.hex}};
    @define-color popover_fg_color {{colors.on_surface.default.hex}};
    @define-color dialog_bg_color {{colors.surface_container_highest.default.hex}};
    @define-color dialog_fg_color {{colors.on_surface.default.hex}};
    @define-color sidebar_bg_color {{colors.surface_container_low.default.hex}};
    @define-color sidebar_fg_color {{colors.on_surface.default.hex}};
    @define-color sidebar_border_color {{colors.outline_variant.default.hex}};
    @define-color sidebar_backdrop_color {{colors.surface_container_lowest.default.hex}};
    @define-color card_bg_color {{colors.surface_container.default.hex}};
    @define-color card_fg_color {{colors.on_surface.default.hex}};
    @define-color card_shade_color alpha({{colors.shadow.default.hex}}, 0.07);
    @define-color thumbnail_bg_color {{colors.surface_dim.default.hex}};
    @define-color thumbnail_fg_color {{colors.on_surface.default.hex}};
    @define-color shade_color alpha({{colors.shadow.default.hex}}, 0.36);
    @define-color scrollbar_outline_color alpha({{colors.surface_variant.default.hex}}, 0.5);
  '';

  # Matugen: GTK3 CSS template
  xdg.configFile."matugen/templates/gtk3.css.jinja".text = ''
    @define-color theme_bg_color {{colors.background.default.hex}};
    @define-color theme_fg_color {{colors.on_background.default.hex}};
    @define-color theme_base_color {{colors.surface.default.hex}};
    @define-color theme_text_color {{colors.on_surface.default.hex}};
    @define-color theme_selected_bg_color {{colors.primary.default.hex}};
    @define-color theme_selected_fg_color {{colors.on_primary.default.hex}};
    @define-color theme_tooltip_bg_color {{colors.surface_container_high.default.hex}};
    @define-color theme_tooltip_fg_color {{colors.on_surface.default.hex}};
    @define-color borders {{colors.outline_variant.default.hex}};
    @define-color warning_color {{colors.error.default.hex}};
    @define-color error_color {{colors.error.default.hex}};
    @define-color success_color {{colors.tertiary.default.hex}};
  '';

  # Matugen: Alacritty colors template
  xdg.configFile."matugen/templates/alacritty.toml.jinja".text = ''
    [colors.primary]
    background = "{{colors.background.default.hex}}"
    foreground = "{{colors.on_background.default.hex}}"

    [colors.cursor]
    text   = "{{colors.background.default.hex}}"
    cursor = "{{colors.primary.default.hex}}"

    [colors.selection]
    text       = "{{colors.on_primary_container.default.hex}}"
    background = "{{colors.primary_container.default.hex}}"

    [colors.normal]
    black   = "{{colors.surface_variant.default.hex}}"
    red     = "{{colors.error.default.hex}}"
    green   = "{{colors.tertiary.default.hex}}"
    yellow  = "{{colors.secondary.default.hex}}"
    blue    = "{{colors.primary.default.hex}}"
    magenta = "{{colors.tertiary_container.default.hex}}"
    cyan    = "{{colors.tertiary.default.hex}}"
    white   = "{{colors.on_surface_variant.default.hex}}"

    [colors.bright]
    black   = "{{colors.outline.default.hex}}"
    red     = "{{colors.error_container.default.hex}}"
    green   = "{{colors.tertiary_container.default.hex}}"
    yellow  = "{{colors.secondary_container.default.hex}}"
    blue    = "{{colors.primary_container.default.hex}}"
    magenta = "{{colors.inverse_primary.default.hex}}"
    cyan    = "{{colors.inverse_surface.default.hex}}"
    white   = "{{colors.on_surface.default.hex}}"
  '';

  # Wallpaper change script
  home.file.".local/bin/set-wallpaper" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      wallpaper="$1"
      if [[ ! -f "$wallpaper" ]]; then
        echo "Error: file not found: $wallpaper" >&2
        exit 1
      fi
      ${lib.getExe pkgs.awww} img "$wallpaper" \
        --transition-type wipe \
        --transition-angle 30 \
        --transition-duration 1
      ${lib.getExe pkgs.matugen} image "$wallpaper"
    '';
  };

  # Ensure fallback color files exist on activation (before matugen runs)
  home.activation.matugenfallbacks = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "${stateDir}"
    if [ ! -f "${stateDir}/colors.json" ]; then
      printf '%s' ${lib.escapeShellArg fallbackColorsJson} > "${stateDir}/colors.json"
    fi
    if [ ! -f "${stateDir}/alacritty-colors.toml" ]; then
      printf '%s' ${lib.escapeShellArg fallbackAlacrittyToml} > "${stateDir}/alacritty-colors.toml"
    fi
  '';
}
