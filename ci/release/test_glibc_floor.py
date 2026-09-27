"""Real ELF / real CLI checks; run on a Linux builder, not with readelf stubs."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCANNER = Path(__file__).with_name("glibc_floor.py")
SCOPES = ("bin", "tools/bin", "runtime/lib", "third_party/llvm/bin")


class GlibcFloorTest(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix="glibc-floor-", dir=os.environ.get("GLIBC_TEST_TMPDIR"))
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.official = self.root / "official"
        self.candidate = self.root / "candidate"
        for scope in SCOPES:
            (self.official / scope).mkdir(parents=True)
        low = self.root / "low.c"
        low.write_text('#include <stdio.h>\nint entry(void) { return puts("old ABI"); }\n')
        high = self.root / "high.c"
        high.write_text('#include <unistd.h>\nint entry(void) { char b; return getentropy(&b, 1); }\n')
        self.low = self.root / "low.so"
        self.high = self.root / "high.so"
        for source, output in ((low, self.low), (high, self.high)):
            subprocess.run(["cc", "-shared", "-fPIC", str(source), "-o", str(output)], check=True)
        for scope in SCOPES:
            shutil.copyfile(self.low, self.official / scope / "payload")
        shutil.copytree(self.official, self.candidate)

    def run_gate(self):
        destination = self.root / "report.json"
        process = subprocess.run([
            sys.executable, str(SCANNER), "--candidate", str(self.candidate),
            "--official", str(self.official), "--json", str(destination),
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        report = json.loads(destination.read_text())
        print("CLI_RESULT {} rc={} elf={} failures={}".format(
            self._testMethodName, process.returncode, report.get("elf_count"), report["failures"]), flush=True)
        print("CLI_REPORT " + json.dumps(report, sort_keys=True), flush=True)
        return process.returncode, report

    def test_same_elf_passes_and_identity_is_recorded(self):
        rc, report = self.run_gate()
        self.assertEqual(rc, 0, report)
        self.assertEqual(report["elf_count"], 4)
        expected = hashlib.sha256(self.low.read_bytes()).hexdigest()
        self.assertTrue(all(row["candidate"]["sha256"] == expected for row in report["files"]))

    def test_higher_requirement_rejected_in_each_scope(self):
        # The result of the actual scanner enters the target assertion. Each
        # independent scope gets exactly one rejected file; no early presence
        # assertion can hide the per-file verdict below.
        for scope in SCOPES:
            with self.subTest(scope=scope):
                target = scope + "/payload"
                shutil.copyfile(self.high, self.candidate / target)
                try:
                    rc, report = self.run_gate()
                    observed = [(row["path"], row["status"]) for row in report["files"] if row["status"] != "accepted"]
                    print("TARGET_ABI_ASSERT scope={} rc={} verdict={}".format(scope, rc, observed), flush=True)
                    self.assertEqual((rc, observed), (1, [(target, "rejected")]))
                finally:
                    shutil.copyfile(self.low, self.candidate / target)

    def test_missing_official_counterpart_fails_closed(self):
        (self.official / "bin/payload").unlink()
        rc, report = self.run_gate()
        self.assertEqual((rc, report["failures"]), (1, ["bin/payload"]))

    def test_missing_scope_fails_closed(self):
        shutil.rmtree(self.candidate / "tools/bin")
        rc, report = self.run_gate()
        self.assertEqual((rc, report["failures"]), (1, ["tools/bin"]))

    def test_non_elf_cannot_replace_official_elf(self):
        (self.candidate / "bin/payload").write_text("#!/bin/sh\nexit 0\n")
        rc, report = self.run_gate()
        self.assertEqual((rc, report["failures"]), (1, ["bin/payload"]))

    def test_non_elf_cross_target_files_are_recorded(self):
        (self.candidate / "runtime/lib/windows.dll").write_bytes(b"MZ\x00\x00")
        rc, report = self.run_gate()
        self.assertEqual(rc, 0, report)
        self.assertEqual(next(row["status"] for row in report["files"] if row["path"].endswith("windows.dll")), "not-elf")

    def test_corrupt_elf_fails_closed(self):
        (self.candidate / "bin/payload").write_bytes(b"\x7fELF")
        rc, report = self.run_gate()
        self.assertEqual((rc, report["failures"]), (1, ["bin/payload"]))

    def test_foreign_architecture_is_not_abi_evidence(self):
        file = self.candidate / "bin/payload"
        data = bytearray(file.read_bytes())
        # readelf reads version needs for either machine; the gate must still
        # reject a counterpart from the wrong target architecture.
        data[18:20] = (183 if int.from_bytes(data[18:20], "little") != 183 else 62).to_bytes(2, "little")
        file.write_bytes(data)
        rc, report = self.run_gate()
        self.assertEqual((rc, report["failures"]), (1, ["bin/payload"]))

    def test_exported_glibc_version_is_not_a_requirement(self):
        versions = self.root / "exports.map"
        versions.write_text("GLIBC_999.0 { global: entry; local: *; };\n")
        subprocess.run([
            "cc", "-shared", "-fPIC", str(self.root / "low.c"),
            "-Wl,--version-script=" + str(versions), "-o", str(self.candidate / "bin/payload"),
        ], check=True)
        rc, report = self.run_gate()
        self.assertEqual(rc, 0, report)
        row = next(row for row in report["files"] if row["path"] == "bin/payload")
        self.assertNotIn("GLIBC_999.0", row["candidate"]["needs"])

    def test_empty_payload_is_not_a_pass(self):
        for root in (self.candidate, self.official):
            for scope in SCOPES:
                (root / scope / "payload").unlink()
        rc, report = self.run_gate()
        self.assertEqual((rc, report["failures"]), (1, ["no ELF payload inspected"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
