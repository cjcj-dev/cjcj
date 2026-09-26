#!/usr/bin/env python3
"""Install target SDK inputs into a job-owned directory; never declares readiness.

OHOS archive identities: openharmony/docs, OpenHarmony-v5.0.1-release.md:260-262.
Android uses the SDK manager already installed on GitHub's official runners.
Xcode is provisioned by the macOS runner image and selected explicitly here.
"""
import argparse
import hashlib
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import zipfile

OHOS_RELEASE = '5.0.1-Release'
OHOS_ARCHIVES = {
    'Linux': ('ohos-sdk-windows_linux-public.tar.gz', '575a245258270b7847bc9ea7045757e6430c61143e0958bfe2da89c7c8de9bf1'),
    'Windows': ('ohos-sdk-windows_linux-public.tar.gz', '575a245258270b7847bc9ea7045757e6430c61143e0958bfe2da89c7c8de9bf1'),
    'Darwin': ('L2-SDK-MAC-M1-PUBLIC.tar.gz', '72c4deef4a343a110cf3aa52b4db390a9d3d614073908bc3fc141e32756b25a7'),
}
NDK_VERSION = '27.3.13750724'


def run(*args):
    print('+', *map(str, args), flush=True)
    subprocess.run(list(map(str, args)), check=True)


def export(name, value):
    value = str(value)
    if '\n' in value or '\r' in value:
        raise ValueError('SDK path contains a newline')
    os.environ[name] = value
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output:
        output.write(f'{name}={value}\n')
    print(f'{name}={value}', flush=True)


def install_ndk():
    sdk = Path(os.environ['ANDROID_HOME']).resolve()
    manager = sdk / 'cmdline-tools/latest/bin' / ('sdkmanager.bat' if os.name == 'nt' else 'sdkmanager')
    if os.name == 'nt':
        run('cmd.exe', '/d', '/c', manager, f'ndk;{NDK_VERSION}')
    else:
        run(manager, f'ndk;{NDK_VERSION}')
    export('ANDROID_NDK_ROOT', sdk / 'ndk' / NDK_VERSION)


def install_ohos(root):
    host = platform.system()
    if host == 'Darwin' and platform.machine() != 'arm64':
        raise ValueError('the release OHOS macOS input is for the arm64 runner')
    filename, expected = OHOS_ARCHIVES[host]
    archive = root / filename
    url = f'https://repo.huaweicloud.com/openharmony/os/{OHOS_RELEASE}/{filename}'
    run('curl', '--fail', '--location', '--retry', '3', '--output', archive, url)
    digest = hashlib.sha256()
    with archive.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    actual = digest.hexdigest()
    print(f'OHOS_ARCHIVE_SHA256={actual}', flush=True)
    if actual != expected:
        raise ValueError(f'OHOS archive identity mismatch: expected {expected}, got {actual}')
    # Public bundles contain zip packages for several components (and on
    # Linux/Windows for both hosts). Copy only this host's native component.
    native_zip = root / 'native.zip'
    wanted = {'Linux': 'linux', 'Windows': 'windows', 'Darwin': 'darwin'}[host]
    matches = []
    with tarfile.open(archive, 'r|gz') as bundle:
        for member in bundle:
            name = Path(member.name).name
            if member.isfile() and name.startswith('native-') and name.endswith('.zip') and wanted in name:
                matches.append(member.name)
                with bundle.extractfile(member) as source, native_zip.open('wb') as target:
                    shutil.copyfileobj(source, target)
    if len(matches) != 1:
        raise ValueError(f'expected one native {wanted} package, found {matches}')
    print(f'OHOS_NATIVE_PACKAGE={matches[0]}', flush=True)
    sdk = root / 'sdk'
    sdk.mkdir()
    with zipfile.ZipFile(native_zip) as bundle:
        for item in bundle.infolist():
            destination = (sdk / item.filename).resolve()
            if not destination.is_relative_to(sdk.resolve()):
                raise ValueError(f'archive member escapes SDK: {item.filename}')
            bundle.extract(item, sdk)
            mode = item.external_attr >> 16
            if mode and os.name != 'nt':
                destination.chmod(mode & 0o777)
    export('OHOS_SDK_HOME', sdk)
    archive.unlink()
    native_zip.unlink()


def install_xcode():
    if platform.system() != 'Darwin':
        raise ValueError('Xcode requires the macOS runner')
    developer = Path('/Applications/Xcode.app/Contents/Developer')
    run('sudo', 'xcode-select', '--switch', developer)
    run('xcodebuild', '-version')
    export('DEVELOPER_DIR', developer)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('requirement', choices=['android-ndk', 'ohos-sdk', 'xcode-ios'])
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    # Every invocation owns a fresh directory; never reuse a partially installed SDK.
    args.root.mkdir(parents=True, exist_ok=False)
    {'android-ndk': install_ndk, 'ohos-sdk': lambda: install_ohos(args.root), 'xcode-ios': install_xcode}[args.requirement]()


if __name__ == '__main__':
    main()
