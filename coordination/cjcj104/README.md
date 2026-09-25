# kkk2 managed Node entry

The old `/usr/local/bin/{node,npm,npx}` links pointed into
`/media/kkk2/428602AC8602A111`, while the toolchain is mounted under `/mnt/win`.
Restore the existing v20.19.0 installation with physical copies, without changing
cjcj's `node` calls or `#!/usr/bin/env node` consumers:

```sh
bash /root/cj_build/ops/bin/wf_kkk2.sh sh <lane> \
  'ulimit -c 0; bash /path/to/tools/install-managed-node.sh /mnt/win/tools/node-v20.19.0-linux-x64 /usr/local'
```

First run the same command with a private prefix `/root/<lane>/private` and
validate it with that prefix's `bin` first in PATH. The source Node SHA-256 is
pinned to `34bc6627675906f8431892630b5e91fc4cc9f1e03ce15e9716025aa551e5c823`.
The script verifies source identity and copies the complete package into
`<prefix>/lib/node-v20.19.0-linux-x64`, dereferencing package links. It installs
a physical `<prefix>/bin/node` and ordinary npm/npx launcher scripts. Existing
identical installations may be reused; different destination contents require
operator investigation. Entry replacements use rename, so an old link's target
is never overwritten. Installation needs write access to the chosen prefix.

Validate `node --version` (v20.19.0), `npm --version`, `npx --version`,
`/usr/bin/env node --version`, and a real cjcj MJS contract through the restored
PATH. Check process exit statuses as well as output. Record binary hashes and
run each check three times. Do not substitute a lane's v23 binary or restore the
old mount-prefix link. The installed files no longer depend on `/mnt/win` being
mounted after reboot; no mount/fstab change is needed.

This repairs the host entry, not GC or compiler behavior. Runtime build arms and
SO mutation tests do not apply. Keep fault injection inside the lane's private
installation, never the shared entry used by other lanes.
