# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  coreSrc,
}:
let
  tool =
    name: version:
    pkgs.runCommand "${name}-${version}"
      {
        pname = name;
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${name}-${version}\n' > $out/bin/${name}
        chmod +x $out/bin/${name}
      '';
  command = "apk --root /srv/target --no-network --allow-untrusted";
  install = "${command} --initdb add /tmp/packages/*.apk\n${command} del $(${command} info | grep '^nix-store-')";
in
import (coreSrc + "/tests/native-vm.nix") {
  inherit pkgs install;
  name = "apk";
  tools = [ pkgs.apk-tools ];
  first = impurifier.makeNativePackages { pkg = tool "native-first" "1"; };
  second = impurifier.makeNativePackages { pkg = tool "native-second" "1"; };
  upgraded = impurifier.makeNativePackages { pkg = tool "native-first" "2"; };
  initialize = "mkdir -p /srv/target/etc/apk; touch /srv/target/etc/apk/repositories";
  upgrade = install;
  removeFirst = "${command} del native-first";
  removeSecond = "${command} del native-second";
  verify = "${command} audit --system";
}
