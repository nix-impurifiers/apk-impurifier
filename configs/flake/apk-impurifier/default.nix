# SPDX-License-Identifier: MIT
{ ... }:
{ lib, inputs, ... }:
{
  flake.lib = lib.mkForce {
    apk-impurifier =
      { pkgs }:
      import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
        sourceInfo = inputs.self;
      };
  };
  perSystem =
    { pkgs, ... }:
    let
      impurifier = import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
        sourceInfo = inputs.self;
      };
    in
    {
      packages = {
        default = impurifier.engine;
        hello-native-packages = impurifier.makeNativePackages { pkg = pkgs.hello; };
        engine = impurifier.engine;
        runtime-apk = impurifier.runtimeApk;
        hello-net-apk = impurifier.makeNetApk { pkg = pkgs.hello; };
        hello-offline-apk = impurifier.makeOfflineApk { pkg = pkgs.hello; };
      };
      formatter = pkgs.nixfmt-tree;
      checks = import ../../../tests {
        inherit pkgs impurifier;
        coreSrc = inputs.impurifier;
      };
    };
}
