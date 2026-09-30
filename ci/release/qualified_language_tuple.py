#!/usr/bin/env python3
"""Preserve the complete SDK whose bytes are bound by runtime admission.

This format deliberately keeps the qualified entry wrappers and SDK runtime.
It does not change the separate H48 packaging contract.
"""
import argparse
import datetime
import json
from pathlib import Path
import shutil
import tarfile
import tempfile

from language_tuple import digest, require, write_json

SCHEMA = "qualified-language-tuple"


def inventory(root):
    files = {}
    for path in sorted(root.rglob("*")):
        require(not path.is_symlink(), f"QUALIFIED_ENTITY_REQUIRED {path}")
        if path.is_file() and path.relative_to(root).as_posix() != "language-tuple.json":
            files[path.relative_to(root).as_posix()] = {
                "sha256": digest(path), "mode": path.stat().st_mode & 0o777}
    return files


def check_identity(root, proof):
    # Use the same identity definitions as runtime language_toolchain.py.
    import hashlib
    sdk = root / "sdk"
    language = {"cjc": digest(sdk / "bin/cjc"),
                "llc": digest(sdk / "third_party/llvm/bin/llc"),
                "opt": digest(sdk / "third_party/llvm/bin/opt"),
                "std_core": digest(sdk / "lib/linux_x86_64_cjnative/libcangjie-std-core.a"),
                "runtime": digest(sdk / "runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so")}
    archives = {str(p.relative_to(sdk)): digest(p) for p in
                sorted((sdk / "lib/linux_x86_64_cjnative").glob("libcangjie-std-*.a"))}
    language["std"] = hashlib.sha256(json.dumps(archives, sort_keys=True).encode()).hexdigest()
    require(language == proof["language"], "QUALIFIED_LANGUAGE_IDENTITY")
    for name, expected in proof["components"].items():
        require(digest(sdk / name) == expected, f"QUALIFIED_COMPONENT_IDENTITY {name}")
    host = sdk / "host/compiler"
    host_files = {p.name: digest(p) for p in sorted(host.iterdir()) if p.is_file()}
    require(digest(host / "libcangjie-runtime.so") == proof["compiler_host"]
            and hashlib.sha256(json.dumps(host_files, sort_keys=True).encode()).hexdigest()
            == proof["compiler_host_set"], "QUALIFIED_COMPILER_HOST_IDENTITY")
    require(digest(root / "colour-host-runtime.so") == proof["colour_host"],
            "QUALIFIED_COLOUR_HOST_IDENTITY")
    return {"language": language, "components": proof["components"],
            "compiler_host": proof["compiler_host"], "compiler_host_set": proof["compiler_host_set"],
            "colour_host": proof["colour_host"]}


def verify(root, manifest_sha, compiler_sha):
    require(digest(root / "language-tuple.json") == manifest_sha, "QUALIFIED_MANIFEST_DIGEST")
    manifest = json.loads((root / "language-tuple.json").read_text())
    require(manifest["schema"] == SCHEMA, "QUALIFIED_SCHEMA")
    require(inventory(root) == manifest["files"], "QUALIFIED_PAYLOAD_IDENTITY")
    proof = json.loads((root / "qualification.json").read_text())
    require(digest(root / "sdk/bin/cjcj-stage1") == compiler_sha, "QUALIFIED_COMPILER_IDENTITY")
    check_identity(root, proof)
    return manifest


def unpack(archive, output, manifest_sha, compiler_sha):
    require(not output.exists(), "QUALIFIED_OUTPUT_EXISTS")
    with tarfile.open(archive, "r:gz") as tar:
        names = set()
        for entry in tar.getmembers():
            parts = Path(entry.name).parts
            require(parts and parts[0] == "tuple" and ".." not in parts
                    and not Path(entry.name).is_absolute() and entry.name not in names
                    and (entry.isfile() or entry.isdir()), "QUALIFIED_ARCHIVE_PATH")
            names.add(entry.name)
        output.mkdir(parents=True)
        tar.extractall(output)
    verify(output / "tuple", manifest_sha, compiler_sha)


