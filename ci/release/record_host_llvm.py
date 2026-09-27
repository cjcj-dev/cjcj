# Manifest producer used by build-host-llvm.yml.
import hashlib, json, os, sys
from pathlib import Path
root = Path(sys.argv[1])
symbols = (root / 'demangled-symbols.txt').read_text()
if 'llvm::isCJTypedReadHelperCandidate(' in symbols:
    raise SystemExit('HOST_LLVM_COLOUR_SYMBOL_PRESENT')
library = root / os.environ['HOST_LLVM_LIBRARY']
digest = hashlib.sha256(library.read_bytes()).hexdigest()
record = dict(source_sha=os.environ['HOST_LLVM_SOURCE_SHA'],
              run_id=os.environ['GITHUB_RUN_ID'], run_attempt=os.environ['GITHUB_RUN_ATTEMPT'],
              producer_sha=os.environ['GITHUB_SHA'], platform=os.environ['HOST_LLVM_PLATFORM'], sha256=digest)
(root / 'manifest.json').write_text(json.dumps(record, indent=2) + '\n')
(root / 'SHA256SUMS').write_text(digest + '  ' + library.name + '\n')
print(json.dumps(record))
