{
  description = "My NixOS configuration";

  inputs = {
    # Nix ecosystem
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.11";

    hardware.url = "github:nixos/nixos-hardware";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nix-gl = {
    #   url = "github:nix-community/nixgl";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nix-gaming = {
    #   url = "github:fufexan/nix-gaming";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    # My own programs, packaged with nix

  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    systems,
    ...
  } @ inputs: let
    inherit (self) outputs;
    systemsList = [
	"aarch64-darwin"
	"aarch64-linux"
	"x86_64-darwin"
	"x86_64-linux"
    ];

    lib = nixpkgs.lib // home-manager.lib;
    forEachSystem = f: lib.genAttrs systemsList (system: f pkgsFor.${system});
    pkgsFor = lib.genAttrs systemsList (
      system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }
    );
  in {
    inherit lib;
    nixosModules = import ./modules/nixos;
    homeManagerModules = import ./modules/home-manager;

    overlays = import ./overlays {inherit inputs outputs;};
    hydraJobs = import ./hydra.nix {inherit inputs outputs;};

    packages = forEachSystem (pkgs: import ./pkgs {inherit pkgs;});
    devShells = forEachSystem (pkgs: import ./shell.nix {inherit pkgs;});
    formatter = forEachSystem (pkgs: pkgs.alejandra);

    nixosConfigurations = {
      # Main desktop
      midgard = lib.nixosSystem {
        modules = [./hosts/midgard];
        specialArgs = {
          inherit inputs outputs;
        };
      };

      # Personal laptop
      # raidho = lib.nixosSystem {
      #   modules = [./hosts/raidho];
      #   specialArgs = {
      #     inherit inputs outputs;
      #   };
      # };
      # # Core server (Vultr)
      # asgard = lib.nixosSystem {
      #   modules = [./hosts/asgard];
      #   specialArgs = {
      #     inherit inputs outputs;
      #   };
      # };
      # # Build and game server (Oracle)
      # nidavellir = lib.nixosSystem {
      #   modules = [./hosts/nidavellir];
      #   specialArgs = {
      #     inherit inputs outputs;
      #   };
      # };
      # # Media server 
      # vanaheim = lib.nixosSystem {
      #   modules = [./hosts/vanaheim];
      #   specialArgs = {
      #     inherit inputs outputs;
      #   };
      # };
      # Bifrost (VPN or proxy server)
      # Heimdall (firewall)
      # Mimir (DB and RAG agent)
      # Niflheim (TOR node and XMR chain)
    };

    homeConfigurations = {
      # Standalone HM only
      
      # Main desktop
      "sanfe@midgard" = lib.homeManagerConfiguration {
        modules = [./home/sanfe/midgard.nix ./home/sanfe/nixpkgs.nix];
        pkgs = pkgsFor.x86_64-linux;
        extraSpecialArgs = {
          inherit inputs outputs;
        };
      };
    #
    #   # Personal laptop
    #   "sanfe@raidho" = lib.homeManagerConfiguration {
    #     modules = [ ./home/sanfe/raidho.nix ./home/sanfe/nixpkgs.nix ];
    #     pkgs = pkgsFor.x86_64-linux;
    #     extraSpecialArgs = {
    #       inherit inputs outputs;
    #     };
    #   };
    #
    #   # Core server (Vultr)
    #   "sanfe@asgard" = lib.homeManagerConfiguration {
    #     modules = [./home/sanfe/asgard.nix ./home/sanfe/nixpkgs.nix];
    #     pkgs = pkgsFor.x86_64-linux;
    #     extraSpecialArgs = {
    #       inherit inputs outputs;
    #     };
    #   };
    #
    #   # Build and game server (Oracle)
    #   "sanfe@nidavellir" = lib.homeManagerConfiguration {
    #     modules = [./home/sanfe/nidavellir.nix ./home/sanfe/nixpkgs.nix];
    #     pkgs = pkgsFor.aarch64-linux;
    #     extraSpecialArgs = {
    #       inherit inputs outputs;
    #     };
    #   };
    #
    #   # Media server 
    #   "sanfe@vanaheim" = lib.homeManagerConfiguration {
    #     modules = [./home/sanfe/vanaheim.nix ./home/sanfe/nixpkgs.nix];
    #     pkgs = pkgsFor.aarch64-linux;
    #     extraSpecialArgs = {
    #       inherit inputs outputs;
    #     };
    #   };
    };
  };
}
