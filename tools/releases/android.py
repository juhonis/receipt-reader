"""Build and inspect a signed alpha APK; never publishes or reads receipt data."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from version import ROOT, sync
sys.path.insert(0, str(ROOT / 'tools/licenses'))
import audit


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tool_invocation(arguments, env):
    """Invoke Windows batch tools without interpolating paths into shell syntax."""
    arguments = [str(value) for value in arguments]
    if os.name != 'nt' or Path(arguments[0]).suffix.lower() not in {'.bat', '.cmd'}:
        return arguments, env
    if any(any(character in value for character in ['"', '\r', '\n']) for value in arguments):
        raise ValueError('Batch tool arguments cannot contain quotes or line breaks')
    batch_env = dict(env)
    references = []
    for index, value in enumerate(arguments):
        name = f'RECEIPT_READER_BATCH_ARG_{index}'
        batch_env[name] = value
        references.append(f'"%{name}%"')
    # Expansion happens once inside quotes; /v:off preserves literal exclamation marks.
    shell = env.get('COMSPEC', str(Path(os.environ['SystemRoot']) / 'System32/cmd.exe'))
    command = subprocess.list2cmdline([shell]) + ' /d /v:off /s /c "' + ' '.join(references) + '"'
    return command, batch_env


def source_state():
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip())
    return commit, dirty


def verify_source_unchanged(commit, allow_dirty):
    current_commit, dirty = source_state()
    if current_commit != commit or (dirty and not allow_dirty):
        raise ValueError('Source changed during the release build; rebuild from the reviewed commit')
    return dirty


def inspect_apk(apk, version, certificate, aapt, signer, env):
    command, signer_env = tool_invocation([signer, 'verify', '--verbose', '--print-certs', apk], env)
    result = subprocess.check_output(command, env=signer_env, encoding='utf-8')
    fingerprints = [match[1].lower() for line in result.splitlines()
                    if (match := re.fullmatch(r'Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})',
                                              line.strip()))]
    if len(fingerprints) != 1:
        raise ValueError(f'Expected one APK signer certificate; parsed {len(fingerprints)}. '
                         'Check the apksigner output format and signer count.')
    if fingerprints[0] != certificate:
        raise ValueError(f'APK signer certificate SHA-256 is {fingerprints[0]}; expected {certificate}. '
                         'APK is not signed by the pinned permanent release certificate')
    if 'Verified using v2 scheme (APK Signature Scheme v2): true' not in result:
        raise ValueError('APK v2 signing verification failed')
    badging = subprocess.check_output([str(aapt), 'dump', 'badging', str(apk)], env=env, encoding='utf-8')
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.M)
    if not package or package.groups() != ('fi.juhonis.receipt_reader', str(version.build), version.name):
        raise ValueError('APK package/version differs from the release source')
    if not re.search(r"^native-code:.*'arm64-v8a'", badging, re.M):
        raise ValueError('APK does not contain the phone arm64 ABI')
    return {'applicationId': package[1], 'versionName': package[3], 'versionCode': int(package[2]),
            'certificateSha256': certificate, 'signatureV2Verified': True, 'arm64Included': True}


MLKIT_REGISTRARS = (
    'com.google.mlkit.common.internal.CommonComponentRegistrar',
    'com.google.mlkit.vision.common.internal.VisionCommonRegistrar',
    'com.google.mlkit.vision.text.internal.TextRegistrar',
)


def verify_mlkit_registrars(apk, env):
    """Check the optimized DEX, not just manifest entries or ProGuard source rules."""
    analyzer = audit.android_command_line_tools() / 'bin/apkanalyzer.bat'
    # This tool reads public APK code only; do not pass the build's signing values.
    analyzer_env = {key: value for key, value in env.items()
                    if not key.upper().startswith('RECEIPT_READER_')}
    for name in MLKIT_REGISTRARS:
        command, child = tool_invocation(
            [analyzer, 'dex', 'code', '--class', name, '--method', '<init>()V', apk], analyzer_env)
        result = subprocess.run(command, env=child, capture_output=True, encoding='utf-8', errors='replace')
        if result.returncode:
            diagnostic = (result.stderr.strip() or result.stdout.strip() or 'No tool diagnostic')[:4000]
            raise ValueError(f'APK analyzer failed (exit {result.returncode}) inspecting {name}:\n{diagnostic}')
        if not re.search(
                r'^\s*\.method\s+public\s+constructor\s+<init>\(\)V\s*$', result.stdout, re.M):
            raise ValueError('Optimized APK lacks a public ML Kit registrar constructor: ' + name)


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--allow-dirty', action='store_true', help='Local rehearsal only; output is marked development')
    cli.add_argument('--tag', help='Optional expected release tag, e.g. v0.2.0-alpha.1')
    args = cli.parse_args()
    version = sync(check=True, tag=args.tag)
    commit, dirty = source_state()
    if dirty and not args.allow_dirty:
        raise ValueError('Commit the reviewed source before building a distributable APK; --allow-dirty is rehearsal only')
    certificate = (ROOT / 'android/release-certificate.sha256').read_text(encoding='ascii').strip()
    if not re.fullmatch(r'[0-9a-f]{64}', certificate):
        raise ValueError('Missing or invalid pinned release certificate')
    env = dict(os.environ)
    env.setdefault('JAVA_HOME', 'C:/Program Files/Android/Android Studio/jbr')
    # Python 3.12 can otherwise find Flutter's extensionless Unix launcher first.
    flutter = shutil.which('flutter.bat' if os.name == 'nt' else 'flutter')
    if not flutter:
        raise ValueError('Windows Flutter is required on PATH')
    destination = ROOT / 'build/distribution' / ('rehearsal' if args.allow_dirty else 'releases')
    destination.mkdir(parents=True, exist_ok=True)
    artifact = destination / version.artifact
    if any(path.exists() for path in [artifact, artifact.with_suffix('.json'), artifact.with_suffix('.apk.sha256')]):
        raise ValueError('Versioned artifact already exists; do not silently replace a distributed version')
    # Review inputs must be current before starting an expensive build.
    audit.load_review()
    build_tools = audit.android_build_tools()
    print('Android verification build-tools:', build_tools.name, flush=True)
    # Project arguments retain their case through Flutter on Windows. Environment
    # names are uppercased by Python/Dart and cannot carry kotlin.incremental.
    command, flutter_env = tool_invocation(
        [flutter, 'build', 'apk', '--release', '--target=lib/main.dart',
         '--android-project-arg=kotlin.incremental=false'], env)
    subprocess.run(command, cwd=ROOT, env=flutter_env, check=True)
    apk = ROOT / 'build/app/outputs/flutter-apk/app-release.apk'
    metadata = inspect_apk(apk, version, certificate, build_tools / 'aapt2.exe', build_tools / 'apksigner.bat', env)
    verify_mlkit_registrars(apk, env)
    native, permissions = audit.verify_apk(apk)
    dirty = verify_source_unchanged(commit, args.allow_dirty) or dirty
    metadata.update({'version': version.full, 'tag': version.tag,
        'commit': commit,
        'workingTreeDirty': dirty, 'developmentBuild': dirty or args.allow_dirty,
        'apkSha256': sha256(apk), 'apkBytes': apk.stat().st_size,
        'noticeInventorySha256': sha256(ROOT / 'third_party/dependencies.json'),
        'applicationLicense': 'MIT', 'packagedNoticesVerified': True,
        'mlkitRegistrarConstructorsVerified': True,
        'nativeLibraries': native, 'permissions': permissions.splitlines(),
        'phoneAcceptanceComplete': False})
    with artifact.open('xb') as target, apk.open('rb') as source:
        shutil.copyfileobj(source, target)
    artifact.with_suffix('.apk.sha256').write_text(f"{metadata['apkSha256']}  {artifact.name}\n", encoding='ascii')
    artifact.with_suffix('.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    print('Verified APK:', artifact)
    print('Certificate SHA-256:', certificate)
    print('APK SHA-256:', metadata['apkSha256'])
    print('Phone acceptance remains required; no release was published.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from None
