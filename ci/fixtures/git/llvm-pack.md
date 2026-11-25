The three llvm.pack.00–02 files concatenate to one shallow Git pack containing
the base LLVM commit and its complete tree. See [the fixture inventory](README.md)
for the base and current pins, the update pack, and the regeneration command.
The complete tree is intentional: layout contracts fetch and check out actual
Git objects and consume the real CangjieRuntimeLayout.h.
