#!/usr/bin/env zx
// Parse the retired language, including nested expansions and opaque here-docs.
// Inventory and execution consume the same expansion. Unsupported materializers
// remain explicit NOT_RUN records; a syntax tree alone is not coverage evidence.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import Parser from './g1-parser/node_modules/tree-sitter/index.js';
import Bash from './g1-parser/node_modules/tree-sitter-bash/bindings/node/index.js';

export const baseline = 'a65c82b648b32f9f3fcbeaf9cb84825852129af3';
const parser = new Parser();
parser.setLanguage(Bash);
const field = (node, name) => node.childForFieldName(name);
const namedFields = (node, name) => node.children.filter((child, i) =>
  child.isNamed && node.fieldNameForChild(i) === name);
const anchor = node => ({line: node.startPosition.row + 1, column: node.startPosition.column,
  start: node.startIndex, end: node.endIndex, source: node.text});
const expr = node => node ? {type: node.type, text: node.text,
  children: node.namedChildren.map(expr)} : undefined;

export function exportBranches(source) {
  const tree = parser.parse(source);
  {
    if (tree.rootNode.hasError) throw new SyntaxError(`Bash parse failed: ${tree.rootNode}`);
    const rows = [];
    function add(node, kind, detail = {}) { rows.push({kind, ...anchor(node), ...detail}); }
    function walk(node, scope = []) {
      // The grammar treats quoted here-doc bodies as opaque text. In an
      // unquoted body, its actual shell expansions must still be visited.
      if (node.type === 'comment') return;
      const nextScope = node.type === 'function_definition'
        ? [...scope, field(node, 'name').text] : scope;
      if (node.type === 'expansion') {
        const operator = field(node, 'operator')?.text;
        if (operator && [':-', '-', ':?', '?', ':+', '+', ':=', '='].includes(operator)) {
          const variable = node.namedChildren[0].text;
          const position = Number(variable);
          const binding = node.parent.type === 'variable_assignment' ? field(node.parent, 'name').text : undefined;
          const operatorNode = field(node, 'operator');
          const activation = [];
          for (let parent = node.parent; parent; parent = parent.parent) {
            if (parent.type === 'expansion') activation.push({variable: parent.namedChildren[0].text,
              operator: field(parent, 'operator')?.text});
          }
          add(node, operator.includes('?') ? 'required' : 'parameter', {variable, operator,
            ...(Number.isInteger(position) && position > 0 ? {position} : {}), binding, activation, scope: nextScope,
            fallback: node.namedChildren.filter(child => child.startIndex >= operatorNode.endIndex).map(expr),
            outcomes: operator.startsWith(':') ? ['unset', 'empty', 'set'] : ['unset', 'set']});
        }
      }
      if (['if_statement', 'elif_clause', 'while_statement'].includes(node.type))
        add(node, 'condition', {scope: nextScope, condition: namedFields(node, 'condition').map(expr), outcomes: ['true', 'false']});
      if (node.type === 'case_item')
        add(node, 'case', {scope: nextScope, patterns: namedFields(node, 'value').map(expr), outcomes: ['selected', 'not-selected']});
      if (node.type === 'for_statement')
        add(node, 'loop', {scope: nextScope, variable: field(node, 'variable')?.text,
          values: namedFields(node, 'value').map(expr), outcomes: ['iteration', 'completion']});
      if (node.type === 'list') {
        const operators = node.children.filter(child => ['&&', '||'].includes(child.type)).map(child => child.type);
        if (operators.length) add(node, 'short-circuit', {scope: nextScope, operators, outcomes: ['success', 'failure']});
      }
      if (node.type === 'test_command' || (node.type === 'command' && field(node, 'name')?.text === 'test'))
        add(node, 'test', {scope: nextScope, expression: expr(node), outcomes: ['success', 'failure']});
      if (node.type === 'command' && !['exit', 'return', 'test'].includes(field(node, 'name')?.text))
        add(node, 'command', {scope: nextScope, name: field(node, 'name')?.text,
          arguments: namedFields(node, 'argument').map(expr), outcomes: ['success', 'failure']});
      if (['file_redirect', 'herestring_redirect', 'heredoc_redirect'].includes(node.type))
        add(node, 'redirection', {scope: nextScope, expression: expr(node), outcomes: ['success', 'failure']});
      if (node.type === 'command' && ['exit', 'return'].includes(field(node, 'name')?.text))
        add(node, 'exit', {scope: nextScope, arguments: namedFields(node, 'argument').map(expr), outcomes: ['reached']});
      for (const child of node.namedChildren) walk(child, nextScope);
    }
    walk(tree.rootNode);
    const bindings = new Map(rows.filter(row => row.binding && !row.scope.length).map(row => [row.binding, row]));
    function parameter(node) {
      if (node.type === 'expansion') {
        const variable = node.children[0]?.text;
        const position = Number(variable);
        return {variable, ...(Number.isInteger(position) && position > 0 ? {position} : {})};
      }
      if (node.type === 'simple_expansion') {
        const bound = bindings.get(node.children[0]?.text);
        return bound && {variable: bound.variable, position: bound.position};
      }
      return node.children.length === 1 ? parameter(node.children[0]) : undefined;
    }
    for (const row of rows) {
      const expression = row.kind === 'condition' ? row.condition[0] : row.kind === 'test' ? row.expression : undefined;
      const unary = expression?.children.find(child => child.type === 'unary_expression');
      if (unary?.children[0]?.text === '-n') row.nonemptyParameter = parameter(unary.children[1]);
    }
    return rows;
  }
}

