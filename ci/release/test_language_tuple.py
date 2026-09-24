"""Contract tests for the packaging device; fixtures are not qualified SDKs."""
import argparse
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest

import language_tuple as product


class LanguageTupleTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.sdk = self.root / "input/sdk"
        self.host = self.root / "input/host/runtime/lib" / product.TUPLE
        for directory in ("bin", "include", "lib", "modules", "runtime", "third_party", "tools"):
            (self.sdk / directory).mkdir(parents=True, exist_ok=True)
        for role, relative in product.ROLES.items():
            file = self.root / "input" / relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(f"synthetic device fixture: {role}\n")
            file.chmod(0o755)
        (self.sdk / "modules/secondary.cjo").write_text("synthetic module\n")
        self.provenance = {
            "sources": {role: {"commit": "a" * 40, "repository": "https://example.invalid/fixture"}
                        for role in ("compiler", "stdlib", "llvm", "target_runtime")},
            "host_sdk": {"identity": "synthetic fixture, not a publishable SDK"},
            "execution": {"kind": "retained-build", "evidence": "test fixture only"},
            "role_sha256": {role: product.digest(self.root / "input" / name)
                            for role, name in product.ROLES.items()},
        }
        self.provenance_file = self.root / "provenance.json"
        product.write_json(self.provenance_file, self.provenance)
        self.output = self.root / "package"

    def pack(self):
        with contextlib.redirect_stdout(io.StringIO()):
            product.pack(argparse.Namespace(sdk=self.sdk, host=self.host,
                         provenance=self.provenance_file, output=self.output))
        self.installed = self.output / "tuple"
        self.manifest_sha = product.digest(self.installed / "language-tuple.json")
        self.compiler_sha = self.provenance["role_sha256"]["compiler"]

    def verify(self):
        return product.verify(self.installed, self.manifest_sha, self.compiler_sha)

    def test_roundtrip_roles_and_local_compiler_aliases(self):
        self.pack()
        self.verify()
        archive = next(self.output.glob("*.tar.gz"))
        destination = self.root / "downloaded"
        with contextlib.redirect_stdout(io.StringIO()):
            product.unpack(argparse.Namespace(archive=archive, archive_sha256=product.digest(archive),
                           output=destination, manifest_sha256=self.manifest_sha, compiler_sha256=self.compiler_sha))
        manifest = product.verify(destination / "tuple", self.manifest_sha, self.compiler_sha)
        self.assertEqual(manifest["roles"], product.ROLES)
        self.assertEqual((destination / "tuple/sdk/bin/cjc").readlink(), Path("cjcj-stage1"))

    def test_producer_rejects_wrong_role_bytes(self):
        (self.sdk / "bin/cjcj-stage1").write_text("wrong compiler before packaging\n")
        with self.assertRaisesRegex(ValueError, "TUPLE_ROLE_IDENTITY_MISMATCH compiler"):
            self.pack()

    def test_consumer_rejects_changed_nonrole_payload(self):
        self.pack()
        (self.installed / "sdk/modules/secondary.cjo").write_text("replaced module\n")
        with self.assertRaisesRegex(ValueError, "TUPLE_PAYLOAD_MISMATCH sdk/modules/secondary.cjo"):
            self.verify()

    def test_consumer_rejects_replaced_compiler(self):
        self.pack()
        (self.installed / product.ROLES["compiler"]).write_text("nightly substitution fixture\n")
        with self.assertRaisesRegex(ValueError, "TUPLE_PAYLOAD_MISMATCH sdk/bin/cjcj-stage1"):
            self.verify()

    def test_consumer_requires_external_manifest_pin(self):
        self.pack()
        with self.assertRaisesRegex(ValueError, "TUPLE_MANIFEST_DIGEST_MISMATCH"):
            product.verify(self.installed, "0" * 64, self.compiler_sha)

    def test_consumer_requires_external_compiler_pin(self):
        self.pack()
        with self.assertRaisesRegex(ValueError, "TUPLE_COMPILER_IDENTITY_MISMATCH"):
            product.verify(self.installed, self.manifest_sha, "0" * 64)

    def test_consumer_rejects_unlisted_files(self):
        self.pack()
        (self.installed / "sdk/bin/unlisted").write_text("unlisted loader input")
        with self.assertRaisesRegex(ValueError, "TUPLE_FILE_SET_MISMATCH"):
            self.verify()

    def test_archive_requires_independent_digest(self):
        self.pack()
        with self.assertRaisesRegex(ValueError, "TUPLE_ARCHIVE_DIGEST_MISMATCH"):
            product.unpack(argparse.Namespace(archive=next(self.output.glob("*.tar.gz")),
                           archive_sha256="0" * 64, output=self.root / "rejected",
                           manifest_sha256=self.manifest_sha, compiler_sha256=self.compiler_sha))
        self.assertFalse((self.root / "rejected").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
