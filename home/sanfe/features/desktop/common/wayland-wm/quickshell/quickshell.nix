{
 inputs,
 pkgs,
 lib,
 config,
 ...
}: {

	home.packages = [
		inputs.quickshell.packages.${pkgs.system}.default
		pkgs.qt6.full
	];

	home.sessionVariables = {
  		QML2_IMPORT_PATH = "${pkgs.qt6.full}/qml";
	};

	# Link the QuickShell configuration
	xdg.configFile."quickshell/quickshell-config".source = ./quickshell-config;

	# Autostart QuickShell with systemd user service
	systemd.user.services.quickshell = {
		Unit = {
			Description = "QuickShell - QML Desktop Shell";
			After = [ "graphical-session.target" ];
			PartOf = [ "graphical-session.target" ];
		};

		Service = {
			ExecStart = "${inputs.quickshell.packages.${pkgs.system}.default}/bin/quickshell -c ${config.xdg.configHome}/quickshell/quickshell-config";
			Restart = "on-failure";
			RestartSec = 3;
		};

		Install = {
			WantedBy = [ "graphical-session.target" ];
		};
	};
}
