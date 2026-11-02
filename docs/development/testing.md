# Testing

`nix flake check -L` runs emitter contracts, the shared engine's unit suite, and real APK transactions in QEMU. Offline tests disable networking and assert the application closure is initially absent. Coverage includes failed substitution, recovery, flavor switching, edited configuration, upgrades, accounts/directories, OpenRC services, lifecycle hooks, administrator intent, removal, GC and native driver-package upgrades that refresh immutable snapshots.

The fixture runs Alpine userspace and actual APK/OpenRC inside a NixOS VM; it supplies preinstalled Nix/Python and pinned native OpenRC dependencies. It does not boot Alpine PID 1. APK can retain broken-script state after a failed trigger; recovery tests repair it with native `apk fix` from a local repository.
