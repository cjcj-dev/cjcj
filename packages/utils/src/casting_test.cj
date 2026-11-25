package cjcj::utils

// PORT-DEFERRED: Utils/CastASTTests.VerifyCastingCount, VerifyMonoCasting, VerifyIntermediateCasting,
// TryAddNewType, and VerifyStaticCasting require the C++ ASTCasting template/RTTI surface from
// cangjie_compiler/include/cangjie/AST/ASTCasting.h:24 and :57; package utils cannot depend
// on downstream package ast to construct the tested AST nodes.
// PORT-DEFERRED: Utils/CastTyTests.VerifyCastingCount, VerifyMonoCasting, and VerifyIntermediateCasting require
// the C++ AST Ty casting template surface from cangjie_compiler/include/cangjie/AST/ASTCasting.h:31
// and :65; package utils cannot depend on downstream package ast/sema type owners.
