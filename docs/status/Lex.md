# Lex Port Status

Date: 2026-06-15

Build: `cjpm build` passes.

Implemented:

- Replaced the Lex scaffold with a multi-file Cangjie package mirroring the C++ Lex components: token tables, annotation token tables, token/string-part data structures, public `Lexer` wrapper, lexer implementation, and diagnostic helpers.
- Added the Lex package dependency on `cangjie_compiler::basic` so source positions, source buffers, and diagnostic reporting use the ported Basic module.
- Ported the token inventory from `Tokens.inc`, including literals, human-readable token names, operator precedence, experimental-token detection, contextual keywords, and escape-token classification.
- Implemented real tokenization for whitespace/newlines, operators and punctuation, ambiguous token splitting, keyword lookup with EH keyword gating, identifiers, backquoted/package identifiers, dollar identifiers, integer and floating literals with prefixes/suffixes, comments including nested block comments, rune and byte-rune literals, single-line strings, multi-line strings, raw strings, interpolation string-part collection, lookahead, reset, token-stream collection, and macro-provided token streams.
- Preserved source position tracking with byte offsets and CRLF handling through Basic `Position` and `MakeRange` diagnostics.
- Replaced the permissive Unicode identifier handling with local Unicode 15.0 `XID_Start`, Cangjie `_` start, and `XID_Continue` range tables mirrored from the C++ `Utils/Unicode.cpp` implementation.
- Rebuilt missing string parts for macro-provided string tokens by recursively lexing synthetic quoted source, matching the C++ `LexerImpl::GetStrParts` strategy.

Known fidelity caveats:

- Identifier NFC normalization is not yet byte-for-byte equivalent to the C++ `Unicode::NFC` path because the Utils module is not ported as a dependency of Lex in this worktree.
- Diagnostics report through the same Basic diagnostic IDs, but several rich hint/help branches from `LexerDiag.cpp` are simplified pending a full diagnostic-detail pass.
- The implementation is behavior-bearing and buildable, but it has not yet been validated against the C++ Lex unit test corpus.

Remaining Lex selfhost markers: 0.
