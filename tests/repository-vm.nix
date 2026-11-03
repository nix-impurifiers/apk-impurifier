# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  frontend ? "apk2",
}:
let
  alpine = import ./alpine.nix { inherit pkgs; };
  tool =
    version:
    pkgs.runCommand "signed-tool-${version}"
      {
        pname = "signed-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/signed-tool
        chmod +x $out/bin/signed-tool
      '';
  app =
    offline: version:
    impurifier.makeApk {
      pkg = tool version;
      inherit offline;
      release = if offline then "1" else "0";
      hostDependencies = [ ];
      configFiles."/etc/signed-tool.conf" = pkgs.writeText "signed-tool.conf" "version=${version}\n";
    };
  provider = impurifier.buildApk {
    name = "fixture-native-runtime";
    version = "1";
    provides = [
      "nix"
      "python3"
    ];
    payload = pkgs.runCommand "apk-signed-runtime-provider" { } ''
      mkdir -p $out/usr/bin
      ln -s ${pkgs.nix}/bin/nix-store $out/usr/bin/nix-store
      ln -s ${pkgs.python3}/bin/python3 $out/usr/bin/python3
    '';
  };
  repository =
    offline: version:
    impurifier.makeRepository {
      packages = [
        provider
        impurifier.runtimeApk
        (app offline version)
      ];
    };
  client = if frontend == "apk2" then "/sbin/apk" else "${pkgs.apk-tools}/bin/apk";
in
pkgs.testers.runNixOSTest {
  name = "apk-impurifier-signed-repository-${frontend}";
  globalTimeout = 180;
  requiredFeatures = {
    kvm = false;
    devnet = false;
  };
  nodes.machine = { lib, ... }: {
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    virtualisation.memorySize = 1024;
    virtualisation.useNixStoreImage = true;
    virtualisation.writableStore = true;
    documentation.enable = false;
    environment.systemPackages = with pkgs; [
      nix
      python3
      gnutar
      apk-tools
      abuild
      openssl
    ];
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /alpine; tar -xzf ${alpine.rootfs} -C /alpine; mkdir -p /alpine/nix /alpine/repo/x86_64 /alpine/opt/nix /alpine/var/lib/apk-impurifier /opt/nix /var/lib/apk-impurifier")
    machine.succeed("mount --rbind /nix /alpine/nix; mount --rbind /dev /alpine/dev; mount -t proc proc /alpine/proc; mount --bind /opt/nix /alpine/opt/nix; mount --bind /var/lib/apk-impurifier /alpine/var/lib/apk-impurifier; : > /alpine/etc/apk/repositories; mkdir -p /alpine/etc/nix; printf 'substituters =\\nbuilders =\\nbuild-users-group =\\n' > /alpine/etc/nix/nix.conf")
    machine.succeed("cp -r ${repository false "1"} /repo-net; cp -r ${repository true "1"} /repo-1; cp -r ${repository true "2"} /repo-2; chmod -R u+w /repo-net /repo-1 /repo-2")
    machine.succeed("openssl genrsa -out /root/fixture.rsa 2048; openssl rsa -in /root/fixture.rsa -pubout -out /alpine/etc/apk/keys/fixture.rsa.pub")
    machine.succeed("for repo in /repo-net /repo-1 /repo-2; do $repo/sign-repository $repo /root/fixture.rsa; done; cp -r /repo-1/* /alpine/repo/")
    machine.succeed("systemctl stop dhcpcd; ip link set eth0 down")
    command = "setsid --wait timeout --foreground -k 2s 45s chroot /alpine /usr/bin/env PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root ${client} --no-network --repository /repo "
    with subtest("signed repository and unsigned package policy"):
        machine.succeed(command + "update")
        machine.succeed(command + "add fixture-native-runtime")
        machine.succeed("cp ${app true "1"} /alpine/unsigned.apk")
        code, output = machine.execute(command + "add /unsigned.apk 2>&1")
        assert code != 0 and any(word in output.lower() for word in ["signature", "untrusted"]), output
        machine.fail("test -e /opt/nix/profile/bin/signed-tool")
    with subtest("tampered repository index is rejected"):
        machine.succeed("cp /alpine/repo/x86_64/APKINDEX.tar.gz /index-good; python3 -c \"from pathlib import Path; p=Path('/alpine/repo/x86_64/APKINDEX.tar.gz'); b=bytearray(p.read_bytes()); b[len(b)//2]^=1; p.write_bytes(b)\"")
        code, output = machine.execute(command + "update 2>&1")
        assert code in (0, 1) and any(word in output.lower() for word in ["bad signature", "corrupt", "invalid"]), output
        machine.succeed("cp /index-good /alpine/repo/x86_64/APKINDEX.tar.gz")
    with subtest("signed package corruption cannot activate"):
        machine.succeed("cp /alpine/repo/x86_64/signed-tool-1-r1.apk /package-good; python3 -c \"from pathlib import Path; p=Path('/alpine/repo/x86_64/signed-tool-1-r1.apk'); b=bytearray(p.read_bytes()); b[-1]^=1; p.write_bytes(b)\"")
        machine.fail(command + "add signed-tool")
        machine.fail("test -e /opt/nix/profile/bin/signed-tool")
        machine.succeed("cp /package-good /alpine/repo/x86_64/signed-tool-1-r1.apk")
    machine.succeed("rm -rf /alpine/repo/*; cp -r /repo-net/* /alpine/repo/")
    code, output = machine.execute(command + "add signed-tool 2>&1")
    assert "nix-profile-engine:" in output, output
    machine.fail("test -e /opt/nix/profile/bin/signed-tool")
    machine.succeed("rm -rf /alpine/repo/*; cp -r /repo-1/* /alpine/repo/")
    code, output = machine.execute(command + "upgrade signed-tool 2>&1")
    assert code in (0, 1) and "activated " in output, output
    machine.succeed(command + "fix apk-impurifier")
    machine.succeed("test $(/opt/nix/profile/bin/signed-tool) = 1; echo administrator > /alpine/etc/signed-tool.conf")
    machine.succeed("rm -rf /alpine/repo/*; cp -r /repo-2/* /alpine/repo/")
    machine.succeed(command + "upgrade signed-tool")
    machine.succeed("test $(/opt/nix/profile/bin/signed-tool) = 2; grep administrator /alpine/etc/signed-tool.conf; chroot --userspec=65534:65534 /alpine /opt/nix/profile/bin/signed-tool | grep '^2$'; nix-store --gc")
    machine.succeed(command + "del signed-tool")
    machine.fail("test -e /opt/nix/profile/bin/signed-tool")
    if machine.execute("test -x /alpine/usr/sbin/nix-profile-engine")[0] == 0:
        machine.succeed("chroot /alpine /usr/sbin/nix-profile-engine prune --keep 0")
        machine.succeed(command + "del apk-impurifier")
    machine.succeed("nix-store --gc")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "2"))}")
  '';
}
