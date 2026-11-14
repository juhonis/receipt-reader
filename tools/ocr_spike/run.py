"""Explicit, local-only OCR experiment. All private artifacts stay in localreceipts."""

import argparse
import base64
import csv
import hashlib
import io
import json
import os
import re
from pathlib import Path
import subprocess
import time
import zipfile
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[2]
PRIVATE = ROOT / 'localreceipts'
OUTPUT = PRIVATE / 'ocr'
PACKAGE = 'fi.juhonis.ocr_spike'
MODEL_REVISION = '87416418657359cb625c412a48b6e1d6d41c29bd'
MODEL_HASHES = {
    'fin': '61a04cd62b507c3d9ae0e1cda399e6715ebf49dea9df47897c8acdcd3bd3e13c',
    'eng': '7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2',
}


def models():
    """Explicit setup download of public models only; never sends receipt data."""
    for language, digest in MODEL_HASHES.items():
        url = f'https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/{MODEL_REVISION}/{language}.traineddata'
        with urlopen(url, timeout=60) as response:
            content = response.read()
        if hashlib.sha256(content).hexdigest() != digest:
            raise ValueError('Model checksum mismatch')
        target = OUTPUT / 'models' / f'{language}.traineddata'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        # Public models only, embedded for first-run offline native comparison.
        asset = Path(__file__).parent / 'android/app/src/main/assets/tessdata' / target.name
        asset.parent.mkdir(parents=True, exist_ok=True)
        asset.write_bytes(content)
    print('Pinned Finnish and English models downloaded and verified.')


def load_manifest():
    manifest = json.loads((OUTPUT / 'manifest.json').read_text(encoding='utf-8'))
    if not manifest:
        raise ValueError('Empty input manifest')
    for entry in manifest:
        if not re.fullmatch(r'sample-[0-9]+', entry['sampleId']):
            raise ValueError('Invalid sample ID')
        prepared = OUTPUT / 'inputs' / (entry['sampleId'] + '.png')
        if sha256(prepared) != entry['preparedSha256']:
            raise ValueError('Prepared image changed; run prepare again')
    return manifest


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare():
    from PIL import Image, ImageOps

    inputs = OUTPUT / 'inputs'
    inputs.mkdir(parents=True, exist_ok=True)
    # Stable anonymous IDs; filenames and original hashes remain private.
    sources = sorted(p for p in PRIVATE.iterdir() if p.suffix.lower() in ('.jpg', '.jpeg', '.png'))
    if not sources:
        raise ValueError('Add JPEG/PNG receipts directly to localreceipts first')
    manifest = []
    for index, source in enumerate(sources, 1):
        sample = f'sample-{index:02}'
        with Image.open(source) as original:
            image = ImageOps.exif_transpose(original).convert('RGB')
            image.save(inputs / f'{sample}.png')
            manifest.append({'sampleId': sample, 'source': source.name,
                             'sha256': sha256(source), 'width': image.width,
                             'height': image.height, 'preparedSha256': sha256(inputs / f'{sample}.png')})
    save(OUTPUT / 'manifest.json', manifest)
    print(f'Prepared {len(manifest)} upright, full-resolution PNGs; originals unchanged.')


def rectangle(left, top, width, height):
    return dict(left=left, top=top, right=left + width, bottom=top + height)


def union(items):
    boxes = [item['box'] for item in items]
    return dict(left=min(b['left'] for b in boxes), top=min(b['top'] for b in boxes),
                right=max(b['right'] for b in boxes), bottom=max(b['bottom'] for b in boxes))


def parse_tsv(tsv):
    blocks = {}
    reader = csv.DictReader(io.StringIO(tsv), delimiter='\t', quoting=csv.QUOTE_NONE)
    required = {'level', 'page_num', 'block_num', 'par_num', 'line_num',
                'left', 'top', 'width', 'height', 'text'}
    if not required.issubset(reader.fieldnames or []):
        raise ValueError('Tesseract did not return the expected TSV columns')
    for row in reader:
        if row['level'] != '5' or not row['text'].strip():
            continue
        block_id = (row['page_num'], row['block_num'])
        line_id = (row['par_num'], row['line_num'])
        line = blocks.setdefault(block_id, {}).setdefault(line_id, [])
        box = rectangle(*(int(row[k]) for k in ('left', 'top', 'width', 'height')))
        line.append({'text': row['text'], 'box': box, 'corners': None})
    result = []
    for grouped_lines in blocks.values():
        lines = [{'text': ' '.join(w['text'] for w in words), 'box': union(words), 'words': words}
                 for words in grouped_lines.values()]
        result.append({'text': '\n'.join(line['text'] for line in lines),
                       'box': union(lines), 'lines': lines})
    return result


