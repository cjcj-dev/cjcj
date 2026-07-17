# Java/ObjC after-type-check no-op scope

## Scope rule

The count below follows an ordinary package with no Java/Objective-C declarations and
`GlobalOptions::InteropLanguage::NA`. Ranges include the executable C++ source from each entry
through the first ordinary-package early return, or all loop/helper control flow that an ordinary
declaration actually traverses. Counts are inclusive physical source lines. Java/Objective-C-only
branches after those gates are excluded and are feature debt, not part of the ordinary no-op path.

## Java

| Entity / method | C++ source range | Ordinary-package path | Lines |
|---|---|---|---:|
| `JavaInteropManager::JavaInteropManager` | `src/Sema/NativeFFI/Java/AfterTypeCheck/JavaInteropManager.h:25-36` | Save the seven constructor arguments; `hasMirrorOrImpl` remains `false`. | 12 |
| `JavaInteropManager::CheckImplRedefinition` | `src/Sema/NativeFFI/Java/AfterTypeCheck/TypeCheckJavaInterop.cpp:351-375` | Iterate files and declarations; non-class/broken declarations and non-`IsImpl` class-likes continue. | 25 |
| `JavaInteropManager::CheckTypes(File&)` | `src/Sema/NativeFFI/Java/AfterTypeCheck/TypeCheckJavaInterop.cpp:377-390` | Iterate every declaration and dispatch the four checks below. | 14 |
| `JavaInteropManager::CheckInheritance` | `src/Sema/NativeFFI/Java/AfterTypeCheck/TypeCheckJavaInterop.cpp:280-287` | Run subtype-attribute check; ordinary declaration fails `IsMirror || IsImpl`. | 8 |
| `CheckJavaMirrorSubtypeAttrClassLikeDecl` | `src/Sema/NativeFFI/Java/AfterTypeCheck/TypeCheckJavaInterop.cpp:310-318` | Evaluate the recursive subtype predicate; ordinary hierarchy produces no diagnostic. | 9 |
| `IsJavaMirrorSubtype` | `src/Sema/NativeFFI/Java/AfterTypeCheck/TypeCheckJavaInterop.cpp:36-60` | Walk ordinary class/interface parents and return `false`. | 25 |
| `JavaInteropManager::CheckTypes(ClassLikeDecl&)` | `src/Sema/NativeFFI/Java/AfterTypeCheck/TypeCheckJavaInterop.cpp:392-396` | Return when neither Java mirror attribute is set. | 5 |
| `JavaInteropManager::CheckExtendDecl` | `src/Sema/NativeFFI/Java/AfterTypeCheck/TypeCheckJavaInterop.cpp:320-325` | Return when the extended type is neither mirror nor impl. | 6 |
| `JavaInteropManager::CheckCJMappingType` | `src/Sema/NativeFFI/Java/AfterTypeCheck/TypeCheckJavaInterop.cpp:436-440` | Return when `IsCJMapping` is false. | 5 |
| `JavaInteropManager::CheckGenericsInstantiation` | `src/Sema/NativeFFI/Java/AfterTypeCheck/EscapeChecks.cpp:86-100` | Walk ordinary declaration nodes; helper paths below collect no Java declarations. | 15 |
| `IsInstantiationWithJavaTypeAllowed(Ty)` | `src/Sema/NativeFFI/Java/AfterTypeCheck/EscapeChecks.cpp:62-65` | Test Option/JArray exception. | 4 |
| `IsInstantiationWithJavaTypeAllowed(NameReferenceExpr)` | `src/Sema/NativeFFI/Java/AfterTypeCheck/EscapeChecks.cpp:67-82` | Test target and outer-declaration types. | 16 |
| `CollectJavaTypes` | `src/Sema/NativeFFI/Java/AfterTypeCheck/EscapeChecks.cpp:24-42` | Recurse through tuple/Option arguments; ordinary types add nothing. | 19 |
| `CollectJavaTypesAndDiag(NameReferenceExpr)` | `src/Sema/NativeFFI/Java/AfterTypeCheck/EscapeChecks.cpp:44-51` | Inspect instantiated types; empty Java collection produces no diagnostic. | 8 |
| `CollectJavaTypesAndDiag(RefType)` | `src/Sema/NativeFFI/Java/AfterTypeCheck/EscapeChecks.cpp:53-60` | Inspect type arguments; empty Java collection produces no diagnostic. | 8 |
| `JavaInteropManager::DesugarPackage` | `src/Sema/NativeFFI/Java/AfterTypeCheck/DesugarPackage.cpp:75-82` | Return because `hasMirrorOrImpl == false` and target language is not Java. | 8 |
| **Java subtotal** | | | **187** |

