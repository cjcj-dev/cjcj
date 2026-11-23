#!/usr/bin/env zx
// mvdan/sh typed JSON preserves the original Bash byte ranges, including glob
// conditions that tree-sitter-bash 0.23.3 and 0.25.1 reject. No source rewriting.
import {spawnSync} from 'node:child_process';
export const parserVersion = 'v3.12.0';
export function exportBranches(source, binary = process.env.CJCJ_BASH_AST_PARSER || 'shfmt') {
  const result = spawnSync(binary, ['-ln', 'bash', '--to-json'], {input: source, encoding: 'utf8', maxBuffer: 16*1024*1024});
  if (result.error || result.status !== 0) throw new SyntaxError(`Bash AST parser rc=${result.status}: ${result.error?.message || result.stderr}`);
  const ast = JSON.parse(result.stdout);
  if (ast.Type !== 'File' || !ast.Stmts.every(stmt => stmt.Cmd?.Type)) throw new Error('Incomplete typed Bash AST');
  const bytes = Buffer.from(source), rows = [];
  const text = node => bytes.subarray(node.Pos.Offset, node.End.Offset).toString();
  function add(node, kind, detail = {}) {
    rows.push({kind, line: node.Pos.Line, column: node.Pos.Col-1, start: node.Pos.Offset,
      end: node.End.Offset, source: text(node), scope: [], ...detail});
  }
  function walk(node, scope = [], field) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { for (const child of node) walk(child, scope, field); return; }
    const nested = node.Type === 'FuncDecl' ? [...scope, node.Name.Value] : scope;
    if (node.Type === 'ParamExp' && node.Exp) {
      // Operator text comes from the parser's exact token boundaries, not a
      // regex over shell source. Preserve enum and complete AST for inspection.
      // Empty error/default words are omitted by mvdan; Rbrace is still a
      // parser-owned token boundary. Never rewrite or regex-guess Bash syntax.
      const operatorEnd = node.Exp.Word?.Pos.Offset ?? node.Rbrace.Offset;
      const operator = bytes.subarray(node.Param.End.Offset, operatorEnd).toString();
      const variable = node.Param.Value, position = Number(variable);
      add(node, operator.includes('?') ? 'required' : 'parameter', {scope: nested, variable, operator,
        operatorEnum: node.Exp.Op, ...(Number.isInteger(position)&&position>0?{position}:{}),
        outcomes: operator.startsWith(':')?['unset','empty','set']:['unset','set']});
    }
    if (['IfClause','BinaryTest','UnaryTest','TestClause'].includes(node.Type))
      add(node,'condition',{scope:nested,astType:node.Type,operatorEnum:node.Op,outcomes:['true','false']});
    if (['ForClause','WhileClause'].includes(node.Type)) add(node,'loop',{scope:nested,outcomes:['iteration','completion']});
    if (node.Type==='CaseClause') add(node,'case',{scope:nested,outcomes:['selected','not-selected']});
    if (node.Type==='BinaryCmd') add(node,'binary-command',{scope:nested,operatorEnum:node.Op,outcomes:['success','failure']});
    if (node.Type==='CallExpr' && node.Args?.length) add(node,'command',{scope:nested,
      name:text(node.Args[0]),arguments:node.Args.slice(1).map(text),outcomes:['success','failure']});
    if (field==='Redirs') add(node,'redirection',{scope:nested,operatorEnum:node.Op,outcomes:['success','failure']});
    for (const [key,value] of Object.entries(node)) {
      if (['Pos','End','Comments','Last','Redirs'].includes(key)) continue;
      if (value && typeof value==='object') walk(value,nested,key);
    }
    for (const redirect of node.Redirs??[]) walk(redirect,nested,'Redirs');
  }
  walk(ast);
  return {ast,rows};
}

// Required env cases come from the typed AST; later native manifest inputs
// remain visible but cannot be reached without a qualified native build.
export function expandEnvironment(rows, baseline) {
  return rows.flatMap(row => row.outcomes.map(outcome => {
    const item = {entry: row.entry, line: row.line, kind: row.kind, variable: row.variable, outcome};
    const reachable = row.entry === 'fetch_sources' || ['TUPLE_ROOT', 'TUPLE_PLATFORM', 'LLVM_TARGETS'].includes(row.variable);
    if (row.kind !== 'required' || !baseline[row.entry] || row.scope.length || !reachable)
      return {...item, status: 'NOT_RUN', reason: 'explicit lifecycle materializer or native build required'};
    const env = {...baseline[row.entry]};
    if (outcome === 'unset') delete env[row.variable];
    else if (outcome === 'empty') env[row.variable] = '';
    return {...item, env, status: 'READY'};
  }));
}
