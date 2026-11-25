"""Run checksum-pinned Windows development tools; never upload scan results."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.request import Request, urlopen
import zipfile

ROOT = Path(__file__).resolve().parents[2]
LOCK = json.loads(Path(__file__).with_name('dev-tools.json').read_text(encoding='utf-8'))


def executable(name):
    if os.name != 'nt':
        raise ValueError('These development-tool pins target Windows x64')
    spec = LOCK[name]
    directory = ROOT / 'build/ci-tools' / (name + '-' + spec['version'])
    directory.mkdir(parents=True, exist_ok=True)
    archive = directory / 'download.zip'
    if not archive.is_file():
        with urlopen(Request(spec['url'], headers={'User-Agent': 'receipt-reader-ci'}), timeout=60) as response:
            data = response.read(40 * 1024 * 1024 + 1)
        if len(data) > 40 * 1024 * 1024:
            raise ValueError('Oversized development tool archive')
        if hashlib.sha256(data).hexdigest() != spec['sha256']:
            raise ValueError('Development tool download checksum mismatch')
        archive.write_bytes(data)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != spec['sha256']:
        raise ValueError('Cached development tool checksum mismatch')
    # Extract only the known executable, without trusting archive member paths.
    with zipfile.ZipFile(archive) as bundle:
        binary = bundle.read(spec['executable'])
    target = directory / spec['executable']
    if not target.is_file() or target.read_bytes() != binary:
        target.write_bytes(binary)
    return target


if __name__ == '__main__':
    if len(sys.argv) < 2 or sys.argv[1] not in LOCK:
        raise SystemExit('Usage: python tools/ci/dev_tools.py {gitleaks|actionlint} [arguments...]')
    try:
        raise SystemExit(subprocess.call([str(executable(sys.argv[1])), *sys.argv[2:]], cwd=ROOT))
    except (ValueError, OSError) as error:
        raise SystemExit(str(error)) from None
