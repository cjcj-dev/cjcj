The three llvm.pack.00–02 files concatenate to one complete-tree shallow Git
pack for the formal LLVM pin 7ed574d4ba6ff1ebeceeb339ab4795e0141e4a60.
They were captured read-only from /root/cj_build/llvm_rebase using a fresh bare
repository and `git fetch --depth 1 file:///root/cj_build/llvm_rebase
7ed574d4ba6ff1ebeceeb339ab4795e0141e4a60:refs/heads/main`.

The pack is about 178 MiB, split at 64 MiB to fit GitHub's per-file limit.
It retains the entire pin tree, without parent history or an alternate object
store. The test consumes the real CangjieRuntimeLayout.h (2493 bytes), and the
existing runtime.pack supplies the actual runtime ABI generator and assertions.
The complete tree is intentional: checkoutExactSource does a real Git checkout;
a header-only synthetic commit would not preserve the formal source identity.

trimpath-layout-fixture.mjs reassembles this pack under its invocation's root,
then uses an unchanged copy of pinned-remote.mjs to install the exact pin.
The temporary pack is removed after import; mirrors and layout-source checkouts
are removed by the owning test's finally block. No persistent repository cache
is read or populated. If pins change, regenerate reviewed local packs; never
fetch the public source as a test fallback.