def pack(args):
    require(not args.output.exists(), "QUALIFIED_OUTPUT_EXISTS")
    root = args.output / "tuple"
    root.mkdir(parents=True)
    shutil.copytree(args.sdk, root / "sdk", symlinks=False)
    shutil.copy2(args.qualification, root / "qualification.json")
    shutil.copy2(args.colour_host, root / "colour-host-runtime.so")
    proof = json.loads(args.qualification.read_text())
    identity = check_identity(root, proof)
    manifest = {"schema": SCHEMA, "source": args.source,
                "packed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "identity": identity, "files": inventory(root)}
    write_json(root / "language-tuple.json", manifest)
    manifest_sha = digest(root / "language-tuple.json")
    compiler_sha = proof["components"]["bin/cjcj-stage1"]
    verify(root, manifest_sha, compiler_sha)
    archive = args.output / "qualified-language-tuple-linux-x86_64.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        tar.add(root, arcname="tuple")
    with tempfile.TemporaryDirectory(dir=args.output) as temporary:
        unpack(archive, Path(temporary) / "readback", manifest_sha, compiler_sha)
    print(f"QUALIFIED_PACKED manifest_sha256={manifest_sha} compiler_sha256={compiler_sha}")


def publish(args, gh, api_write, download_asset):
    manifest = verify(args.package / "tuple", args.manifest_sha256, args.compiler_sha256)
    archive = args.package / "qualified-language-tuple-linux-x86_64.tar.gz"
    with tempfile.TemporaryDirectory(dir=args.package) as temporary:
        unpack(archive, Path(temporary) / "readback", args.manifest_sha256, args.compiler_sha256)
    tag = f"tuple-qualified-{args.compiler_sha256[:8]}-{digest(archive)[:12]}"
    repository = "cjcj-dev/cjcj"
    release = api_write("POST", f"repos/{repository}/releases", {
        "tag_name": tag, "target_commitish": args.target_commit,
        "name": tag, "body": f"Complete qualified SDK, preserved from {manifest['source']}. "
        "See the manifest for every payload SHA256 and runtime qualification.",
        "draft": True, "prerelease": True, "make_latest": "false"})
    manifest_file = args.package / "qualified-language-tuple-manifest.json"
    qualification = args.package / "qualified-language-tuple-qualification.json"
    shutil.copy2(args.package / "tuple/language-tuple.json", manifest_file)
    shutil.copy2(args.package / "tuple/qualification.json", qualification)
    sums = args.package / "qualified-language-tuple-SHA256SUMS"
    files = [archive, manifest_file, qualification, sums]
    sums.write_text("".join(f"{digest(p)}  {p.name}\n" for p in files[:-1]))
    gh("release", "upload", tag, "--repo", repository, *map(str, files))
    release = json.loads(gh("api", f"repos/{repository}/releases/{release['id']}"))
    require(release["draft"] and release["prerelease"], "QUALIFIED_RELEASE_STATE")
    assets = {a["name"]: a for a in release["assets"]}
    require(set(assets) == {p.name for p in files}, "QUALIFIED_ASSET_SET")
    pin = {"schema": 1, "tuple_schema": SCHEMA, "repository": repository,
           "tag": tag, "release_id": release["id"], "manifest_sha256": args.manifest_sha256,
           "compiler_sha256": args.compiler_sha256, "source": manifest["source"], "assets": []}
    with tempfile.TemporaryDirectory(dir=args.package) as temporary:
        for file, role in zip(files, ("archive", "manifest", "qualification", "checksums")):
            asset = assets[file.name]
            copy = Path(temporary) / file.name
            download_asset(asset["id"], copy)
            require(digest(copy) == digest(file), f"QUALIFIED_RELEASE_READBACK {role}")
            pin["assets"].append({"id": asset["id"], "name": file.name,
                                  "sha256": digest(file), "role": role})
    state = api_write("PATCH", f"repos/{repository}/releases/{release['id']}", {
        "draft": False, "prerelease": True, "make_latest": "false"})
    require(state["prerelease"] and not state["draft"], "QUALIFIED_PUBLICATION_STATE")
    write_json(args.pin, pin)
    print(f"QUALIFIED_PUBLISHED release_id={release['id']} pin={args.pin}")


def fetch(args, pin, release, download_asset):
    require(not args.output.exists(), "QUALIFIED_OUTPUT_EXISTS")
    args.output.mkdir(parents=True)
    records = {a["id"]: a for a in release["assets"]}
    roles = {}
    for asset in pin["assets"]:
        require(asset["role"] in ("archive", "manifest", "qualification", "checksums")
                and asset["role"] not in roles, "QUALIFIED_ASSET_ROLE")
        require(Path(asset["name"]).name == asset["name"] and asset["name"] not in (".", "..")
                and records[asset["id"]]["name"] == asset["name"], "QUALIFIED_ASSET_IDENTITY")
        file = args.output / asset["name"]
        download_asset(asset["id"], file)
        require(digest(file) == asset["sha256"], f"QUALIFIED_ASSET_DIGEST {asset['role']}")
        roles[asset["role"]] = file
    require(set(roles) == {"archive", "manifest", "qualification", "checksums"}, "QUALIFIED_ASSET_SET")
    require(digest(roles["manifest"]) == pin["manifest_sha256"], "QUALIFIED_MANIFEST_PIN")
    unpack(roles["archive"], args.output / "installed", pin["manifest_sha256"], pin["compiler_sha256"])
    root = args.output / "installed/tuple"
    require(roles["qualification"].read_bytes() == (root / "qualification.json").read_bytes(),
            "QUALIFIED_QUALIFICATION_PIN")
    require(json.loads(roles["manifest"].read_text())["source"] == pin["source"], "QUALIFIED_SOURCE_PIN")
    print(f"QUALIFIED_FETCHED_VERIFIED root={root}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("sdk", "qualification", "colour-host", "output"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    parser.add_argument("--source", required=True)
    pack(parser.parse_args())
