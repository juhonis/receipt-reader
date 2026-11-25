"""Derive generated Dart version metadata from pubspec.yaml; no dependency on Flutter."""
import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
PATTERN = re.compile(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
                     r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?\+([1-9][0-9]*)')


@dataclass(frozen=True)
class Version:
    name: str
    build: int

    @property
    def full(self):
        return f'{self.name}+{self.build}'

    @property
    def tag(self):
        return 'v' + self.name

    @property
    def artifact(self):
        return f'receipt-reader-{self.name}-build{self.build}-android.apk'

    @property
    def windows_artifact(self):
        return f'receipt-reader-{self.name}-build{self.build}-windows-x64.zip'


def parse(value):
    match = PATTERN.fullmatch(value)
    if not match or int(match[5]) > 2100000000:
        raise ValueError('Version must be SemVer+positive Android build (at most 2100000000)')
    if match[4] and any(p.isdigit() and len(p) > 1 and p.startswith('0') for p in match[4].split('.')):
        raise ValueError('Numeric prerelease identifiers must not have leading zeroes')
    return Version(value.rsplit('+', 1)[0], int(match[5]))


def read_version(root=ROOT):
    return pubspec_version((root / 'pubspec.yaml').read_text(encoding='utf-8'))


def pubspec_version(source):
    values = re.findall(r'^version:\s*(\S+)\s*$', source, re.M)
    if len(values) != 1:
        raise ValueError('Exactly one pubspec version is required')
    return parse(values[0])


def check_history(version, root=ROOT):
    tags = subprocess.check_output(['git', 'tag', '--list', 'v*'], cwd=root, text=True).splitlines()
    if len(tags) > 1000:
        raise ValueError('Version tag history exceeds the reviewed bound')
    for tag in tags:
        if tag == version.tag:
            continue
        source = subprocess.check_output(['git', 'show', tag + ':pubspec.yaml'], cwd=root, text=True)
        previous = pubspec_version(source)
        if previous.build >= version.build:
            raise ValueError('Android build number must exceed every previously tagged build: ' + tag)


def dart_source(version):
    return ('// Generated from pubspec.yaml by tools/releases/version.py. Do not edit.\n'
            f"const receiptAppVersion = '{version.full}';\n")


def sync(root=ROOT, check=False, tag=None):
    version = read_version(root)
    if tag is not None and tag != version.tag:
        raise ValueError('Release tag does not match pubspec.yaml')
    path = root / 'lib/app_version.dart'
    expected = dart_source(version)
    if check:
        if not path.is_file() or path.read_text(encoding='utf-8') != expected:
            raise ValueError('Generated app version is stale; run python tools/releases/version.py')
    else:
        path.write_text(expected, encoding='utf-8', newline='\n')
    return version


if __name__ == '__main__':
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--check', action='store_true')
    cli.add_argument('--tag')
    cli.add_argument('--check-history', action='store_true')
    args = cli.parse_args()
    try:
        version = sync(check=args.check, tag=args.tag)
        if args.check_history:
            check_history(version)
        print(version.full)
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from None
