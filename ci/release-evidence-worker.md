# Private release evidence worker

The GitHub Node contract job installs jq (`.github/workflows/ci.yml`). A private
Linux x64 worker must supply the same real shell prerequisite before running the
contracts; a missing jq is not passing evidence.

Download the upstream jq 1.7.1 Linux amd64 executable into the worker's private
directory (no system installation):

```bash
ulimit -c 0
worker=/root/<full-lane-name>
mkdir -p "$worker/keep"
curl -fL https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64 \
  -o "$worker/keep/jq-linux-amd64"
# From the candidate checkout:
bash ci/release-evidence-worker.sh "$worker/candidate" "$worker/keep/jq-linux-amd64" \
  build/test/release-evidence.test.mjs
```

The entry verifies SHA256
`5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5`
before and after copying the executable, checks `jq-1.7.1`, and exports a private
PATH and persistent `RELEASE_EVIDENCE_TEST_ROOT` to the actual Node/shell consumer.
It prints the selected executable, version and hash. Existing bash, Node and
sha256sum are required. There is no fallback jq implementation.

Omit the trailing test arguments to use the complete source-derived list from
`node ci/test-manifest.mjs list`. Pass Node test options before filenames for a
focused run. Use separate private roots for parallel arms. Preserve each actual
exit code and log; existing failures remain failures. On kkk2 invoke this entry
through `box.sh` and keep all files below `/root/<full-lane-name>/`.