## Objective-C

| Entity / method | C++ source range | Ordinary-package path | Lines |
|---|---|---|---:|
| `InteropContext::InteropContext` | `src/Sema/NativeFFI/ObjC/AfterTypeCheck/Interop/Context.h:30-43` | Save inputs and construct the bridge/mapper/name/factory carriers. | 14 |
| `InteropLibBridge::InteropLibBridge` | `src/Sema/NativeFFI/ObjC/Utils/InteropLibBridge.h:24-27` | Save import manager and diagnostics. | 4 |
| `TypeMapper::TypeMapper` | `src/Sema/NativeFFI/ObjC/Utils/TypeMapper.h:36-39` | Save bridge and type manager. | 4 |
| `NameGenerator::NameGenerator` | `src/Sema/NativeFFI/ObjC/Utils/NameGenerator.cpp:34-37` | Save mangler and type manager. | 4 |
| `ASTFactory::ASTFactory` | `src/Sema/NativeFFI/ObjC/Utils/ASTFactory.h:39-47` | Save five references; no AST construction occurs. | 9 |
| `GlobalOptions::GetSharedLibraryExtension` | `src/Option/Option.cpp:1251-1264` | Select `.dll`, `.dylib`, or `.so` from target OS. | 14 |
| `ObjC::Desugar` | `src/Sema/NativeFFI/ObjC/AfterTypeCheck/Desugar.cpp:16-20` | Return when `objc.internal` is inaccessible. | 5 |
| `InteropLibBridge::IsInteropLibAccessible()` | `src/Sema/NativeFFI/ObjC/Utils/InteropLibBridge.cpp:596-599` | Delegate to the static overload. | 4 |
| `InteropLibBridge::IsInteropLibAccessible(ImportManager&)` | `src/Sema/NativeFFI/ObjC/Utils/InteropLibBridge.cpp:591-594` | `GetPackageDecl("objc.internal")` is empty for the ordinary package. | 4 |
| **Objective-C subtotal** | | | **54** |
| **Total** | | | **241** |

## Dependency closure pre-scan

Already present in selfhost:

- `InteropLibBridge::{IsInteropLibAccessible, constructor}` —
  `packages/sema/src/NativeFFI/InteropLibBridge.cj:216-239` and
  `packages/sema/src/NativeFFI/ObjC/InteropLibBridge.cj:67-78,251-252`.
- `TypeMapper::TypeMapper` — `packages/sema/src/NativeFFI/ObjC/TypeMapper.cj:81-89`.
- `NameGenerator::NameGenerator` — `packages/sema/src/NativeFFI/ObjC/NameGenerator.cj:22-29`.
- `GlobalOptions::GetSharedLibraryExtension` — `packages/option/src/Option.cj:1068-1076`.
- `IsMirror`, `IsImpl`, and `IsCJMapping` — `packages/ast/src/Utils.cj:976-1017`.
- `MemberMap` and `TypeCheckerImpl::structMemberMap` —
  `packages/sema/src/MemberSignature.cj:68-91` and `packages/sema/src/TypeCheckerImpl.cj:92`.

Zero match in selfhost:

- `ASTFactory` — C++ declaration `src/Sema/NativeFFI/ObjC/Utils/ASTFactory.h:37-284`.
  Only its 9-line constructor is reachable before the ordinary-package ObjC early return. The
  constructor has no missing prerequisite and is included in this lane's explicit no-op skeleton;
  its Java/ObjC-only method surface and bodies remain named feature debt.

The 241-line ordinary no-op skeleton is below the 600-line stop threshold, so phase B applies.
