These offline fixtures retain the exact formal Git identities used by the Node
integration tests. They are shallow, complete-tree packs, not invented commits.

- runtime.pack: cjcj-dev/cangjie-runtime at
  9733dfc09d29eca27d19cc3937a149838b4e3322
- tools.pack: cjcj-dev/cangjie-tools at
  3a7f4bb1a85672e98b799e4766758edac7d9ed08

Captured from the existing local repository objects with `git init --bare` and
`git fetch --depth 1 <local-repository> <sha>:refs/heads/main`. The pack contains
that commit and its entire tree, with no parent history. `pinnedRemote` installs
it into a fresh bare repository and records its shallow boundary. The tests
then exercise their existing Git fetch/proof paths against this local remote.

When a formal pin changes, regenerate its pack from the reviewed local object;
tests must fail on a stale pack rather than fetch GitHub to repair it. Product
source URLs and fetch implementations are unchanged. Source identity guards
still compare the real formal SHA and canonical URL.