def validate(result):
    if result['schemaVersion'] != 1 or result['image']['orientation'] != 'upright':
        raise ValueError('Unsupported coordinate contract')
    width, height = result['image']['width'], result['image']['height']
    if width <= 0 or height <= 0:
        raise ValueError('Invalid image dimensions')
    for block in result['blocks']:
        for line in block['lines']:
            for item in [block, line, *line['words']]:
                b = item['box']
                if not (0 <= b['left'] < b['right'] <= width and
                        0 <= b['top'] < b['bottom'] <= height):
                    raise ValueError('OCR box outside the prepared image')
            for word in line['words']:
                if word['corners'] is not None and len(word['corners']) != 4:
                    raise ValueError('Expected four corners or null')


def windows(args):
    manifest = load_manifest()
    version = subprocess.run([args.tesseract, '--version'], capture_output=True, check=True,
                             encoding='utf-8').stdout.splitlines()[0]
    models = OUTPUT / 'models'
    for language in ('fin', 'eng'):
        model = models / f'{language}.traineddata'
        if not model.is_file() or sha256(model) != MODEL_HASHES[language]:
            raise ValueError(f'Missing or changed pinned model: {language}')
    for psm in (3, 6):
        for entry in manifest:
            sample = entry['sampleId']
            started = time.perf_counter()
            process = subprocess.run(
                [args.tesseract, str(OUTPUT / 'inputs' / f'{sample}.png'), 'stdout',
                 '--tessdata-dir', str(models), '-l', 'fin+eng', '--psm', str(psm),
                 '-c', 'tessedit_create_tsv=1'],
                capture_output=True, encoding='utf-8', timeout=120, check=True)
            blocks = parse_tsv(process.stdout)
            result = {'schemaVersion': 1, 'sampleId': sample, 'engine': version,
                      'inputSha256': entry['preparedSha256'],
                      'adapterVersion': 'tsv-v1', 'configuration': {'psm': psm, 'languages': 'fin+eng'},
                      'modelHashes': {p.name: sha256(p) for p in models.glob('*.traineddata')},
                      'image': {'width': entry['width'], 'height': entry['height'], 'orientation': 'upright'},
                      'elapsedMs': round((time.perf_counter() - started) * 1000),
                      'text': '\n'.join(b['text'] for b in blocks), 'blocks': blocks}
            validate(result)
            save(OUTPUT / f'tesseract-psm{psm}' / f'{sample}.json', result)
            print(f'Tesseract PSM {psm}: {sample} completed (private output saved).')


