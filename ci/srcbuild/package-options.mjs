// The compile-option a package declares in its cjpm.toml, as an argument list.
//
// Only the forms the repository's manifests use are accepted, and everything
// else is rejected rather than read as "no options": the key must sit in the
// [package] table and hold a single-line TOML basic ("...") or literal ('...')
// string, optionally followed by a comment. The decoded string is split on
// whitespace; a "double" or 'single' quoted argument stays one argument, the
// syntax ci/release/trimpath.mjs reads and writes (double quotes there are
// JSON-encoded). A missing key or an empty string means no options.
export function packageCompileOptions(manifest, source = 'cjpm.toml') {
  const fail = why => {
    throw new Error(`${source}: [package] compile-option ${why}`);
  };
  let table = '';
  let value;
  for (const [index, raw] of manifest.split(/\r?\n/).entries()) {
    const line = raw.trim();
    if (line === '' || line.startsWith('#')) continue;
    const header = line.match(/^\[(\[?)\s*([A-Za-z0-9_.-]+)\s*\]\1\s*(?:#.*)?$/);
    if (header) {
      table = header[1] ? `[${header[2]}]` : header[2];
      continue;
    }
    if (table === '' && /^package\s*\.\s*compile-option\s*=/.test(line)) {
      fail(`as a dotted key on line ${index + 1} is not supported`);
    }
    if (table !== 'package') continue;
    const entry = line.match(/^(?:compile-option|"compile-option"|'compile-option')\s*=\s*(.*)$/);
    if (!entry) continue;
    if (value !== undefined) fail(`is defined again on line ${index + 1}`);
    value = decodeString(entry[1], why => fail(`on line ${index + 1} ${why}`));
  }
  return splitArguments(value ?? '', fail);
}

const BASIC_ESCAPES = {b: '\b', t: '\t', n: '\n', f: '\f', r: '\r', '"': '"', '\\': '\\'};

function decodeString(text, fail) {
  let body;
  let rest;
  if (text.startsWith('"""') || text.startsWith("'''")) {
    fail('is a multi-line string, which is not supported');
  } else if (text.startsWith('"')) {
    const match = text.match(/^"((?:[^"\\]|\\.)*)"(.*)$/);
    if (!match) fail('is an unterminated string');
    body = match[1].replace(/\\(?:u([0-9A-Fa-f]{4})|U([0-9A-Fa-f]{8})|(.))/g, (all, short, long, single) => {
      if (single !== undefined) {
        if (!Object.hasOwn(BASIC_ESCAPES, single)) fail(`has an invalid escape ${all}`);
        return BASIC_ESCAPES[single];
      }
      const code = parseInt(short ?? long, 16);
      if (code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)) fail(`has an invalid escape ${all}`);
      return String.fromCodePoint(code);
    });
    rest = match[2];
  } else if (text.startsWith("'")) {
    const match = text.match(/^'([^']*)'(.*)$/);
    if (!match) fail('is an unterminated string');
    [, body, rest] = match;
  } else {
    fail(`must be a string, found ${JSON.stringify(text)}`);
  }
  if (!/^\s*(?:#.*)?$/.test(rest)) fail(`has unexpected text after the string: ${JSON.stringify(rest.trim())}`);
  return body;
}

function splitArguments(options, fail) {
  const argument = /\s*(?:"((?:[^"\\]|\\.)*)"|'([^']*)'|([^\s"']+))(?=\s|$)/y;
  const result = [];
  let at = 0;
  while (!/^\s*$/.test(options.slice(at))) {
    argument.lastIndex = at;
    const match = argument.exec(options);
    if (!match) fail(`has unsupported quoting near ${JSON.stringify(options.slice(at).trim())}`);
    if (match[1] !== undefined) {
      try {
        result.push(JSON.parse(`"${match[1]}"`));
      } catch {
        fail(`has an invalid escape in the argument "${match[1]}"`);
      }
    } else {
      result.push(match[2] ?? match[3]);
    }
    at = argument.lastIndex;
  }
  return result;
}
