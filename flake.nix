{
  description = "Nix plugin for Lapce";

  inputs = {
    # <upstream>
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # <frameworks>
    flake-parts.url = "github:hercules-ci/flake-parts";

    # <tools>
    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";

    alejandra.url = "github:kamadorueda/alejandra";
    alejandra.inputs.nixpkgs.follows = "nixpkgs";

    nuenv.url = "github:MrFoxPro/nuenv";
    nuenv.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {...} @ inputs:
    with inputs;
      flake-parts.lib.mkFlake {inherit inputs;} {
        imports = [devenv.flakeModule];
        systems = ["x86_64-linux"];
        perSystem = {
          config,
          system,
          inputs',
          ...
        }: let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              inputs.nuenv.overlays.nuenv
              inputs.nuenv.overlays.default
            ];
            config.allowUnfree = true;
          };
          lib = pkgs.lib;
          create_nu = name: script: "${pkgs.nuenv.mkScript {inherit name script;}}/bin/${name}";
          nu_bin = pkgs.nushell + "/bin/nu";

          test_script = ''
            ${nu_bin} --version | print
            print $"Derivation script that runs in Nushell"
            if ("DRV_SYSTEM" in $env) { print $"Building for system: ($env.DRV_SYSTEM)" }

            def blue [msg: string] { $"(ansi blue)($msg)(ansi reset)" }
            blue "This text should be blue." | print

            print "Let's inspect command outputs:"
            let commands = [
              "ls -la"
              "ls -la | table"
              "ls -la | table | ansi strip"
            ]
            for cmd in $commands {
              print $"> ($cmd)"
              ${nu_bin} -c $cmd | print
            }
          '';

          create_empty_out = ''
            touch empty
            mkdir $env.out
            cp empty ($env.out + "/")
          '';
        in {
          _module.args = {inherit pkgs lib;};

          packages.nuenv-drv = pkgs.nuenv.mkDerivation {
            name = "nu-drv";
            inherit system;
            src = let _src = builtins.trace ./. ./.; in _src;

            DRV_SYSTEM = system;

            build = ''
              print "BEFORE"
              print ("NIX SANDBOX IS: " + $env.NIX_BUILD_TOP)
              print ("NIX STORE IS: " + $env.NIX_STORE)
              ${test_script}
               print "AFTER"
              ${create_empty_out}
            '';
          };

          packages.stdenv-drv = pkgs.stdenv.mkDerivation {
            pname = "stdenv-drv";
            version = "0.0.1";
            src = ./.;

            DRV_SYSTEM = system;

            buildPhase = create_nu "build-phase.nu" ''
              print ("NIX SANDBOX IS: " + $env.NIX_BUILD_TOP)
              print ("NIX STORE IS: " + $env.NIX_STORE)
              ${test_script}
            '';

            installPhase = create_nu "install-phase.nu" ''
              ${test_script}
              ${create_empty_out}
            '';
          };

          packages.rust-drv = let
            manifest = with builtins; fromTOML (readFile ./Cargo.toml);
          in
            pkgs.rustPlatform.buildRustPackage {
              pname = "rust-drv";
              version = manifest.package.version;
              src = ./.;
              doCheck = false;

              DRV_SYSTEM = system;

              buildPhase = create_nu "build-phase.nu" ''
                ${test_script}
              '';
              installPhase = create_nu "install-phase.nu" ''
                ${test_script}
                ${create_empty_out}
              '';
              cargoLock = {
                lockFile = ./Cargo.lock;
                allowBuiltinFetchGit = true;
              };
            };

          devenv.shells.default = {
            name = "nushell-nix-shell";
            packages = with inputs'; [
              alejandra.packages.default
            ];
            enterShell = create_nu "enter-shell.nu" ''
              print "Welcome to Nix environment in Nushell!"

              print $"Run test-script to execute sample nushell script."
              print $"Run test-build-all to build default package and see it outputs."
            '';
            scripts = {
              test-script.exec = create_nu "test-script.nu" test_script;
              test-build-all.exec = with builtins;
                create_nu "test-build-all.nu" ''
                  let dervs = [${concatStringsSep " " (attrNames config.packages)}]
                  print ("Will build: " + ($dervs | str join " "))
                  for drv in $dervs { ${nu_bin} -c $"nix build .#packages.${system}.($drv) --print-build-logs" }
                '';
            };

            containers = lib.mkForce {};
          };
        };
      };
}