export function inventory(directory = new URL('./fixtures/g1/', import.meta.url)) {
  return fs.readdirSync(directory).filter(name => name.endsWith('.bash.txt')).sort().flatMap(name => {
    const source = fs.readFileSync(new URL(name, directory instanceof URL ? directory : `file://${path.resolve(directory)}/`), 'utf8');
    const entry = `ci/${name.slice(0, -'.bash.txt'.length)}.mjs`;
    return exportBranches(source).map(row => ({entry, baseline:entry==='ci/test-llvm-tuple-layout.mjs'?'87fea61097486afac68f310d36d5a05148649780':baseline, ...row}));
  });
}

// Arguments must be real prepared inputs supplied by the caller. Never emit
// $ARG placeholders or invent a source/SDK/ELF to make a branch appear covered.
export function expandInputs(rows, inputs) {
  return rows.flatMap(row => row.outcomes.map(outcome => {
    const base = inputs[row.entry];
    const record = {entry: row.entry, kind: row.kind, line: row.line, start: row.start, outcome};
    if (!base) return {...record, status: 'NOT_RUN', reason: 'entry inputs not prepared'};
    if (row.scope.length) return {...record, status: 'NOT_RUN', reason: 'function-local branch needs caller state'};
    const selector = row.nonemptyParameter || row;
    const state = row.nonemptyParameter ? (['true', 'success'].includes(outcome) ? 'set' : 'empty') : outcome;
    if (selector.position && (row.nonemptyParameter || ['required', 'parameter'].includes(row.kind))) {
      const args = [...base.args];
      if (state === 'unset') args.splice(selector.position - 1);
      else if (state === 'empty') args[selector.position - 1] = '';
      else if (!args[selector.position - 1])
        return {...record, status: 'NOT_RUN', reason: 'set positional input not prepared'};
      if (Array.from(args).some(value => typeof value !== 'string'))
        throw new Error(`incomplete positional inputs: ${row.entry}`);
      return {...record, args, env: {...base.env}, status: 'READY'};
    }
    if (row.kind === 'parameter' && !row.position && !row.binding) {
      const args = [...base.args], env = {...base.env};
      for (const parent of row.activation) {
        if (![':-', '-'].includes(parent.operator))
          return {...record, status: 'NOT_RUN', reason: 'unsupported enclosing expansion activation'};
        const position = Number(parent.variable);
        if (Number.isInteger(position) && position > 0) args.splice(position - 1);
        else delete env[parent.variable];
      }
      if (outcome === 'unset') delete env[row.variable];
      else if (outcome === 'empty') env[row.variable] = '';
      else if (!env[row.variable])
        return {...record, status: 'NOT_RUN', reason: 'set environment input not prepared'};
      return {...record, args, env, unsetEnv: [row.variable, ...row.activation.map(parent => parent.variable)]
        .filter(variable => !Number.isInteger(Number(variable)) && !(variable in env)), status: 'READY'};
    }
    return {...record, status: 'NOT_RUN', reason: 'branch requires filesystem/process state materializer'};
  }));
}

const entryIndex = process.argv.findIndex((arg, index) => index > 0 && path.resolve(arg) === fileURLToPath(import.meta.url));
if (entryIndex > 0) {
  const files = process.argv.slice(entryIndex + 1);
  const rows = files.length ? files.flatMap(file =>
    exportBranches(fs.readFileSync(file, 'utf8')).map(row => ({file, ...row}))) : inventory();
  console.log(JSON.stringify(rows, null, 2));
}