def android(args):
    sdk = Path(os.environ.get('ANDROID_HOME', Path(os.environ['LOCALAPPDATA']) / 'Android/Sdk'))
    adb = str(sdk / 'platform-tools/adb.exe')
    prefix = [adb, '-s', args.device]

    def call(*command, **kwargs):
        return subprocess.run([*prefix, *command], capture_output=True, check=True,
                              timeout=120, **kwargs).stdout

    apk = Path(__file__).parent / 'build/app/outputs/flutter-apk/app-debug.apk'
    if not apk.is_file():
        raise ValueError('Build the dedicated OCR harness APK first')
    aapt = sdk / 'build-tools/36.0.0/aapt.exe'
    permissions = subprocess.run([str(aapt), 'dump', 'permissions', str(apk)],
                                 capture_output=True, check=True, text=True).stdout
    if 'android.permission.INTERNET' in permissions:
        raise ValueError('Offline harness must not request INTERNET permission')
    with zipfile.ZipFile(apk) as archive:
        assets = [n for n in archive.namelist() if any(s in n.lower() for s in ('mlkit', 'tflite', 'tess', 'lept'))]
        if args.engine == 'tesseract':
            for language, digest in MODEL_HASHES.items():
                if hashlib.sha256(archive.read(f'assets/tessdata/{language}.traineddata')).hexdigest() != digest:
                    raise ValueError('APK does not contain the expected bundled Tesseract models')
    manifest = load_manifest()
    prior_airplane = call('shell', 'settings', 'get', 'global', 'airplane_mode_on').decode().strip()
    installed = False
    try:
        # Uninstall first: no previous app data or model download can survive.
        subprocess.run([*prefix, 'uninstall', PACKAGE], capture_output=True, timeout=30)
        call('shell', 'cmd', 'connectivity', 'airplane-mode', 'enable')
        call('install', str(apk))
        installed = True
        call('shell', 'run-as', PACKAGE, 'mkdir', '-p', 'files/inputs')
        call('shell', 'run-as', PACKAGE, 'sh', '-c', f'"echo {args.engine} > files/engine"')
        for entry in manifest:
            sample = entry['sampleId']
            # No shared-storage copy: stream directly into app-private storage.
            input_bytes = (OUTPUT / 'inputs' / f'{sample}.png').read_bytes()
            call('shell', '-T', 'run-as', PACKAGE, 'sh', '-c',
                 f'"base64 -d > files/inputs/{sample}.png"',
                 input=base64.b64encode(input_bytes))
            staged_bytes = call('exec-out', 'run-as', PACKAGE, 'cat', f'files/inputs/{sample}.png')
            if hashlib.sha256(staged_bytes).digest() != hashlib.sha256(input_bytes).digest():
                raise ValueError(f'ADB input transfer changed image bytes ({len(input_bytes)} to {len(staged_bytes)})')
        started = time.perf_counter()
        call('shell', 'am', 'start', '-n', f'{PACKAGE}/.MainActivity')
        while time.perf_counter() - started < 180:
            listing = call('shell', 'run-as', PACKAGE, 'ls', 'files').decode()
            if 'results' in listing:
                results = call('shell', 'run-as', PACKAGE, 'ls', 'files/results').decode().split()
                if 'failed' in results:
                    failure = json.loads(call('exec-out', 'run-as', PACKAGE, 'cat', 'files/results/failed'))
                    save(OUTPUT / 'android-failure.json', failure)
                    raise RuntimeError('Android OCR failed; no receipt text was logged')
                if 'done' in results:
                    break
            time.sleep(1)
        else:
            raise TimeoutError('Android OCR did not finish')
        for entry in manifest:
            sample = entry['sampleId']
            for psm in ([3, 6] if args.engine == 'tesseract' else [None]):
                filename = f'{sample}-psm{psm}.json' if psm else f'{sample}.json'
                result = json.loads(call('exec-out', 'run-as', PACKAGE, 'cat', f'files/results/{filename}'))
                validate(result)
                if (result['image']['width'], result['image']['height']) != (entry['width'], entry['height']):
                    raise ValueError('Engines did not receive the same image dimensions')
                result['inputSha256'] = entry['preparedSha256']
                if psm:
                    result['modelHashes'] = {f'{lang}.traineddata': digest for lang, digest in MODEL_HASHES.items()}
                folder = f'android-tesseract-psm{psm}' if psm else 'mlkit'
                save(OUTPUT / folder / f'{sample}.json', result)
        evidence_name = 'android-tesseract-evidence.json' if args.engine == 'tesseract' else 'android-evidence.json'
        save(OUTPUT / evidence_name, {'apkSha256': sha256(apk), 'apkBytes': apk.stat().st_size,
             'permissions': permissions, 'bundledModelAssets': assets, 'freshInstall': True,
             'airplaneModeDuringRun': call('shell', 'settings', 'get', 'global', 'airplane_mode_on').decode().strip(),
             'device': call('shell', 'getprop', 'ro.build.fingerprint').decode().strip(),
             'samplesCompleted': len(manifest)})
        (OUTPUT / 'android-failure.json').unlink(missing_ok=True)
        print(f'{args.engine}: {len(manifest)} samples completed on fresh offline installation.')
    finally:
        # This removes only this dedicated harness and its copies, not source images.
        try:
            if installed:
                call('uninstall', PACKAGE)
        finally:
            if prior_airplane != '1':
                call('shell', 'cmd', 'connectivity', 'airplane-mode', 'disable')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['models', 'prepare', 'windows', 'android'])
    parser.add_argument('--tesseract', default=r'C:\Program Files\Tesseract-OCR\tesseract.exe')
    parser.add_argument('--device', default='emulator-5554')
    parser.add_argument('--engine', choices=['mlkit', 'tesseract'], default='mlkit')
    args = parser.parse_args()
    {'models': models, 'prepare': prepare, 'windows': lambda: windows(args),
     'android': lambda: android(args)}[args.command]()


if __name__ == '__main__':
    main()
