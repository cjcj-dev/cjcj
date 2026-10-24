These offline fixtures retain the exact formal Git identities used by the Node
integration tests. They are shallow, complete-tree packs, not invented commits.

- runtime.pack: cjcj-dev/cangjie-runtime at
  0d6e0888216481c55d1e8b2a0fc2685672289b6a
- tools.pack: cjcj-dev/cangjie-tools at
  2c8a704d7d51e65af2b777e11836aeef66bd8f50

Captured with `git init --bare` and
`git fetch --depth 1 <repository> <sha>:refs/heads/main`. Runtime used existing
local objects; tools used its canonical source repository at the exact pin.
The pack contains
that commit and its entire tree, with no parent history. `pinnedRemote` installs
it into a fresh bare repository and records its shallow boundary. The tests
then exercise their existing Git fetch/proof paths against this local remote.

When a formal pin changes, regenerate its pack from the reviewed local object;
tests must fail on a stale pack rather than fetch GitHub to repair it. Product
source URLs and fetch implementations are unchanged. Source identity guards
still compare the real formal SHA and canonical URL.
