#!/usr/bin/env python3
"""Stage, download and finalize a qualified source tuple as a non-latest prerelease.

Local calls use the campaign bot. Qualification runs separately on kkk2 and
returns its real gate output; creating the draft never claims gate acceptance.
"""
import argparse
import json
from pathlib import Path
import tempfile
import tarfile

from language_tuple import digest, require, write_json
from source_language_tuple import unpack, verify
from publish_language_tuple import REPOSITORY, gh, api_write, download_asset


def current_sources(sources):
    for key, repo, branch in (('cjcj', REPOSITORY, 'master'),
                              ('runtime', 'cjcj-dev/cangjie-runtime', 'main')):
        head = json.loads(gh('api', f'repos/{repo}/commits/{branch}'))['sha']
        require(head == sources[key], f'SOURCE_TUPLE_MAIN_MOVED {key} expected={sources[key]} actual={head}')


def stage(args):
    manifest = args.package / 'language-tuple.json'
    manifest_sha = digest(manifest)
    value = json.loads(manifest.read_text())
    compiler_sha = value['role_sha256']['compiler']
    verify(args.package / 'tuple', manifest_sha, compiler_sha)
    current_sources(value['sources'])
    archives = list(args.package.glob('source-language-tuple-*.tar.gz'))
    require(len(archives) == 1, 'SOURCE_TUPLE_ARCHIVE_COUNT')
    archive = archives[0]
    with tempfile.TemporaryDirectory(dir=args.package) as tmp:
        unpack(argparse.Namespace(archive=archive, archive_sha256=digest(archive), output=Path(tmp) / 'readback',
                                 manifest_sha256=manifest_sha, compiler_sha256=compiler_sha))
    sources = value['sources']
    tag = f"source-tuple-{sources['cjcj']}-{sources['runtime']}-{digest(archive)[:12]}-prerelease"
    release = api_write('POST', f'repos/{REPOSITORY}/releases', {
        'tag_name': tag, 'target_commitish': sources['cjcj'], 'name': tag,
        'body': 'Source-built stage3 compiler and rebuilt std. Compiler runtime is frozen with the tuple; '
                'official host runtime is separate. The runtime under test is built by the consumer. '
                'See the source/build manifests and language-gate qualification asset.',
        'draft': True, 'prerelease': True, 'make_latest': 'false',
    })
    named_manifest = args.package / f"source-tuple-{sources['cjcj']}-{sources['runtime']}-provenance.json"
    named_manifest.write_bytes(manifest.read_bytes())
    sums = args.package / f"source-tuple-{sources['cjcj']}-{sources['runtime']}-SHA256SUMS"
    sums.write_text(f'{digest(archive)}  {archive.name}\n{manifest_sha}  {named_manifest.name}\n')
    files = [archive, named_manifest, sums]
    gh('release', 'upload', tag, '--repo', REPOSITORY, *map(str, files))
    release = json.loads(gh('api', f"repos/{REPOSITORY}/releases/{release['id']}"))
    records = {asset['name']: asset for asset in release['assets']}
    require(set(records) == {file.name for file in files}, 'SOURCE_TUPLE_ASSET_SET')
    pin = {'schema': 2, 'repository': REPOSITORY, 'release_id': release['id'], 'tag': tag,
           'sources': sources, 'manifest_sha256': manifest_sha, 'compiler_sha256': compiler_sha, 'assets': []}
    with tempfile.TemporaryDirectory(dir=args.package) as tmp:
        for role, file in zip(('archive', 'manifest', 'checksums'), files):
            asset = records[file.name]
            copy = Path(tmp) / file.name
            download_asset(asset['id'], copy)
            require(digest(copy) == digest(file), f'SOURCE_TUPLE_ASSET_READBACK {file.name}')
            pin['assets'].append({'role': role, 'name': file.name, 'id': asset['id'], 'sha256': digest(file)})
    write_json(args.pin, pin)
    print(f"SOURCE_TUPLE_DRAFT release_id={release['id']}")


