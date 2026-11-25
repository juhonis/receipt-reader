"""Create a local development ZIP and rehearse relocation; no publishing."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
from setup import ROOT, LOCK, digest

sys.path.insert(0, str(ROOT / 'tools/licenses'))
import audit as license_audit
sys.path.insert(0, str(ROOT / 'tools/releases'))
from version import sync
from android import source_state, verify_source_unchanged

SYSTEM_DLLS = set('kernel32.dll ntdll.dll user32.dll gdi32.dll advapi32.dll shell32.dll ole32.dll oleaut32.dll ws2_32.dll combase.dll shlwapi.dll version.dll winmm.dll bcrypt.dll crypt32.dll imm32.dll msimg32.dll dwmapi.dll uxtheme.dll propsys.dll rpcrt4.dll setupapi.dll dxgi.dll d3d11.dll d3d9.dll dcomp.dll dwrite.dll d2d1.dll usp10.dll opengl32.dll winhttp.dll iphlpapi.dll secur32.dll netapi32.dll userenv.dll dbghelp.dll wintrust.dll psapi.dll oleacc.dll uiautomationcore.dll'.split())


def visual_studio():
    finder = Path(os.environ['ProgramFiles(x86)']) / 'Microsoft Visual Studio/Installer/vswhere.exe'
    return Path(subprocess.check_output([str(finder), '-latest', '-products', '*', '-requires',
        'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath'], text=True).strip())


def verify_bundle(bundle):
    manifest = json.loads((bundle / 'manifest.json').read_text(encoding='utf-8'))
    actual = {p.relative_to(bundle).as_posix() for p in bundle.rglob('*') if p.is_file() and p.name != 'manifest.json'}
    if actual != set(manifest['files']):
        raise ValueError('Unexpected or missing OCR bundle files')
    for name, expected in manifest['files'].items():
        if not re.fullmatch(r'[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*', name) or '..' in name.split('/'):
            raise ValueError('Invalid OCR bundle member')
        if digest(bundle / name) != expected:
            raise ValueError('OCR bundle checksum mismatch')
    if manifest['sources'] != LOCK:
        raise ValueError('OCR bundle does not match the pinned inputs')
    return manifest


def audit_imports(directory, install):
    compiler = sorted((install / 'VC/Tools/MSVC').iterdir())[-1]
    dumpbin = compiler / 'bin/Hostx64/x64/dumpbin.exe'
    root_libraries = {p.name.lower() for p in directory.iterdir() if p.suffix.lower() == '.dll'}
    audit = {}
    for binary in sorted(directory.rglob('*')):
        if binary.suffix.lower() not in ('.exe', '.dll'):
            continue
        data = binary.read_bytes()
        pe = struct.unpack_from('<I', data, 0x3c)[0]
        if data[pe:pe+4] != b'PE\0\0' or struct.unpack_from('<H',data,pe+4)[0] != 0x8664:
            raise ValueError('Non-x64 native dependency')
        text = subprocess.check_output([str(dumpbin), '/nologo', '/dependents', str(binary)], text=True)
        local_libraries = {p.name.lower() for p in binary.parent.iterdir() if p.suffix.lower() == '.dll'}
        owned = local_libraries if binary.name == 'receipt_ocr_worker.exe' else root_libraries | local_libraries
        names = re.findall(r'^\s+([\w.-]+\.dll)\s*$', text, re.MULTILINE | re.IGNORECASE)
        for name in names:
            lower = name.lower()
            if lower not in owned and lower not in SYSTEM_DLLS and not lower.startswith(('api-ms-win-', 'ext-ms-win-')):
                raise ValueError('Unbundled dependency: ' + binary.name + ': ' + name)
        audit[binary.relative_to(directory).as_posix()] = sorted(set(names), key=str.lower)
    return audit


def relocation(bundle):
    env = {'SystemRoot': os.environ['SystemRoot'], 'WINDIR': os.environ['SystemRoot'],
        'PATH': str(Path(os.environ['SystemRoot']) / 'System32')}
    executable = bundle / 'receipt_ocr_worker.exe'
    version = subprocess.check_output([str(executable), '--version'], cwd=bundle, env=env, text=True).strip()
    if version != 'receipt-ocr/1 tesseract/' + LOCK['tesseract']['version']:
        raise ValueError('Unexpected worker version')
    pixels = b'RRO1' + struct.pack('<II', 64, 64) + bytes([255]) * (64 * 64 * 4)
    result = subprocess.run([str(executable)], input=pixels, cwd=bundle, env=env, capture_output=True, timeout=30)
    if result.returncode or result.stderr or not result.stdout.startswith(b'level\tpage_num\t'):
        raise ValueError('Relocated model initialization failed')
    before = {p.relative_to(bundle).as_posix(): digest(p) for p in bundle.rglob('*') if p.is_file()}
    for bad in [b'', b'NOPE' + pixels[4:], b'RRO1' + struct.pack('<II', 12001, 1), pixels[:-1], pixels + b'x']:
        failed = subprocess.run([str(executable)], input=bad, cwd=bundle, env=env, capture_output=True, timeout=10)
        if failed.returncode != 2 or failed.stdout:
            raise ValueError('Invalid worker input was accepted')
    after = {p.relative_to(bundle).as_posix(): digest(p) for p in bundle.rglob('*') if p.is_file()}
    if before != after:
        raise ValueError('OCR modified its runtime directory')
    return {'workerVersion': version, 'sanitizedPath': True, 'unicodeAndSpacePath': True,
        'modelInitialization': True, 'invalidInputRejections': 5, 'runtimeFilesUnchanged': True,
        'cleanMachineVerified': False, 'publicReleaseReady': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', help='Create an immutable versioned alpha candidate for this tag')
    parser.add_argument('--allow-dirty', action='store_true', help='Versioned local rehearsal only')
    args = parser.parse_args()
    if args.allow_dirty and not args.tag:
        raise ValueError('--allow-dirty is only needed with --tag')
    version = sync(check=True, tag=args.tag)
    commit, dirty = source_state()
    candidate = args.tag is not None
    if candidate and dirty and not args.allow_dirty:
        raise ValueError('A versioned Windows candidate requires a clean reviewed commit')
    release = ROOT / 'build/windows/x64/runner/Release'
    if not (release / 'receipt_reader.exe').is_file():
        raise RuntimeError('Build the normal Windows release first')
    verify_bundle(release / 'ocr')
    install = visual_studio()
    distribution = ROOT / 'build/distribution'
    if candidate:
        distribution /= 'rehearsal' if args.allow_dirty else 'releases'
    distribution.mkdir(parents=True, exist_ok=True)
    # Only directories created here, under the verified build directory, are cleaned.
    if not distribution.resolve().is_relative_to(ROOT.resolve()):
        raise RuntimeError('Unexpected packaging root')
    artifact = distribution / (version.windows_artifact if candidate else 'receipt-reader-windows-x64-dev.zip')
    if candidate and any(path.exists() for path in [artifact, artifact.with_suffix('.json'), artifact.with_suffix('.zip.sha256')]):
        raise ValueError('Versioned artifact already exists; do not replace a distributed version')
    work = Path(tempfile.mkdtemp(prefix='receipt-zip-', dir=distribution)).resolve()
    if not work.is_relative_to(distribution.resolve()):
        raise RuntimeError('Unexpected packaging directory')
    try:
        stage = work / 'Receipt Reader'
        shutil.copytree(release, stage, ignore=shutil.ignore_patterns('*.pdb', '*.lib', '*.exp'))
        redist = sorted(p for p in (install / 'VC/Redist/MSVC').iterdir() if re.fullmatch(r'\d+\.\d+\.\d+', p.name))[-1]
        crt = redist / 'x64/Microsoft.VC143.CRT'
        for library in crt.glob('*.dll'):
            shutil.copy2(library, stage / library.name)
        if not (stage / 'vcruntime140.dll').is_file():
            raise RuntimeError('Visual C++ redistributable runtime missing')
        imports = audit_imports(stage, install)
        license_text = license_audit.verify_windows(stage)
        (stage / 'THIRD-PARTY-NOTICES.txt').write_text(license_text, encoding='utf-8')
        shutil.copy2(ROOT / 'third_party/dependencies.json', stage / 'THIRD-PARTY-COMPONENTS.json')
        shutil.copy2(ROOT / 'LICENSE', stage / 'LICENSE.txt')
        shutil.copy2(ROOT / 'test/fixtures/synthetic_receipt.png', stage / 'synthetic_receipt.png')
        shutil.copy2(ROOT / 'docs/windows-ocr-clean-machine.md', stage / 'CLEAN-MACHINE-TEST.txt')
        heading = 'Unsigned alpha candidate; acceptance remains pending.\n' if candidate else 'Development test build, not a public release.\n'
        (stage / 'READ-ME.txt').write_text(heading + 'Extract the entire folder, then run receipt_reader.exe.\nOCR works locally; no Tesseract/Python installation is required.\nReceipt data is stored in Windows application-support storage, not in this folder.\nKeep independent encrypted backups before replacing or deleting application data.\nSoftware notices: THIRD-PARTY-NOTICES.txt and the app information/license screen.\nExact component inventory: THIRD-PARTY-COMPONENTS.json. Original OCR notices: ocr/notices.\nPublic distribution acceptance remains a separate owner step.\n', encoding='utf-8')
        info = {'developmentBuild': not candidate or dirty or args.allow_dirty,
            'version': version.full, 'tag': version.tag, 'applicationLicense': 'MIT',
            'publicReleaseReady': False, 'executableSigned': False,
            'commit': commit,
            'workingTreeDirty': dirty,
            'ocr': verify_bundle(stage / 'ocr'), 'visualCppRuntime': redist.name,
            'visualCppRuntimeFiles': {p.name: digest(p) for p in sorted(crt.glob('*.dll'))},
            'nativeImports': imports, 'nativeNoticesVerified': True,
            'thirdPartyInventorySha256': digest(stage / 'THIRD-PARTY-COMPONENTS.json')}
        (stage / 'BUILD-INFO.json').write_text(json.dumps(info,indent=2)+'\n',encoding='utf-8')
        if candidate:
            verify_source_unchanged(commit, args.allow_dirty)
        with zipfile.ZipFile(artifact,'x' if candidate else 'w',compression=zipfile.ZIP_DEFLATED) as archive:
            for file in sorted(stage.rglob('*')):
                if file.is_file(): archive.write(file, Path('Receipt Reader') / file.relative_to(stage))
        relocated = work / 'Relocated Receipt Ä'
        with zipfile.ZipFile(artifact) as archive:
            archive.extractall(relocated)
        shipped = relocated / 'Receipt Reader'
        verify_bundle(shipped / 'ocr')
        evidence = relocation(shipped / 'ocr')
        evidence.update({'zipSha256': digest(artifact), 'zipBytes': artifact.stat().st_size,
            'version': version.full, 'tag': version.tag, 'applicationLicense': 'MIT',
            'developmentBuild': info['developmentBuild'], 'executableSigned': False,
            'nativeNoticesVerified': True, 'thirdPartyInventorySha256': info['thirdPartyInventorySha256'],
            'uncompressedBytes': sum(p.stat().st_size for p in stage.rglob('*') if p.is_file()),
            'nativeImportAudit': True, 'commit': info['commit'], 'workingTreeDirty': info['workingTreeDirty']})
        evidence_path = artifact.with_suffix('.json') if candidate else distribution / 'windows-ocr-evidence.json'
        with evidence_path.open('x' if candidate else 'w', encoding='utf-8', newline='\n') as target:
            target.write(json.dumps(evidence,indent=2)+'\n')
        if candidate:
            with artifact.with_suffix('.zip.sha256').open('x', encoding='ascii', newline='\n') as target:
                target.write(evidence['zipSha256'] + '  ' + artifact.name + '\n')
        print(str(artifact.relative_to(ROOT)))
        print(json.dumps(evidence,indent=2))
    finally:
        if not work.resolve().is_relative_to(distribution.resolve()) or not work.name.startswith('receipt-zip-'):
            raise RuntimeError('Unexpected packaging cleanup target')
        shutil.rmtree(work)


if __name__ == '__main__':
    main()
