// The runtime provenance (GenerateRuntimeProvenance.cmake) runs `git status
// --porcelain` on the runtime checkout. actions/checkout wrote that checkout
// with Git for Windows (core.autocrlf=true); MSYS2's /usr/bin/git
// (core.autocrlf=false) sees every CRLF file as modified and the stamp becomes
// <sha>-dirty (run 45401980497). Fail before build.py unless git is Git for
// Windows, and print the porcelain status the provenance step will see.
export function windowsRuntimeGitGuard(sourceVar = 'runtime_source') {
  return [
    'runtime_git="$(command -v git)"',
    'runtime_git_version="$(git --version)"',
    'echo "RUNTIME_SOURCE_GIT=$runtime_git $runtime_git_version"',
    'case "$runtime_git_version" in *.windows.*) ;; *) echo "FATAL: runtime provenance needs Git for Windows, PATH selects $runtime_git ($runtime_git_version)" >&2; exit 5;; esac',
    'echo "RUNTIME_SOURCE_STATUS_BEGIN"',
    // Mixed D:/a/... path: Git for Windows must not depend on MSYS argv conversion.
    `git -C "$(cygpath -m "$${sourceVar}")" status --porcelain`,
    'echo "RUNTIME_SOURCE_STATUS_END"',
  ];
}
