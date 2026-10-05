#!/usr/bin/env python3
"""Mutate one real product bearing point in an isolated compiler source tree."""
import argparse
import difflib
from pathlib import Path


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('tree',type=Path)
    p.add_argument('--kind',choices=['lambda-producer','lambda-consumer','raw-producer','raw-consumer','export-producer','export-consumer'],required=True)
    p.add_argument('--diff',type=Path,required=True)
    a=p.parse_args()
    relative='packages/mangle/src/BaseMangler.cj'
    if a.kind=='lambda-consumer': relative='packages/frontend/src/CompilerInstance.cj'
    if a.kind=='raw-producer': relative='packages/mangle/src/ASTMangler.cj'
    if a.kind=='raw-consumer': relative='packages/incremental_compilation/src/ASTCacheCalculator.cj'
    path=a.tree/relative;original=path.read_text();text=original
    suffix=' + (if (decl.identifier.Val() == "acceptRawType") { "$cut" } else { "" })'
    if a.kind=='lambda-producer':
        start=text.index('    public func MangleLambda(lambda: LambdaExpr,')
        offset=text.index('return CJMangledCompression(mangleStr)',start)
        before='return CJMangledCompression(mangleStr)'
        text=text[:offset]+text[offset:].replace(before,before+' + "$cut"',1)
    elif a.kind=='lambda-consumer':
        before='                        lambda.mangledName = mangledName'
        assert text.count(before)==1
        text=text.replace(before,before+' + "$cut"')
    elif a.kind=='raw-producer':
        before='    var mangledName = MangleName(typeAnnotation.ref.identifier.Val())'
        assert text.count(before)==1
        text=text.replace(before,before+' + (if (typeAnnotation.ref.identifier.Val() == "type") { "$cut" } else { "" })')
    elif a.kind=='raw-consumer':
        before='        decl.rawMangleName = mangler.Mangle(decl)'
        assert text.count(before)==3
        text=text.replace(before,before+suffix)
    elif a.kind=='export-producer':
        start=text.index('    public func MangleExportId(decl: Decl)')
        offset=text.index('return decl.exportId',start)
        before='return decl.exportId'
        text=text[:offset]+text[offset:].replace(before,before+suffix,1)
    else:
        before='                    decl.exportId = MangleExportId(decl)'
        assert text.count(before)==1
        text=text.replace(before,before+suffix)
    assert text!=original
    path.write_text(text)
    a.diff.write_text(''.join(difflib.unified_diff(original.splitlines(True),text.splitlines(True),fromfile='a/'+relative,tofile='b/'+relative)))


if __name__=='__main__':main()
