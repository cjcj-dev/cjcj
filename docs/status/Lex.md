# Lex Port Status

Date: 2026-06-15

Update: 2026-06-17

Build: `cjpm build` passes.

Implemented:

- Replaced the Lex scaffold with a multi-file Cangjie package mirroring the C++ Lex components: token tables, annotation token tables, token/string-part data structures, public `Lexer` wrapper, lexer implementation, and diagnostic helpers.
- Added the Lex package dependency on `cangjie_compiler::basic` so source positions, source buffers, and diagnostic reporting use the ported Basic module.
- Ported the token inventory from `Tokens.inc`, including literals, human-readable token names, operator precedence, experimental-token detection, contextual keywords, and escape-token classification.
- Corrected `GetEscapeTokenKinds` to match the C++ Lex declaration/ParseQuote implementation: quote escapes are `$identifier`, `@`, `$`, `(`, and `)`, not string/rune literal token kinds.
- Implemented real tokenization for whitespace/newlines, operators and punctuation, ambiguous token splitting, keyword lookup with EH keyword gating, identifiers, backquoted/package identifiers, dollar identifiers, integer and floating literals with prefixes/suffixes, comments including nested block comments, rune and byte-rune literals, single-line strings, multi-line strings, raw strings, interpolation string-part collection, lookahead, reset, token-stream collection, and macro-provided token streams.
- Preserved source position tracking with byte offsets and CRLF handling through Basic `Position` and `MakeRange` diagnostics.
- De-isolated Unicode identifier and NFC handling to the real sibling `cangjie_compiler::utils` package, removing Lex-local copies of the Unicode 15.0 XID and normalization tables.
- Rebuilt missing string parts for macro-provided string tokens by recursively lexing synthetic quoted source, matching the C++ `LexerImpl::GetStrParts` strategy.
- Ported C++ multi-byte UTF-8 rejection details for malformed continuation bytes, overlong encodings, malformed-run consumption, and unsafe Unicode security diagnostics.
- Tightened backquoted identifier lexing to scan real identifier parts, package-identifier separators, wildcard diagnostics, and missing-backquote recovery instead of accepting arbitrary backquoted text.
- Aligned backquoted identifier token value/range finalization with C++ by fixing the returned token before recovery scanning consumes trailing malformed text.
- Matched C++ numeric suffix recovery for `.identifier` member access after number literals, including Unicode identifier lookahead and the original adjacency guard for unknown-suffix diagnostics.
- Matched C++ fractional-number classification by only promoting a dotted numeric literal during decimal-part scanning when the first fractional character is an ASCII digit, preserving hex-letter member-access fallback unless an exponent follows.
- Expanded number diagnostic parity for expected/unexpected digit and illegal integer/float suffix cases with C++ main-hint substitutions, contextual hints, and notes.
- Expanded string, rune, byte-rune, unicode-escape, and interpolation diagnostic parity with C++ hints, notes, range choices, unicode scalar validation, escape-note text, rune-overflow help, and byte-literal ASCII checks.
- Normalized identifier token values at the same point as C++ `LexerImpl::ScanIdentifierContinue`, now through `utils.NFC`.
- Aligned `Token` identity with the C++ `Token::operator==`/ordering contract by keying equality and hashing on begin position only, which makes token-stream and string-part maps match the reference's position-based token identity.
- Matched the C++ `Token::Length` precondition checks by asserting same-file and same-line token ranges before computing column length.
- Restored `GetTokenStream` to ordered `TreeSet<Token>` semantics, matching the C++ `std::set<Token>` behavior instead of exposing an unordered hash set.
- Restored C++ public lexer/token constants that the earlier port omitted (`NUM_TOKENS == 200`, UTF-8 byte step/index constants, and shift constants) and padded the precedence table to the exact reference capacity.
- Matched the C++ `ReserveToken` EOF-padding behavior used by `Seeing` instead of stopping after the first `END` token.
- Fixed macro-provided ambiguous-token splitting to preserve the C++ left-token source range while mutating the cached right token for `??`, `>>=`, `>>`, and `>=`.
- Matched C++ invalid composite symbol consumption for `+&=`, `-&=`, `*&=`, and `**&=` so those forms are diagnosed as one illegal token.
- Replaced the remaining peek-only symbol scanner with C++-style per-symbol scan helpers, preserving the reference rollback behavior for invalid partial composites such as `+&x`, `-&x`, `*&x`, and `**&x` as single illegal symbol spans.
- Expanded numeric, unicode-escape, unknown-token, and dollar-identifier diagnostics with the C++ helper behavior: secondary hints, notes, and fix-it substitutions.
- Added C++-style diagnostics for non-ASCII numeric junk, illegal Unicode identifier continuations, and missing multiline/raw-string delimiter hints.
- Reworked string-interpolation hole scanning to mirror the C++ helper split for nested braces, strings, comments, linebreak diagnostics, and raw-string failure propagation.
- Routed non-identifier Unicode token starts through the C++ symbol fallback path so they produce `lex_unknown_start_of_token` behavior instead of Lex-local unrecognized-symbol handling.
- Matched the C++ dedicated identifier-continuation UTF-8 recovery path: malformed multibyte continuation scans now consume only the offending byte and report `lex_illegal_unicode`, instead of using the general UTF-8 reader that can absorb the following ASCII byte.
- Aligned numeric exponent/suffix diagnostics with C++ by anchoring exponent digit scanning at the exponent marker and preserving the reference `success` state after unknown-suffix reporting.
- Tightened `GetStrParts` to assert string-token kinds and require scanned string-part map entries just like C++, while still rebuilding macro-provided string tokens through a temporary lexer.
- Delegated current-character diagnostic rendering to Basic `ConvertChar` after newline detection, matching C++ handling for EOF and control characters.
- Preserved the C++ lexer `success` state for illegal Unicode scalar escape diagnostics and unexpected dollar-keyword diagnostics instead of treating those recoverable diagnostics as scan failure.
- Matched C++ lexer context-stack preconditions by asserting quote/normal mode exits and quote-context reads instead of silently ignoring mismatched state, and restored the string-dispatch quote assertion.
- Reworked Lex `ProcessQuotaMarks` to preserve raw UTF-8 bytes while applying the C++ quote/interpolation transform, and restored the C++ assertion for nested interpolation string scanning.

Known validation caveats:

- Diagnostics report through the same Basic diagnostic IDs, but rendered diagnostic-output parity still needs validation against the C++ Lex test corpus.
- The implementation is behavior-bearing and buildable; focused ad hoc checks exercise identifier NFC normalization, but this Cangjie workspace currently has no executable Lex test corpus (`cjpm test` reports 0 tests).

Remaining Lex selfhost markers: 0.
