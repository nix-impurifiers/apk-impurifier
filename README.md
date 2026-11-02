# apk-impurifier

Emit Alpine APK v2 artifacts backed by the shared [impurifier engine](https://github.com/nix-impurifiers/impurifier). Native APK transactions own installation intent and host files; Nix supplies application closures through an atomic, GC-rooted `/opt/nix/profile`.

```nix
let impurifier = inputs.apk-impurifier.lib.apk-impurifier { inherit pkgs; };
in impurifier.makePackage { pkg = pkgs.hello; }
```

`makePackage` returns `net` and `offline`. Individual constructors are `makeApk`, `makeNetApk`, and `makeOfflineApk`. Versions and releases must satisfy native APK syntax. Net packages use administrator-configured Nix substituters. Offline packages contain the complete closure cache and import with remote substitution and remote builders disabled.

`makeRuntimeApk { nixDependency = "nix"; }` lets consumers choose a native Nix provider dependency. Python 3 and a working Nix installation must already exist. Providing Nix through an impure native package is deferred installer work, not excluded from the project.

Both flavors use the same native package name and version. Their contents and APK identities differ; installing the other local artifact replaces the existing flavor through an ordinary native transaction. Separate Nix outputs select transport without placing flavor-specific names in APK's world file. Export them under distinct filenames for local installation. Repository publication needs separate flavor channels or distinct native releases; both cannot occupy the same repository filename.

```sh
sudo apk add --allow-untrusted ./hello-offline.apk
sudo apk add --allow-untrusted ./hello-net.apk
sudo apk del hello
```

Unsigned local artifacts require `--allow-untrusted`; a production repository should use its own signing/distribution policy. The emitter does not modify global trust configuration.

`configFiles`, `files`, `users`, and `directories` use the common payload DSL. OpenRC is the default host backend; `openrc.script` accepts a native runscript. Its `enable`, `startOnInstall`, `restartOnUpgrade`, and `stopOnRemove` policies default to true. The engine provisions accounts and directories using BusyBox, publishes the profile, and starts services. Scripts should invoke `/opt/nix/profile/bin/<tool>`. Removed services retain a generation-owned copy of the effective runscript so post-transaction cleanup can stop them after APK removes their installed script. Persistent accounts and data remain. Native protected configuration rules govern edited files.

The runtime uses an APK directory trigger. Fetch/composition failure preserves the previous profile, although APK may have committed package changes. Service failures may occur after publication. Inspect diagnostics, fix the cause and run `/usr/sbin/nix-profile-engine reconcile`. APK can retain a broken-script flag after a failed trigger; recovery also requires native `apk fix apk-impurifier` with the runtime artifact available in a repository. `status` reports the published profile; `prune --keep 2` retains active and pending activation roots.

```sh
nix flake check -L
```

Checks include native APK verification, reference-free artifact closures, shared engine contracts, and a QEMU VM with actual Alpine userspace, APK and OpenRC. The fixture supplies a preinstalled Nix/Python runtime and pinned native OpenRC packages; it does not test a Nix installer or an Alpine kernel/PID 1 boot.

MIT.

Lifecycle hooks `lifecycle.onInstall` and `lifecycle.onUpgrade` accept shell bodies. They run as root after accounts/directories exist and the new profile is published, before service activation. Use `/opt/nix/profile/bin/<tool>` for projected commands and declare native dependencies for other commands. Install hooks run until the application's first successful activation; upgrade hooks run when its output, version or hook revision changes, including native downgrades. A failed hook leaves activation pending and may be retried, so hooks must be idempotent. They do not provide database rollback or exactly-once execution. Flavor-only changes to the same application do not rerun completed hooks.

Host-library bridging is opt-in:

```nix
hardware = {
  libraries."libdriver.so.1" = "/usr/lib/libdriver.so.1";
  programs = [ "my-tool" ];
  preload = []; # Optional subset of declared library names.
};
```

The engine captures explicitly selected ELF files into an immutable Nix-store directory, roots it with the generation, and wraps the selected application's `bin` commands with `LD_LIBRARY_PATH` and optional `LD_PRELOAD`. Native library-directory transaction hooks reconcile driver upgrades. Changed snapshots create a new generation and restart previously running managed services according to their upgrade policy. Older generations retain their original user-space snapshot. Missing or unreadable libraries abort before profile publication; the existing snapshot remains usable.

Consumers select compatible libraries, their non-Nix dependencies, paths and native package dependencies. This does not discover a GPU stack, validate its ABI, rebind already-running processes, or roll back kernel modules. GPU user/kernel compatibility and real-device behavior need hardware tests. Sources outside `/usr/lib`, `/usr/lib64`, `/lib` and `/lib64` need explicit reconciliation after updates. This is a bounded runtime bridge, not automatic GPU compatibility.

The exported `runtimeVersion` follows the pinned core source timestamp. Application dependencies require that runtime version or newer, rather than accepting every engine as `0.1.0`. This supports ordinary native engine upgrades without project release tags. Consumer-provided Nix dependency expressions remain independent of the engine's own native version.
