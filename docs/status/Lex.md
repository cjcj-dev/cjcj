# Lex Port Status

Date: 2026-06-15

Update: 2026-06-16

Build: `cjpm build` passes.

Implemented:

- Replaced the Lex scaffold with a multi-file Cangjie package mirroring the C++ Lex components: token tables, annotation token tables, token/string-part data structures, public `Lexer` wrapper, lexer implementation, and diagnostic helpers.
- Added the Lex package dependency on `cangjie_compiler::basic` so source positions, source buffers, and diagnostic reporting use the ported Basic module.
- Ported the token inventory from `Tokens.inc`, including literals, human-readable token names, operator precedence, experimental-token detection, contextual keywords, and escape-token classification.
- Implemented real tokenization for whitespace/newlines, operators and punctuation, ambiguous token splitting, keyword lookup with EH keyword gating, identifiers, backquoted/package identifiers, dollar identifiers, integer and floating literals with prefixes/suffixes, comments including nested block comments, rune and byte-rune literals, single-line strings, multi-line strings, raw strings, interpolation string-part collection, lookahead, reset, token-stream collection, and macro-provided token streams.
- Preserved source position tracking with byte offsets and CRLF handling through Basic `Position` and `MakeRange` diagnostics.
- Replaced the permissive Unicode identifier handling with local Unicode 15.0 `XID_Start`, Cangjie `_` start, and `XID_Continue` range tables mirrored from the C++ `Utils/Unicode.cpp` implementation.
- Rebuilt missing string parts for macro-provided string tokens by recursively lexing synthetic quoted source, matching the C++ `LexerImpl::GetStrParts` strategy.
- Ported C++ multi-byte UTF-8 rejection details for malformed continuation bytes, overlong encodings, malformed-run consumption, and unsafe Unicode security diagnostics.
- Tightened backquoted identifier lexing to scan real identifier parts, package-identifier separators, wildcard diagnostics, and missing-backquote recovery instead of accepting arbitrary backquoted text.
- Matched C++ numeric suffix recovery for `.identifier` member access after number literals, including Unicode identifier lookahead and the original adjacency guard for unknown-suffix diagnostics.
- Expanded number diagnostic parity for expected/unexpected digit and illegal integer/float suffix cases with C++ main-hint substitutions, contextual hints, and notes.
- Expanded string, rune, byte-rune, unicode-escape, and interpolation diagnostic parity with C++ hints, notes, range choices, unicode scalar validation, escape-note text, rune-overflow help, and byte-literal ASCII checks.
- Added Lex-local Unicode 15.0 NFC canonical decomposition/recomposition data and logic, and normalized identifier token values at the same point as C++ `LexerImpl::ScanIdentifierContinue`.
- Aligned `Token` identity with the C++ `Token::operator==`/ordering contract by keying equality and hashing on begin position only, which makes token-stream and string-part maps match the reference's position-based token identity.
- Restored C++ public lexer/token constants that the earlier port omitted (`NUM_TOKENS == 200`, UTF-8 byte step/index constants, and shift constants) and padded the precedence table to the reference capacity.
- Matched the C++ `ReserveToken` EOF-padding behavior used by `Seeing` instead of stopping after the first `END` token.
- Fixed macro-provided ambiguous-token splitting to preserve the C++ left-token source range while mutating the cached right token for `??`, `>>=`, `>>`, and `>=`.
- Matched C++ invalid composite symbol consumption for `+&=`, `-&=`, `*&=`, and `**&=` so those forms are diagnosed as one illegal token.
- Expanded numeric, unicode-escape, unknown-token, and dollar-identifier diagnostics with the C++ helper behavior: secondary hints, notes, and fix-it substitutions.
- Added C++-style diagnostics for non-ASCII numeric junk, illegal Unicode identifier continuations, and missing multiline/raw-string delimiter hints.
- Reworked string-interpolation hole scanning to mirror the C++ helper split for nested braces, strings, comments, linebreak diagnostics, and raw-string failure propagation.
- Routed non-identifier Unicode token starts through the C++ symbol fallback path so they produce `lex_unknown_start_of_token` behavior instead of Lex-local unrecognized-symbol handling.

Known validation caveats:

- Diagnostics report through the same Basic diagnostic IDs, but rendered diagnostic-output parity still needs validation against the C++ Lex test corpus.
- The implementation is behavior-bearing and buildable; focused ad hoc checks exercise identifier NFC normalization, but this Cangjie workspace currently has no executable Lex test corpus (`cjpm test` reports 0 tests).

Remaining Lex selfhost markers: 0.
