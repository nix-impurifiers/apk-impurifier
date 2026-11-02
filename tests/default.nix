# SPDX-License-Identifier: GPL-3.0-or-later
{ pkgs, impurifier }:
let
  net = impurifier.makeNetApk { pkg = pkgs.hello; };
  offline = impurifier.makeOfflineApk { pkg = pkgs.hello; };
  closure = pkgs.closureInfo {
    rootPaths = [
      net
      offline
    ];
  };
in
{
  unit = impurifier.unit;
  emitter = pkgs.runCommand "apk-impurifier-contract" { nativeBuildInputs = [ pkgs.apk-tools pkgs.libarchive ]; } ''
    apk verify --allow-untrusted ${net} ${offline}
    bsdtar -xOf ${net} .PKGINFO | grep '^pkgname = hello$'
    bsdtar -xOf ${impurifier.makeRuntimeApk { nixDependency = "custom-nix-provider"; }} .PKGINFO | grep '^depend = custom-nix-provider$'
    test "$(wc -l < ${closure}/store-paths)" = 2
    touch $out
  '';
  vm = import ./vm.nix { inherit pkgs impurifier; };
}
