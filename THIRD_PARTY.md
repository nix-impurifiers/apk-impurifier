# Third-party material

`nix/abuild-tar-eof.patch` modifies abuild-tar.c from abuild 3.17.0, Copyright (C) 2009–2014 Timo Teräs, licensed GPL-2.0-only. The patch preserves that license; see [the upstream COPYING file, preserved verbatim](LICENSES/abuild-COPYING). Nix fetches the upstream source with its original notices and applies the patch when building this external tool. The impurifier emitter and runtime code are MIT licensed.

The CI workflow templates retain their original MIT SPDX notices. Packaged applications and external build/runtime dependencies retain their own licenses; the project's license does not relicense them.
