; Downstream verifier control: AS1->AS0 of a struct* is a legal shape for
; the earlier addrspacecast user/element checks, so the remaining fail-closed
; rule is "AddrSpaceCast source must be addrspace(0)".
target triple = "x86_64-unknown-linux-gnu"

%S = type { i64 }

define void @managed_native_managed(%S addrspace(1)* %managed, %S** %slot) gc "cangjie" {
entry:
  %native = addrspacecast %S addrspace(1)* %managed to %S*
  store %S* %native, %S** %slot
  ret void
}
