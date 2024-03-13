{
  description = "package definition and devshell for gitout";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  inputs.systems.url = "github:msfjarvis/flake-systems";

  inputs.advisory-db.url = "github:rustsec/advisory-db";
  inputs.advisory-db.flake = false;

  inputs.crane.url = "github:ipetkov/crane";
  inputs.crane.inputs.nixpkgs.follows = "nixpkgs";

  inputs.devshell.url = "github:numtide/devshell";
  inputs.devshell.inputs.nixpkgs.follows = "nixpkgs";
  inputs.devshell.inputs.flake-utils.follows = "flake-utils";

  inputs.fenix.url = "github:nix-community/fenix";
  inputs.fenix.inputs.nixpkgs.follows = "nixpkgs";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.flake-utils.inputs.systems.follows = "systems";

  inputs.flake-compat.url = "github:nix-community/flake-compat";
  inputs.flake-compat.flake = false;

  outputs = {
    nixpkgs,
    advisory-db,
    crane,
    devshell,
    fenix,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [devshell.overlays.default];
      };

      rustStable = (import fenix {inherit pkgs;}).fromToolchainFile {
        file = ./rust-toolchain.toml;
        sha256 = "sha256-e4mlaJehWBymYxJGgnbuCObVlqMlQSilZ8FljG9zPHY=";
      };
      graphqlFilter = path: builtins.match ".*graphql$" path != null;
      filter = path: type: (graphqlFilter path) || (craneLib.filterCargoSources path type);

      craneLib = (crane.mkLib pkgs).overrideToolchain rustStable;
      commonArgs = {
        src = pkgs.lib.cleanSourceWith {
          src = craneLib.path ./.;
          inherit filter;
        };
        buildInputs = with pkgs; [(lib.getDev openssl)];
        nativeBuildInputs = with pkgs; [pkg-config];
        cargoClippyExtraArgs = "--all-targets -- --deny warnings";
      };
      cargoArtifacts = craneLib.buildDepsOnly (commonArgs // {doCheck = false;});

      gitout = craneLib.buildPackage (commonArgs // {doCheck = false;});
      gitout-clippy = craneLib.cargoClippy (commonArgs
        // {
          inherit cargoArtifacts;
        });
      gitout-fmt = craneLib.cargoFmt (commonArgs // {});
      gitout-audit = craneLib.cargoAudit (commonArgs // {inherit advisory-db;});
      gitout-nextest = craneLib.cargoNextest (commonArgs
        // {
          inherit cargoArtifacts;
          src = ./.;
          partitions = 1;
          partitionType = "count";
        });
    in {
      checks = {
        inherit gitout;
        # There are some deprecated dependencies that need to be replaced
        #inherit gitout-audit;
        # Clippy hates this old code
        #inherit gitout-clippy;
        inherit gitout-fmt;
        inherit gitout-nextest;
      };

      packages.default = gitout;

      apps.default = flake-utils.lib.mkApp {drv = gitout;};

      devShells.default = pkgs.devshell.mkShell {
        bash = {interactive = "";};
        imports = ["${pkgs.devshell.extraModulesDir}/language/c.nix"];
        language.c = {
          includes = with pkgs; [(lib.getDev openssl)];
          compiler = pkgs.stdenv.cc;
        };

        env = [
          {
            name = "DEVSHELL_NO_MOTD";
            value = 1;
          }
        ];

        packages = with pkgs; [
          cargo-nextest
          cargo-release
          rustStable
          stdenv.cc
        ];
      };
    });
}
