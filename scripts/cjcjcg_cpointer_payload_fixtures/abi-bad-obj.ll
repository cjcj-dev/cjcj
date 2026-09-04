target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare void @llvm.cj.gcread.generic.payload(i8*, i8*, i32)

define void @bad_obj(i8* %dst, i8* %obj, i32 %size) gc "cangjie" {
  call void @llvm.cj.gcread.generic.payload(i8* %dst, i8* %obj, i32 %size)
  ret void
}
