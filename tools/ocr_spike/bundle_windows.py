"""Build and smoke-test a private relocatable prototype, not a release package."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

import pefile

from run import OUTPUT, MODEL_HASHES, parse_tsv, save, sha256, validate


def dependency_closure(executable):
    root = executable.parent
    available = {p.name.lower(): p for p in root.iterdir() if p.is_file()}
    system = Path(os.environ['SystemRoot']) / 'System32'
    pending, binaries, external = [executable], {}, set()
    while pending:
        path = pending.pop()
        if path.name.lower() in binaries:
            continue
        binaries[path.name.lower()] = path
        with pefile.PE(str(path)) as pe:
            imports = [entry.dll.decode('ascii') for table in
                       ('DIRECTORY_ENTRY_IMPORT', 'DIRECTORY_ENTRY_DELAY_IMPORT')
                       for entry in getattr(pe, table, [])]
        for name in imports:
            key = name.lower()
            if key in available:
                pending.append(available[key])
            elif key.startswith(('api-ms-win-', 'ext-ms-win-')) or (system / name).is_file():
                external.add(name)
            else:
                raise RuntimeError(f'Unresolved dependency: {path.name}: {name}')
    return list(binaries.values()), sorted(external)


def build_and_test(executable):
    binaries, external = dependency_closure(executable)
    parent = OUTPUT / 'windows-bundles'
    parent.mkdir(parents=True, exist_ok=True)
    # A new directory on every run prevents stale DLLs masking missing dependencies.
    staging = Path(tempfile.mkdtemp(prefix='staging-', dir=parent))
    for source in binaries:
        shutil.copy2(source, staging / source.name)
    models = staging / 'tessdata'
    models.mkdir()
    for language, digest in MODEL_HASHES.items():
        source = OUTPUT / 'models' / f'{language}.traineddata'
        if sha256(source) != digest:
            raise ValueError('Model checksum mismatch')
        shutil.copy2(source, models / source.name)
    notices = staging / 'source-notices'
    notices.mkdir()
    for name in ('AUTHORS', 'LICENSE', 'README.md'):
        source = executable.parent / 'doc' / name
        if source.is_file():
            shutil.copy2(source, notices / name)
    manifest = {'releaseReady': False, 'licenseAudit': 'Incomplete dependency/model notices',
                'systemImports': external,
                'files': {str(p.relative_to(staging)): sha256(p)
                          for p in staging.rglob('*') if p.is_file()}}
    save(staging / 'bundle-manifest.json', manifest)
    bundle = staging.with_name(staging.name.replace('staging-', 'Relocated OCR '))
    staging.rename(bundle)
    windows = Path(os.environ['SystemRoot'])
    env = {key: value for key, value in os.environ.items()
           if key.upper() not in ('PATH', 'TESSDATA_PREFIX')}
    env['PATH'] = os.pathsep.join(map(str, (bundle, windows / 'System32', windows)))
    evidence = []
    for path in sorted((OUTPUT / 'preprocessing').glob('*/*-psm*.json')):
        expected = json.loads(path.read_text(encoding='utf-8'))
        image = path.parent / f"{expected['sampleId']}.png"
        if sha256(image) != expected['inputSha256']:
            raise ValueError('Experiment image changed')
        process = subprocess.run([str(bundle / 'tesseract.exe'), str(image), 'stdout',
                                  '--tessdata-dir', str(bundle / 'tessdata'), '-l', 'fin+eng',
                                  '--psm', str(expected['configuration']['psm']),
                                  '-c', 'tessedit_create_tsv=1'],
                                 cwd=bundle, env=env, capture_output=True, encoding='utf-8',
                                 check=True, timeout=120)
        blocks = parse_tsv(process.stdout)
        validate({**expected, 'blocks': blocks})
        if blocks != expected['blocks']:
            raise ValueError(f'Bundled OCR differs: {path.name}')
        evidence.append({'result': str(path.relative_to(OUTPUT)),
                         'inputSha256': sha256(image), 'identicalTextAndGeometry': True})
    if not evidence:
        raise ValueError('Run preprocess.py first')
    save(bundle / 'smoke-evidence.json', {'cases': evidence, 'sanitizedPath': env['PATH'],
          'freshMachineVerified': False, 'runtimeLoadedModulesAudited': False})
    print(f'Private prototype: {bundle}')
    print(f'{len(evidence)} OCR cases match; fresh-machine and license audit still required.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tesseract', type=Path,
                        default=Path(r'C:\Program Files\Tesseract-OCR\tesseract.exe'))
    build_and_test(parser.parse_args().tesseract.resolve())
