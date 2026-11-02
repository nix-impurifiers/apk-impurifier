# SPDX-License-Identifier: GPL-3.0-or-later
{ pkgs, impurifier }:
let
  alpine = import ./alpine.nix { inherit pkgs; };
  tool =
    version:
    pkgs.runCommand "apk-tool-${version}"
      {
        pname = "apk-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/apk-tool
        chmod +x $out/bin/apk-tool
      '';
  app =
    offline: version:
    impurifier.makeApk {
      pkg = tool version;
      inherit offline;
      configFiles."/etc/apk-tool.conf" = pkgs.writeText "apk-tool.conf" "version=${version}\n";
    };
  daemon =
    version:
    pkgs.runCommand "apk-service-${version}"
      {
        pname = "apk-service";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        cat > $out/bin/apk-service <<'SCRIPT'
        #!${pkgs.busybox}/bin/sh
        echo ${version} > /var/lib/apk-service/version
        exec ${pkgs.busybox}/bin/sleep infinity
        SCRIPT
        chmod +x $out/bin/apk-service
      '';
  service =
    version:
    impurifier.makeOfflineApk {
      pkg = daemon version;
      users.apk-service = { };
      directories."/var/lib/apk-service" = {
        owner = "apk-service:apk-service";
        mode = "0750";
      };
      openrc.script = pkgs.writeText "apk-service.init" ''
        #!/sbin/openrc-run
        command=/opt/nix/profile/bin/apk-service
        command_user=apk-service:apk-service
        command_background=yes
        pidfile=/run/apk-service.pid
      '';
    };
  provider = impurifier.buildApk {
    name = "vm-runtime";
    version = "1";
    provides = [
      "nix"
      "python3"
    ];
    payload = pkgs.runCommand "apk-runtime-payload" { } ''
      mkdir -p $out/usr/share/impurifier-vm
      echo preinstalled > $out/usr/share/impurifier-vm/runtime
    '';
  };
in
pkgs.testers.runNixOSTest {
  name = "apk-impurifier-openrc";
  requiredFeatures = {
    kvm = false;
    devnet = false;
  };
  nodes.machine = { lib, ... }: {
    virtualisation.memorySize = 2048;
    virtualisation.diskSize = 2048;
    virtualisation.useNixStoreImage = true;
    virtualisation.writableStore = true;
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [
      pkgs.nix
      pkgs.python3
      pkgs.gnutar
    ];
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /srv/alpine; tar xzf ${alpine.rootfs} -C /srv/alpine")
    machine.succeed("mkdir -p /srv/alpine/nix /srv/alpine/proc /srv/alpine/sys /srv/alpine/dev /srv/alpine/packages /srv/alpine/opt/nix /srv/alpine/var/lib/apk-impurifier /opt/nix /var/lib/apk-impurifier")
    machine.succeed("mount --rbind /nix /srv/alpine/nix; mount -t proc proc /srv/alpine/proc; mount --rbind /dev /srv/alpine/dev; mount --rbind /sys /srv/alpine/sys; mount --bind /opt/nix /srv/alpine/opt/nix; mount --bind /var/lib/apk-impurifier /srv/alpine/var/lib/apk-impurifier")
    machine.succeed("ln -s ${pkgs.python3}/bin/python3 /srv/alpine/usr/bin/python3; ln -s ${pkgs.nix}/bin/nix-store /srv/alpine/usr/bin/nix-store")
    machine.succeed("cp ${provider} /srv/alpine/packages/provider.apk; cp ${impurifier.runtimeApk} /srv/alpine/packages/runtime.apk; cp ${app false "1"} /srv/alpine/packages/net1.apk; cp ${app true "1"} /srv/alpine/packages/offline1.apk; cp ${app true "2"} /srv/alpine/packages/offline2.apk; cp ${service "1"} /srv/alpine/packages/service1.apk; cp ${service "2"} /srv/alpine/packages/service2.apk")
    machine.succeed("cp ${alpine.openrc} /srv/alpine/packages/openrc.apk; cp ${alpine.openrc-user} /srv/alpine/packages/openrc-user.apk; cp ${alpine.libcap} /srv/alpine/packages/libcap.apk; cp ${alpine.ifupdown} /srv/alpine/packages/ifupdown.apk")
    machine.succeed("systemctl stop dhcpcd; ip link set eth0 down")
    root = "chroot /srv/alpine /usr/bin/env PATH=/usr/sbin:/usr/bin:/sbin:/bin "
    apk = root + "/sbin/apk --allow-untrusted --no-network --repository /packages "
    machine.succeed("mkdir -p /srv/alpine/packages/x86_64 /srv/alpine/packages/noarch; cp /srv/alpine/packages/runtime.apk /srv/alpine/packages/noarch/apk-impurifier-0.1.0-r0.apk")
    machine.succeed(root + "/sbin/apk --allow-untrusted index -o /packages/x86_64/APKINDEX.tar.gz /packages/noarch/apk-impurifier-0.1.0-r0.apk")
    machine.succeed(apk + "add /packages/openrc.apk /packages/openrc-user.apk /packages/libcap.apk /packages/ifupdown.apk /packages/provider.apk /packages/runtime.apk")
    machine.succeed("mkdir -p /srv/alpine/run/openrc; echo default > /srv/alpine/run/openrc/softlevel")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
    with subtest("failed net trigger preserves the existing profile"):
        before = machine.succeed("readlink /opt/nix/profile").strip()
        output = machine.execute(apk + "add /packages/net1.apk 2>&1")[1]
        assert "nix-profile-engine:" in output, output
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    with subtest("offline flavor recovers without any network"):
        code, output = machine.execute(apk + "add /packages/offline1.apk 2>&1")
        assert code in (0, 1) and "activated " in output, output
        machine.succeed(apk + "fix apk-impurifier")
        machine.succeed(root + "/opt/nix/profile/bin/apk-tool | grep '^1$'")
    with subtest("native protected configuration survives switching and upgrade"):
        machine.succeed("echo local > /srv/alpine/etc/apk-tool.conf")
        machine.succeed(apk + "add /packages/net1.apk")
        machine.succeed("grep local /srv/alpine/etc/apk-tool.conf")
        machine.succeed(apk + "add /packages/offline2.apk")
        machine.succeed(root + "/opt/nix/profile/bin/apk-tool | grep '^2$'")
        machine.succeed("grep local /srv/alpine/etc/apk-tool.conf")
    with subtest("OpenRC lifecycle uses actual native account and service tools"):
        machine.succeed(apk + "add /packages/service1.apk")
        machine.wait_until_succeeds("grep '^1$' /srv/alpine/var/lib/apk-service/version")
        machine.succeed(root + "/sbin/rc-service apk-service status")
        machine.succeed("test $(stat -c %U /srv/alpine/var/lib/apk-service) != root")
        machine.succeed(apk + "add /packages/service2.apk")
        machine.wait_until_succeeds("grep '^2$' /srv/alpine/var/lib/apk-service/version")
        machine.succeed(root + "/sbin/rc-service apk-service stop")
        machine.succeed(root + "/sbin/rc-update del apk-service default")
        machine.succeed(apk + "add /packages/service1.apk")
        machine.fail(root + "/sbin/rc-service apk-service status")
        machine.fail("test -L /srv/alpine/etc/runlevels/default/apk-service")
        machine.succeed(root + "/sbin/rc-service apk-service start")
        machine.succeed(apk + "del apk-service")
        machine.fail(root + "/sbin/rc-service apk-service status")
        machine.fail("test -L /srv/alpine/etc/runlevels/default/apk-service")
        machine.succeed("test -d /srv/alpine/var/lib/apk-service")
    with subtest("rooted closures survive GC and removal drops intent"):
        machine.succeed("nix-store --gc")
        machine.succeed(root + "/opt/nix/profile/bin/apk-tool | grep '^2$'")
        machine.succeed(apk + "del apk-tool")
        machine.fail("test -e /opt/nix/profile/bin/apk-tool")
        machine.succeed(root + "/usr/sbin/nix-profile-engine prune --keep 0")
        machine.succeed("nix-store --gc; test -d /opt/nix/profile")
  '';
}
