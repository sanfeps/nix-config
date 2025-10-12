{
 inputs, 
 pkgs,
 lib,
 ...
}: {
 
	home.packages = [
		inputs.quickshell.packages.${pkgs.system}.default
		pkgs.qt6.full
	];
	
	home.sessionVariables = {
  		QML2_IMPORT_PATH = "${pkgs.qt6.full}/qml";
	};


}