def fetch(args):
    pin = json.loads(args.pin.read_text())
    require(pin['schema'] == 2 and pin['repository'] == REPOSITORY, 'SOURCE_TUPLE_PIN_SCHEMA')
    release = json.loads(gh('api', f"repos/{REPOSITORY}/releases/{int(pin['release_id'])}"))
    require(release['prerelease'] and release['tag_name'] == pin['tag']
            and release['target_commitish'] == pin['sources']['cjcj']
            and (args.allow_draft or not release['draft']), 'SOURCE_TUPLE_RELEASE_IDENTITY')
    require(not args.output.exists(), 'SOURCE_TUPLE_OUTPUT_EXISTS')
    args.output.mkdir(parents=True)
    records = {asset['id']: asset for asset in release['assets']}
    roles = {}
    for asset in pin['assets']:
        require(asset['role'] in ('archive', 'manifest', 'checksums', 'qualification') and asset['role'] not in roles,
                'SOURCE_TUPLE_ASSET_ROLE')
        require(Path(asset['name']).name == asset['name'] and asset['name'] not in ('.', '..'),
                'SOURCE_TUPLE_ASSET_NAME')
        require(records[asset['id']]['name'] == asset['name'], 'SOURCE_TUPLE_ASSET_IDENTITY')
        file = args.output / asset['name']
        download_asset(asset['id'], file)
        require(digest(file) == asset['sha256'], f"SOURCE_TUPLE_ASSET_DIGEST {asset['role']}")
        roles[asset['role']] = (file, asset['sha256'])
    expected_roles = {'archive', 'manifest', 'checksums'}
    if not release['draft']:
        expected_roles.add('qualification')
    require(set(roles) == expected_roles, 'SOURCE_TUPLE_ASSET_SET')
    if 'qualification' in roles:
        with tarfile.open(roles['qualification'][0], 'r:gz') as proof:
            receipt = json.load(proof.extractfile('qualification.json'))
            require(receipt['manifest_sha256'] == pin['manifest_sha256'] and receipt['gate_rc'] == 0,
                    'SOURCE_TUPLE_PUBLISHED_QUALIFICATION')
    require(roles['manifest'][1] == pin['manifest_sha256'], 'SOURCE_TUPLE_MANIFEST_PIN')
    archive, archive_sha = roles['archive']
    unpack(argparse.Namespace(archive=archive, archive_sha256=archive_sha, output=args.output / 'installed',
                             manifest_sha256=pin['manifest_sha256'], compiler_sha256=pin['compiler_sha256']))
    value = verify(args.output / 'installed/tuple', pin['manifest_sha256'], pin['compiler_sha256'])
    require(value['sources'] == pin['sources'], 'SOURCE_TUPLE_SOURCE_PIN')
    print('SOURCE_TUPLE_FETCHED_VERIFIED')


def finalize(args):
    pin = json.loads(args.pin.read_text())
    receipt = json.loads((args.qualification / 'qualification.json').read_text())
    require(receipt['manifest_sha256'] == pin['manifest_sha256']
            and receipt['compiler_sha256'] == pin['compiler_sha256']
            and receipt['runtime_source_sha'] == pin['sources']['runtime']
            and receipt['gate_rc'] == 0, 'SOURCE_TUPLE_QUALIFICATION_IDENTITY')
    require(set(receipt['elf']) == {'gate/finalizer_trigger', 'gate/phase_entry_trigger'}, 'SOURCE_TUPLE_GATE_ELF_SET')
    for name, sha in receipt['elf'].items():
        require(digest(args.qualification / name) == sha, f'SOURCE_TUPLE_GATE_ELF {name}')
    require(digest(args.qualification / 'gate.log') == receipt['gate_log_sha256'], 'SOURCE_TUPLE_GATE_LOG')
    release = json.loads(gh('api', f"repos/{REPOSITORY}/releases/{int(pin['release_id'])}"))
    require(release['draft'] and release['prerelease'] and release['tag_name'] == pin['tag']
            and release['target_commitish'] == pin['sources']['cjcj'], 'SOURCE_TUPLE_DRAFT_IDENTITY')
    current_sources(pin['sources'])
    qualification = args.qualification / f"source-tuple-{pin['sources']['cjcj']}-{pin['sources']['runtime']}-qualification.tar.gz"
    with tarfile.open(qualification, 'w:gz') as proof:
        for name in ('qualification.json', 'gate.log', *receipt['elf']):
            proof.add(args.qualification / name, arcname=name)
    gh('release', 'upload', pin['tag'], '--repo', REPOSITORY, str(qualification))
    uploaded = json.loads(gh('api', f"repos/{REPOSITORY}/releases/{pin['release_id']}"))
    assets = [asset for asset in uploaded['assets'] if asset['name'] == qualification.name]
    require(len(assets) == 1, 'SOURCE_TUPLE_QUALIFICATION_ASSET')
    with tempfile.TemporaryDirectory(dir=args.qualification) as tmp:
        copy = Path(tmp) / qualification.name
        download_asset(assets[0]['id'], copy)
        require(digest(copy) == digest(qualification), 'SOURCE_TUPLE_QUALIFICATION_READBACK')
    pin['assets'].append({'role': 'qualification', 'name': qualification.name,
                          'id': assets[0]['id'], 'sha256': digest(qualification)})
    current_sources(pin['sources'])
    published = api_write('PATCH', f"repos/{REPOSITORY}/releases/{pin['release_id']}", {
        'draft': False, 'prerelease': True, 'make_latest': 'false',
    })
    require(published['prerelease'] and not published['draft'], 'SOURCE_TUPLE_PUBLICATION_STATE')
    write_json(args.pin, pin)
    print(f"SOURCE_TUPLE_PUBLISHED release_id={pin['release_id']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    producer = commands.add_parser('stage')
    producer.add_argument('--package', type=Path, required=True)
    consumer = commands.add_parser('fetch')
    consumer.add_argument('--output', type=Path, required=True)
    consumer.add_argument('--allow-draft', action='store_true')
    publisher = commands.add_parser('finalize')
    publisher.add_argument('--qualification', type=Path, required=True)
    for command in (producer, consumer, publisher):
        command.add_argument('--pin', type=Path, required=True)
    args = parser.parse_args()
    {'stage': stage, 'fetch': fetch, 'finalize': finalize}[args.command](args)


if __name__ == '__main__':
    main()
