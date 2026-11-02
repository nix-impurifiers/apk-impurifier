# SPDX-License-Identifier: MIT
{ pkgs, coreSrc }:
let
  inherit (pkgs) lib;
  # abuild 3.17's hash filter returns failure at clean EOF. Preserve data-tar
  # terminators and real error propagation instead of ignoring its status.
  archiveTools = pkgs.abuild.overrideAttrs (old: {
    patchPhase = (old.patchPhase or "") + ''
      patch -p1 < ${./abuild-tar-eof.patch}
    '';
  });
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    namespace = "apk-impurifier";
  };
  architecture =
    if pkgs.stdenv.hostPlatform.isx86_64 then
      "x86_64"
    else if pkgs.stdenv.hostPlatform.isAarch64 then
      "aarch64"
    else
      throw "apk-impurifier: unsupported architecture";
  atom = value: builtins.match "[A-Za-z0-9/!@:._+<>=~*-]+" value != null;
  buildApk =
    {
      name,
      version,
      release ? "0",
      architecture ? "noarch",
      payload,
      description ? "Impurified Nix package",
      license ? "LicenseRef-Unknown",
      dependencies ? [ ],
      provides ? [ ],
      replaces ? [ ],
      providerPriority ? 0,
      scripts ? { },
      triggers ? [ ],
    }:
    assert lib.assertMsg (builtins.match "[a-z0-9][a-z0-9+.-]+" name != null) "invalid APK name";
    assert lib.assertMsg (builtins.match "[0-9][A-Za-z0-9._+]*" version != null) "invalid APK version";
    assert lib.assertMsg (builtins.match "[0-9]+" release != null) "invalid APK release";
    assert lib.assertMsg (lib.all atom (
      dependencies ++ provides ++ replaces
    )) "invalid APK dependency atom";
    assert lib.assertMsg (
      builtins.isInt providerPriority && providerPriority >= 0
    ) "invalid provider priority";
    assert lib.assertMsg (lib.all (
      key:
      lib.elem key [
        "trigger"
        "pre-install"
        "post-install"
        "pre-upgrade"
        "post-upgrade"
        "pre-deinstall"
        "post-deinstall"
      ]
    ) (builtins.attrNames scripts)) "unsupported APK script";
    pkgs.runCommand "${name}-${version}-r${release}.apk"
      {
        nativeBuildInputs = [
          archiveTools
          pkgs.apk-tools
          pkgs.gzip
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      }
      ''
        set -eo pipefail
        apk version --check '${version}-r${release}'
        mkdir root control
        cp -r ${payload}/. root/
        chmod -R u+w root
        find root -mindepth 1 -printf '%P\0' | sort -z > files
        # abuild-tar extends an existing PAX header with file checksums.
        # Keep deterministic atime/ctime headers, as upstream apk_tar does.
        tar -C root --null --no-recursion --mtime=@1 --owner=0 --group=0 --numeric-owner \
          --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,atime:=0,ctime:=0 -cf data.tar -T "$PWD/files"
        abuild-tar --hash < data.tar | gzip -n9 > data.tar.gz
        cat > control/.PKGINFO <<'PKGINFO'
        pkgname = ${name}
        pkgver = ${version}-r${release}
        pkgdesc = ${description}
        url = https://github.com/nix-impurifiers/apk-impurifier
        builddate = 1
        packager = Nix Impurifiers <root@localhost>
        arch = ${architecture}
        origin = ${name}
        license = ${license}
        provider_priority = ${toString providerPriority}
        ${lib.concatMapStringsSep "\n" (value: "depend = ${value}") dependencies}
        ${lib.concatMapStringsSep "\n" (value: "provides = ${value}") provides}
        ${lib.concatMapStringsSep "\n" (value: "replaces = ${value}") replaces}
        ${lib.optionalString (triggers != [ ]) "triggers = ${lib.concatStringsSep " " triggers}"}
        PKGINFO
        echo "size = $(du --apparent-size -sb root | cut -f1)" >> control/.PKGINFO
        echo "datahash = $(sha256sum data.tar.gz | cut -d' ' -f1)" >> control/.PKGINFO
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (kind: source: ''
            install -Dm755 ${lib.escapeShellArg (toString source)} control/.${kind}
          '') scripts
        )}
        tar -C control --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
          -cf control.tar .PKGINFO ${
            lib.concatMapStringsSep " " (kind: ".${kind}") (builtins.attrNames scripts)
          }
        abuild-tar --cut < control.tar | gzip -n9 > control.tar.gz
        cat control.tar.gz data.tar.gz > "$out"
      '';
  makeApk =
    args@{
      pkg,
      release ? "0",
      hostDependencies ? null,
      providerPriority ? null,
      ...
    }:
    let
      hostBackend = args.hostBackend or (if (args.systemd or null) != null then "systemd" else "openrc");
      payload = core.makePayload (
        (builtins.removeAttrs args [
          "release"
          "hostDependencies"
          "providerPriority"
        ])
        // {
          inherit hostBackend;
        }
      );
      hostDeps =
        if hostDependencies != null then
          hostDependencies
        else if hostBackend == "openrc" then
          [ "busybox" ] ++ lib.optional ((args.openrc or null) != null) "openrc"
        else
          [ "systemd" ];
    in
    buildApk {
      name = payload.name;
      inherit (payload) version description;
      inherit payload release architecture;
      providerPriority =
        if providerPriority != null then
          providerPriority
        else if payload.offline then
          10
        else
          100;
      dependencies = [
        "apk-impurifier>=0.1.0"
      ]
      ++ lib.optionals payload.hostEnabled hostDeps;

    };
  makeRuntimeApk =
    {
      nixDependency ? "nix",
      pythonDependency ? "python3",
    }:
    buildApk {
      name = "apk-impurifier";
      version = "0.1.0";
      payload = core.makeRuntimeTree { };
      license = "MIT";
      description = "Native package intent projected into a Nix profile";
      dependencies = [
        pythonDependency
        nixDependency
        "/bin/sh"
      ];
      triggers = [
        "/usr/share/nix-profile.d"
        "/usr/lib/apk-impurifier"
      ];
      scripts.trigger = pkgs.writeText "apk-impurifier.trigger" ''
        #!/bin/sh
        exec /usr/sbin/nix-profile-engine reconcile
      '';
    };
in
{
  inherit (core) engine offlineCache unit;
  inherit buildApk makeApk makeRuntimeApk;
  runtimeApk = makeRuntimeApk { };
  makePackage = args: {
    net = makeApk (args // { offline = false; });
    offline = makeApk (args // { offline = true; });
  };
  makeNetApk = args: makeApk (args // { offline = false; });
  makeOfflineApk = args: makeApk (args // { offline = true; });
}
