"""Packaging contracts only; synthetic SDKs do not prove runtime admission."""
import argparse
import contextlib
import hashlib
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

import qualified_language_tuple as product


class QualifiedTupleTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.sdk = self.root / "input"
        names = {"bin/cjc": "entry wrapper", "bin/cjcj-stage1": "compiler",
                 "third_party/llvm/bin/llc": "backend wrapper",
                 "third_party/llvm/bin/opt": "backend wrapper",
                 "lib/linux_x86_64_cjnative/libcangjie-std-core.a": "std",
                 "runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so": "qualified runtime",
                 "runtime/lib/linux_x86_64_cjnative/libboundscheck.so": "qualified boundscheck",
                 "host/compiler/libcangjie-runtime.so": "compiler host",
                 "MANIFEST": "source receipt", "std-producer.json": "std receipt",
                 "provenance/SDK.lock.json": "complete lock"}
        for name, data in names.items():
            path = self.sdk / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(data)
        self.colour_host = self.root / "reference.so"
        self.colour_host.write_text("official reference")
        archives = {"lib/linux_x86_64_cjnative/libcangjie-std-core.a":
                    product.digest(self.sdk / "lib/linux_x86_64_cjnative/libcangjie-std-core.a")}
        language = {key: product.digest(self.sdk / name) for key, name in {
            "cjc": "bin/cjc", "llc": "third_party/llvm/bin/llc", "opt": "third_party/llvm/bin/opt",
            "std_core": "lib/linux_x86_64_cjnative/libcangjie-std-core.a",
            "runtime": "runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so"}.items()}
        language["std"] = hashlib.sha256(json.dumps(archives, sort_keys=True).encode()).hexdigest()
        host = {"libcangjie-runtime.so": product.digest(self.sdk / "host/compiler/libcangjie-runtime.so")}
        self.proof = {"language": language,
                      "components": {name: product.digest(self.sdk / name) for name in
                                     ("bin/cjcj-stage1", "MANIFEST", "std-producer.json",
                                      "runtime/lib/linux_x86_64_cjnative/libboundscheck.so")},
                      "compiler_host": host["libcangjie-runtime.so"],
                      "compiler_host_set": hashlib.sha256(json.dumps(host, sort_keys=True).encode()).hexdigest(),
                      "colour_host": product.digest(self.colour_host)}
        self.qualification = self.root / "qualification.json"
        self.qualification.write_text(json.dumps(self.proof))
        self.package = self.root / "package"

    def pack(self):
        with contextlib.redirect_stdout(io.StringIO()):
            product.pack(argparse.Namespace(sdk=self.sdk, qualification=self.qualification,
                         colour_host=self.colour_host, output=self.package, source="synthetic fixture"))
        return self.package / "tuple"

    def test_roundtrip_preserves_wrapper_runtime_and_provenance(self):
        root = self.pack()
        self.assertFalse((root / "sdk/bin/cjc").is_symlink())
        for file in self.sdk.rglob("*"):
            if file.is_file():
                self.assertEqual(file.read_bytes(), (root / "sdk" / file.relative_to(self.sdk)).read_bytes())
        self.assertEqual(self.qualification.read_bytes(), (root / "qualification.json").read_bytes())

    def test_rejects_unqualified_entry_before_publication(self):
        (self.sdk / "bin/cjc").write_text("replacement entry")
        with self.assertRaisesRegex(ValueError, "QUALIFIED_LANGUAGE_IDENTITY"):
            self.pack()

    def test_rejects_changed_payload_after_download(self):
        root = self.pack()
        manifest_sha = product.digest(root / "language-tuple.json")
        (root / "sdk/provenance/SDK.lock.json").write_text("replacement receipt")
        with self.assertRaisesRegex(ValueError, "QUALIFIED_PAYLOAD_IDENTITY"):
            product.verify(root, manifest_sha, self.proof["components"]["bin/cjcj-stage1"])

    def test_rejects_archive_links_before_extraction(self):
        archive = self.root / "bad.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            entry = tarfile.TarInfo("tuple/sdk/host")
            entry.type = tarfile.SYMTYPE
            entry.linkname = "/outside"
            tar.addfile(entry)
        with self.assertRaisesRegex(ValueError, "QUALIFIED_ARCHIVE_PATH"):
            product.unpack(archive, self.root / "extracted", "unused", "unused")
        self.assertFalse((self.root / "extracted").exists())


if __name__ == "__main__":
    unittest.main()
