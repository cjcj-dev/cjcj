These offline fixtures retain the exact formal Git identities used by the Node
integration tests. They are shallow, complete-tree packs, not invented commits.

- runtime.pack: cjcj-dev/cangjie-runtime at
  259ad49f709222e75bdb832bcc28dc769ea4efbf
- tools.pack: local cjcj-tools migration candidate at
  8e27eead8dc93ddd20ed66eaac9fd4170072e1c6

Captured with `git init --bare` and
`git fetch --depth 1 <repository> <sha>:refs/heads/main`. Runtime used existing
local objects; tools used a normal `git clone --no-local --depth=1 --single-branch`
from the frozen local migration repository. The new public repository is not
created (bot403); this fixture proves local fixed-object consumption only.
The pack contains
that commit and its entire tree, with no parent history. `pinnedRemote` installs
it into a fresh bare repository and records its shallow boundary. The tests
then exercise their existing Git fetch/proof paths against this local remote.

When a formal pin changes, regenerate its pack from the reviewed local object;
tests must fail on a stale pack rather than fetch GitHub to repair it. Product
source URLs and fetch implementations are unchanged. Source identity guards
still compare the real formal SHA and canonical URL.
