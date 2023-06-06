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

          test_script = let
            cmds = [
              "ls .vscode | print"
              "ls -s .vscode | print"
              "ls .vscode | table | ansi strip | print"
            ];
          in ''
            $"(ansi blue)('This text should be blue.')(ansi reset)" | print
            ${builtins.concatStringsSep "\n" cmds}
          '';

          create_empty_out = ''
            touch empty
            mkdir $env.out
            cp empty ($env.out + "/")
          '';
        in {
          _module.args = {inherit pkgs lib;};

          # packages.nuenv-drv = pkgs.nuenv.mkDerivation rec {
          #   name = "nu-drv";
          #   inherit system;
          #   src = ./.;

          #   DRV_SYSTEM = system;

          #   build = ''
          #     print "=== ${name} ==="
          #     ${test_script}
          #     ${create_empty_out}
          #   '';
          # };

          packages.stdenv-drv = pkgs.stdenv.mkDerivation rec {
            pname = "stdenv-drv";
            version = "0.0.1";
            src = ./.;

            DRV_SYSTEM = system;

            buildPhase = create_nu "build-phase.nu" ''
              print "=== ${pname} ==="
              ${test_script}
            '';

            installPhase = create_nu "install-phase.nu" ''
              ${create_empty_out}
            '';
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
