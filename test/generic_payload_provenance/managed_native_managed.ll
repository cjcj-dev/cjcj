; Negative compiler fixture for the source classifier: the outer AS0 -> AS1
; cast is not a native view because its AS0 operand came from AS1.
target triple = "x86_64-unknown-linux-gnu"

define void @managed_native_managed(i8 addrspace(1)* %managed) gc "cangjie" {
entry:
  %native = addrspacecast i8 addrspace(1)* %managed to i8*
  %roundtrip = addrspacecast i8* %native to i8 addrspace(1)*
  ret void
}
