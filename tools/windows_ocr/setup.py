"""Explicit Windows-only build setup; downloads public sources/models, never receipts."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build' / 'windows-ocr'
LOCK = json.loads((HERE / 'sources.json').read_text(encoding='utf-8'))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def download(url, target, expected=None):
    if not target.exists() or (expected and digest(target) != expected):
        data = urlopen(url, timeout=60).read()
        if expected and hashlib.sha256(data).hexdigest() != expected:
            raise ValueError('Public dependency checksum mismatch')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    if expected and digest(target) != expected:
        raise ValueError('Public dependency checksum mismatch')


def cmake_path():
    if shutil.which('cmake'):
        return shutil.which('cmake')
    finder = Path(os.environ['ProgramFiles(x86)']) / 'Microsoft Visual Studio/Installer/vswhere.exe'
    install = subprocess.check_output([str(finder), '-latest', '-products', '*', '-requires',
        'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath'], text=True).strip()
    result = Path(install) / 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
    if not result.is_file():
        raise RuntimeError('Install Visual Studio C++ CMake tools first')
    return str(result)


def run(args):
    with (OUT / 'setup.log').open('a', encoding='utf-8') as log:
        log.write(repr(args) + '\n')
        log.flush()
        result = subprocess.run(args, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError('Native build failed; inspect build/windows-ocr/setup.log')


def main():
    if os.name != 'nt':
        raise RuntimeError('Use the Windows Python/toolchain for this build')
    OUT.mkdir(parents=True, exist_ok=True)
    cmake = cmake_path()
    sources = {}
    for name in ('leptonica', 'tesseract'):
        entry = LOCK[name]
        archive = OUT / (name + '.tar.gz')
        download(entry['url'], archive, entry['sha256'])
        source = OUT / 'sources' / entry['directory']
        if not source.is_dir():
            with tarfile.open(archive) as package:
                package.extractall(OUT / 'sources', filter='data')
        sources[name] = source
    prefix = OUT / 'prefix'
    common = ['-G', 'Visual Studio 17 2022', '-A', 'x64', '-DBUILD_SHARED_LIBS=OFF',
        '-DSW_BUILD=OFF', '-DCMAKE_POLICY_DEFAULT_CMP0091=NEW', '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded', '-DCMAKE_INSTALL_PREFIX=' + str(prefix)]
    lept = OUT / 'leptonica-build'
    print('Building pinned Leptonica without image codecs...', flush=True)
    run([cmake, '-S', str(sources['leptonica']), '-B', str(lept), *common, '-DBUILD_PROG=OFF',
        *['-DENABLE_' + feature + '=OFF' for feature in ('ZLIB', 'PNG', 'GIF', 'JPEG', 'TIFF', 'WEBP', 'OPENJPEG')]])
    run([cmake, '--build', str(lept), '--config', 'Release', '--target', 'install', '--parallel', '4'])
    tess = OUT / 'tesseract-build'
    print('Building pinned Tesseract LSTM library...', flush=True)
    run([cmake, '-S', str(sources['tesseract']), '-B', str(tess), *common,
        '-DCMAKE_PREFIX_PATH=' + str(prefix), '-DWIN32_MT_BUILD=ON', '-DBUILD_TRAINING_TOOLS=OFF',
        '-DBUILD_TESTS=OFF', '-DOPENMP_BUILD=OFF', '-DGRAPHICS_DISABLED=ON', '-DDISABLED_LEGACY_ENGINE=ON',
        '-DDISABLE_ARCHIVE=ON', '-DDISABLE_CURL=ON', '-DDISABLE_TIFF=ON', '-DENABLE_NATIVE=OFF'])
    run([cmake, '--build', str(tess), '--config', 'Release', '--target', 'libtesseract', '--parallel', '4'])
    worker = OUT / 'worker-build'
    print('Building bounded in-memory OCR worker...', flush=True)
    run([cmake, '-S', str(HERE), '-B', str(worker), *common, '-DCMAKE_PREFIX_PATH=' + str(prefix),
        '-DTESSERACT_BUILD=' + str(tess)])
    run([cmake, '--build', str(worker), '--config', 'Release', '--parallel', '4'])
    bundle = OUT / 'bundle'
    (bundle / 'tessdata').mkdir(parents=True, exist_ok=True)
    (bundle / 'notices').mkdir(exist_ok=True)
    shutil.copy2(worker / 'Release/receipt_ocr_worker.exe', bundle / 'receipt_ocr_worker.exe')
    expected_files = {'receipt_ocr_worker.exe', 'tessdata/fin.traineddata', 'tessdata/eng.traineddata',
        'notices/tesseract.txt', 'notices/leptonica.txt', 'notices/models.txt'}
    for name, source in sources.items():
        shutil.copy2(source / ('leptonica-license.txt' if name == 'leptonica' else 'LICENSE'), bundle / 'notices' / (name + '.txt'))
        if (source / 'NOTICE').exists():
            expected_files.add('notices/' + name + '-NOTICE.txt')
            shutil.copy2(source / 'NOTICE', bundle / 'notices' / (name + '-NOTICE.txt'))
    for language in ('fin', 'eng'):
        entry = LOCK['models']
        url = 'https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/' + entry['revision'] + '/' + language + '.traineddata'
        download(url, bundle / 'tessdata' / (language + '.traineddata'), entry[language])
    download('https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/' + LOCK['models']['revision'] + '/LICENSE',
        bundle / 'notices/models.txt', LOCK['models']['licenseSha256'])
    actual = {p.relative_to(bundle).as_posix() for p in bundle.rglob('*') if p.is_file() and p.name != 'manifest.json'}
    if actual != expected_files:
        raise ValueError('Unexpected files in OCR build staging directory')
    manifest = {'schemaVersion': 1, 'architecture': 'x64', 'engine': 'tesseract', 'version': LOCK['tesseract']['version'],
        'leptonica': LOCK['leptonica']['version'], 'languages': 'fin+eng', 'modelFamily': 'tessdata_fast',
        'modelRevision': LOCK['models']['revision'], 'pageSegmentationMode': 6, 'protocol': 'RRO1',
        'sources': LOCK, 'files': {p.relative_to(bundle).as_posix(): digest(p) for p in sorted(bundle.rglob('*')) if p.is_file() and p.name != 'manifest.json'}}
    (bundle / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print('Built app-owned OCR bundle at build/windows-ocr/bundle', flush=True)
    print(subprocess.check_output([str(bundle / 'receipt_ocr_worker.exe'), '--version'], text=True).strip())


if __name__ == '__main__':
    main()
