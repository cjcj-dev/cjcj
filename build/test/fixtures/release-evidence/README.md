Source: GitHub REST repos/cjcj-dev/cjcj/actions/runs/36311262568/jobs (2026-09-30).
Only id/name/conclusion/html_url are retained. This real run FAILED.
The test constructs a hypothetical successful current release: removes the three
OHOS packages no longer in release.yml, expands the eight skipped package callers
with build-release-package.yml's host job name, changes required jobs to success,
and preserves the two optional LLVM skips and Publish release skip. It does not
claim this run completed successfully. Manifests/checksums are synthetic fixtures.
