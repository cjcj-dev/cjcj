#!/usr/bin/env python3
"""Publish a verified retained H48 tuple as a prerelease, or fetch its exact IDs."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

from language_tuple import EXCLUDED, digest, require, unpack, verify, write_json

REPOSITORY = "cjcj-dev/cjcj"
# Local operations use the campaign bot shim. Hosted consumers already receive
# their repository-scoped Actions token and use the runner's installed gh.
GH = ["gh"] if os.environ.get("GITHUB_ACTIONS") == "true" else ["/root/.local/bin/cjcj-bot", "exec", "gh"]


def gh(*args):
    return subprocess.check_output([*GH, *args], text=True)


def api_write(method, route, value):
    return json.loads(subprocess.check_output([*GH, "api", "--method", method,
                      route, "--input", "-"], input=json.dumps(value), text=True))


def download_asset(asset, output):
    with output.open("wb") as stream:
        subprocess.run([*GH, "api", f"repos/{REPOSITORY}/releases/assets/{asset}",
                        "-H", "Accept: application/octet-stream"], stdout=stream, check=True)


def publish(args):
    manifest = verify(args.package / "tuple", args.manifest_sha256, args.compiler_sha256)
    require(manifest["provenance"]["execution"]["kind"] == "retained-build", "H48_RETAINED_BUILD_REQUIRED")
    source = manifest["provenance"]["sources"]["compiler"]["commit"]
    archives = list(args.package.glob("h48-language-tuple-*.tar.gz"))
    require(len(archives) == 1, "H48_ARCHIVE_COUNT")
    archive = archives[0]
    archive_sha = digest(archive)
    # Verify the actual compressed payload as well as the producer directory.
    with tempfile.TemporaryDirectory(dir=args.package, prefix="readback-") as temporary:
        unpack(argparse.Namespace(archive=archive, archive_sha256=archive_sha,
               output=Path(temporary) / "extracted", manifest_sha256=args.manifest_sha256,
               compiler_sha256=args.compiler_sha256))
    tag = f"h48-{source}-{archive_sha[:12]}-provenance-partial-prerelease"
    notes = args.package / "release-notes.md"
    notes.write_text(f"Retained H48 language tuple. Compiler source: `{source}`.\n\n"
                     "These are retained build bytes, not a rebuild of current master. "
                     "See the provenance manifest for each component's source and build evidence. "
                     "Std source SHA was not recorded; its exact bytes and compiler/backend inputs are pinned. "
                     "Source traceability is tracked in cjcj#135. "
                     "Only the official compiler host runtime is included; the consumer must build "
                     "its coloured target runtime from its own immutable source pin.\n")
    if args.resume_release_id is not None:
        release = json.loads(gh("api", f"repos/{REPOSITORY}/releases/{args.resume_release_id}"))
        require(release["tag_name"] == tag and release["target_commitish"] == source
                and release["draft"] and release["prerelease"], "H48_RESUME_IDENTITY")
    else:
        release = api_write("POST", f"repos/{REPOSITORY}/releases", {
            "tag_name": tag, "target_commitish": source, "name": tag, "body": notes.read_text(),
            "draft": True, "prerelease": True, "make_latest": "false",
        })
    named_manifest = args.package / f"h48-{source}-provenance.json"
    named_manifest.write_bytes((args.package / "tuple/language-tuple.json").read_bytes())
    qualification = args.package / f"h48-{source}-PROVENANCE-NOTES.json"
    write_json(qualification, {
        "manifest_sha256": args.manifest_sha256,
        "qualification": "H48-provenance-partial",
        "std_source_sha": "unrecorded",
        "follow_up": "cjcj-dev/cjcj#135",
        "excluded": {name: (
            "Retained target runtime/boundscheck source identity was not recoverable; consumer supplies a newly pinned pair."
            if "runtime/lib/" in name or name.endswith("libboundscheck.so") else
            "AST support source identity was not recoverable; it is not required by the qualified language gate."
            if name.endswith("libcangjie-ast-support.a") else
            "Stale backend metadata/cache predates the installed llc/opt; the manifest pins the executable bytes directly."
        ) for name in EXCLUDED},
    })
    sums = args.package / f"h48-{source}-SHA256SUMS"
    sums.write_text("".join(f"{digest(file)}  {file.name}\n" for file in (archive, named_manifest, qualification)))
    files = [archive, named_manifest, qualification, sums]
    if args.resume_release_id is None:
        gh("release", "upload", tag, "--repo", REPOSITORY, *map(str, files))
    # Draft releases need their numeric ID; the tag endpoint can return 404.
    release = json.loads(gh("api", f"repos/{REPOSITORY}/releases/{release['id']}"))
    require(release["prerelease"] and release["draft"], "H48_RELEASE_STATE")
    assets = {asset["name"]: asset for asset in release["assets"]}
    require(set(assets) == {file.name for file in files}, "H48_RELEASE_ASSET_SET")
    pin = {"schema": 1, "repository": REPOSITORY, "tag": tag, "release_id": release["id"],
           "manifest_sha256": args.manifest_sha256, "compiler_sha256": args.compiler_sha256,
           "sources": manifest["provenance"]["sources"], "assets": []}
    with tempfile.TemporaryDirectory(dir=args.package, prefix="download-") as temporary:
        for file in files:
            asset = assets[file.name]
            copy = Path(temporary) / file.name
            download_asset(asset["id"], copy)
            require(digest(copy) == digest(file), f"H48_RELEASE_READBACK {file.name}")
            pin["assets"].append({"id": asset["id"], "name": file.name, "sha256": digest(file),
                                  "role": "archive" if file == archive else "manifest" if file == named_manifest
                                  else "qualification" if file == qualification else "checksums"})
    published = api_write("PATCH", f"repos/{REPOSITORY}/releases/{release['id']}", {
        "draft": False, "prerelease": True, "make_latest": "false",
    })
    require(not published["draft"] and published["prerelease"], "H48_PUBLICATION_STATE")
    write_json(args.pin, pin)
    print(f"H48_PUBLISHED release_id={release['id']} pin={args.pin}")


def fetch(args):
    pin = json.loads(args.pin.read_text())
    require(pin["schema"] == 1 and pin["repository"] == REPOSITORY, "H48_PIN_SCHEMA")
    release = json.loads(gh("api", f"repos/{REPOSITORY}/releases/{int(pin['release_id'])}"))
    require(release["prerelease"] and not release["draft"] and release["tag_name"] == pin["tag"],
            "H48_PIN_RELEASE_IDENTITY")
    require(not args.output.exists(), "H48_OUTPUT_EXISTS")
    args.output.mkdir(parents=True)
    records = {a["id"]: a for a in release["assets"]}
    by_role = {}
    for asset in pin["assets"]:
        require(asset["role"] in ("archive", "manifest", "qualification", "checksums") and asset["role"] not in by_role,
                "H48_ASSET_ROLE")
        require(Path(asset["name"]).name == asset["name"] and asset["name"] not in (".", ".."), "H48_ASSET_NAME")
        require(records[asset["id"]]["name"] == asset["name"], "H48_ASSET_IDENTITY")
        file = args.output / asset["name"]
        download_asset(asset["id"], file)
        require(digest(file) == asset["sha256"], f"H48_ASSET_DIGEST {asset['role']}")
        by_role[asset["role"]] = (file, asset["sha256"])
    require(set(by_role) == {"archive", "manifest", "qualification", "checksums"}, "H48_ASSET_SET")
    require(by_role["manifest"][1] == pin["manifest_sha256"], "H48_MANIFEST_PIN")
    qualification = json.loads(by_role["qualification"][0].read_text())
    require(qualification["manifest_sha256"] == pin["manifest_sha256"]
            and qualification["std_source_sha"] == "unrecorded"
            and qualification["qualification"] == "H48-provenance-partial"
            and set(qualification["excluded"]) == set(EXCLUDED), "H48_QUALIFICATION_PIN")
    archive, archive_sha = by_role["archive"]
    unpack(argparse.Namespace(archive=archive, archive_sha256=archive_sha, output=args.output / "installed",
           manifest_sha256=pin["manifest_sha256"], compiler_sha256=pin["compiler_sha256"]))
    manifest = json.loads(by_role["manifest"][0].read_text())
    require(manifest["provenance"]["sources"] == pin["sources"], "H48_SOURCE_PIN")
    print(f"H48_FETCHED_VERIFIED root={args.output / 'installed/tuple'}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    producer = commands.add_parser("publish")
    producer.add_argument("--package", type=Path, required=True)
    producer.add_argument("--manifest-sha256", required=True)
    producer.add_argument("--compiler-sha256", required=True)
    producer.add_argument("--resume-release-id", type=int,
                          help="Read back an already uploaded matching draft; never replace its assets")
    consumer = commands.add_parser("fetch")
    consumer.add_argument("--output", type=Path, required=True)
    for command in (producer, consumer):
        command.add_argument("--pin", type=Path, required=True)
    args = parser.parse_args()
    (publish if args.command == "publish" else fetch)(args)
