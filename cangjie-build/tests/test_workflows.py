from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_platform_specific_scripts_are_prefixed() -> None:
    scripts = {path.name for path in (ROOT / ".github" / "scripts").glob("*.sh")}
    workflows = "\n".join(
        _read(path)
        for path in (
            ".github/workflows/build-cangjie-azure.yml",
            ".github/workflows/build-cangjie-gcp.yml",
            ".github/workflows/reap-orphans.yml",
        )
    )

    assert "azure-provision-vm.sh" in scripts
    assert "azure-teardown.sh" in scripts
    assert "azure-reap-orphans.sh" in scripts
    assert "gcp-provision-vm.sh" in scripts
    assert "gcp-teardown.sh" in scripts
    assert "gcp-reap-orphans.sh" in scripts

    assert "provision-vm.sh" not in scripts
    assert "teardown.sh" not in scripts
    assert "reap-orphans.sh" not in scripts
    assert ".github/scripts/azure-provision-vm.sh" in workflows
    assert ".github/scripts/azure-teardown.sh" in workflows
    assert ".github/scripts/azure-reap-orphans.sh" in workflows
    assert ".github/scripts/provision-vm.sh" not in workflows
    assert ".github/scripts/teardown.sh" not in workflows
    assert ".github/scripts/reap-orphans.sh" not in workflows


def test_gcp_provision_does_not_write_gcloud_output_to_github_outputs() -> None:
    script = _read(".github/scripts/gcp-provision-vm.sh")

    assert "-o none" not in script
    assert "--quiet >/dev/null" in script
