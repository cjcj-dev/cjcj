These offline fixtures retain the exact formal Git identities used by the Node
integration tests. They are shallow, complete-tree packs, not invented commits.

- runtime.pack: cjcj-dev/cangjie-runtime at
  259ad49f709222e75bdb832bcc28dc769ea4efbf
- tools.pack: cjcj-tools publish candidate at
  52adc7a2b67f8f1e711b6a50fbd0c83d85558a58

Captured with `git init --bare` and
`git fetch --depth 1 <repository> <sha>:refs/heads/main`. Runtime used existing
local objects; tools used a normal `git clone --no-local --depth=1 --single-branch`
from the frozen local candidate repository. The current tools pack was
regenerated from the complete reviewed 52adc object on
`fix/stage2-tool-cjpm-1031`; its public publish ref is
`publish/cangjie-tools-8e27-1029`. This fixture proves local fixed-object
consumption only; public fetch evidence is recorded separately.
The pack contains
that commit and its entire tree, with no parent history. `pinnedRemote` installs
it into a fresh bare repository and records its shallow boundary. The tests
then exercise their existing Git fetch/proof paths against this local remote.

When a formal pin changes, regenerate its pack from the reviewed local object;
tests must fail on a stale pack rather than fetch GitHub to repair it. Product
source URLs and fetch implementations are unchanged. Source identity guards
still compare the real formal SHA and canonical URL.
