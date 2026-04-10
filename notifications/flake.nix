{
  description = "Zulip to Signal notification bridge";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        erlang = pkgs.erlang;
        rebar3 = pkgs.rebar3;
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "zulip-signal";
          version = "0.1.0";
          src = ./.;

          nativeBuildInputs = [ erlang rebar3 ];

          buildPhase = ''
            export HOME=$TMPDIR
            rebar3 compile
            rebar3 release
          '';

          installPhase = ''
            mkdir -p $out
            cp -r _build/default/rel/zulip_signal/* $out/
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            erlang
            rebar3
            pkgs.signal-cli
          ];
        };
      });
}
