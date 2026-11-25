"""Inventory public dependencies and preserve notices; never reads receipt data."""
import argparse
import gzip
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[2]
THIRD = ROOT / 'third_party'
SEPARATOR = '\n' + '-' * 80 + '\n'
GOOGLE_TERMS = 'https://developers.google.com/ml-kit/terms'
ANDROID_TERMS = 'https://developer.android.com/studio/terms.html'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    return digest(Path(path).read_bytes())


def canonical(value):
    return json.dumps(value, ensure_ascii=False, indent=2) + '\n'


def config_packages():
    config = ROOT / '.dart_tool/package_config.json'
    result = {}
    for p in json.loads(config.read_text(encoding='utf-8'))['packages']:
        uri = p['rootUri']
        if uri.startswith('file:'):
            path = Path(unquote(urlparse(uri).path).lstrip('/'))
        else:
            path = (config.parent / unquote(uri)).resolve()
        result[p['name']] = path
    return result


def read_pom(path):
    root = ET.parse(path).getroot()
    for e in root.iter():
        e.tag = e.tag.rsplit('}', 1)[-1]
    return [{'name': x.findtext('name'), 'url': x.findtext('url')}
            for x in root.findall('licenses/license')]


def android_sdk():
    for line in (ROOT / 'android/local.properties').read_text(encoding='utf-8').splitlines():
        if line.startswith('sdk.dir='):
            return Path(line[8:].replace('\\\\', '\\').replace('\\:', ':'))
    raise ValueError('Android SDK directory is not configured')


def notice_family(name, notice, owned):
    if notice is None:
        return 'project-owned; repository MIT license'
    text = notice.read_text(encoding='utf-8')
    if name == 'sky_engine':
        return 'upstream engine aggregate; preserve all terms and exceptions'
    if len(text) > 20000:
        raise ValueError('Review combined Dart notice: ' + name)
    if 'Apache License' in text and 'Version 2.0' in text:
        return 'Apache-2.0'
    if 'Permission is hereby granted' in text:
        return 'MIT'
    if 'Redistribution and use' in text:
        return 'BSD-3-Clause' if 'neither' in text.lower() else 'BSD-2-Clause'
    raise ValueError('Review unfamiliar Dart license: ' + name)


def notice_sections(index, raw):
    """Google AAR offsets are byte offsets, not Unicode character offsets."""
    entries = json.loads(index)
    if not isinstance(entries, dict):
        raise ValueError('Invalid upstream notice index')
    for name, location in sorted(entries.items()):
        start, length = location['start'], location['length']
        if (type(start) is not int or type(length) is not int or
                start < 0 or length <= 0 or start + length > len(raw)):
            raise ValueError('Invalid upstream notice range')
        yield name, raw[start:start + length]


def embedded_notices(path):
    def scan(blob, prefix=''):
        with zipfile.ZipFile(blob) as archive:
            names = set(archive.namelist())
            if 'third_party_licenses.json' in names:
                index = archive.read('third_party_licenses.json')
                raw = archive.read('third_party_licenses.txt')
                for name, text in notice_sections(index, raw):
                    yield name, prefix + 'third_party_licenses.txt', text
            for item in archive.infolist():
                name = item.filename
                if name.lower().endswith('.jar'):
                    if item.file_size > 64 * 1024 * 1024:
                        raise ValueError('Oversized nested dependency archive')
                    yield from scan(io.BytesIO(archive.read(item)), prefix + name + '!/')
                elif (Path(name).name.upper().startswith(('LICENSE', 'NOTICE', 'COPYING'))
                      and not name.endswith('/')):
                    if item.file_size > 8 * 1024 * 1024:
                        raise ValueError('Oversized dependency notice')
                    yield 'embedded ' + name, prefix + name, archive.read(item)
    yield from scan(path)


def collect():
    paths = config_packages()
    sdk = paths['flutter'].parent.parent
    flutter = json.loads((sdk / 'bin/cache/flutter.version.json').read_text())
    dart_exe = sdk / 'bin/cache/dart-sdk/bin' / ('dart.exe' if os.name == 'nt' else 'dart')
    graph = json.loads(subprocess.check_output(
        [str(dart_exe), 'pub', 'deps', '--json'], cwd=ROOT, encoding='utf-8',
        env={**os.environ, 'FLUTTER_ROOT': str(sdk)}))
    packages = {p['name']: p for p in graph['packages']}
    pending = list(packages[graph['root']]['directDependencies'])
    runtime = set()
    while pending:
        name = pending.pop()
        if name not in runtime:
            runtime.add(name)
            pending.extend(packages[name].get('directDependencies', []))
    dart = []
    for name in sorted(runtime):
        p, path = packages[name], paths[name]
        notice = next((path / n for n in ['NOTICES', 'LICENSE'] if (path / n).is_file()), None)
        if notice is None and p['source'] == 'sdk' and path.is_relative_to(sdk):
            notice = sdk / 'LICENSE'
        owned = path.is_relative_to(ROOT)
        if notice is None and not owned:
            raise ValueError('Unreviewed Dart dependency without notices: ' + name)
        dart.append({'name': name, 'version': p['version'], 'source': p['source'],
                     'noticeFamily': notice_family(name, notice, owned),
                     'noticeFile': notice.name if notice else None,
                     'noticeSha256': file_digest(notice) if notice else None,
                     'handling': 'project-owned' if owned else 'Flutter NOTICES.Z'})

    inventory = json.loads((ROOT / 'build/licenses/android-artifacts.json').read_text())
    if inventory['schemaVersion'] != 1 or inventory['configuration'] != 'releaseRuntimeClasspath':
        raise ValueError('Unexpected Android inventory')
    for name, expected in inventory['inputs'].items():
        if file_digest(ROOT / name) != expected:
            raise ValueError('Stale Android inventory; rerun Gradle inventory: ' + name)
    blocks, evidence = {}, []

    def add(name, raw, origin):
        text = raw.decode('utf-8').replace('\r\n', '\n').replace('\r', '\n')
        # Whitespace only: do not let a literal license separator split an entry.
        text = text.replace(SEPARATOR, '\n ' + '-' * 80 + '\n')
        key = digest(text.encode('utf-8'))
        entry = blocks.setdefault(key, {'names': set(), 'text': text})
        entry['names'].add(name.replace('\n', ' ').replace('\r', ' '))
        evidence.append({'name': name, 'origin': origin,
                         'sourceSha256': digest(raw), 'displaySha256': key})

    # Preserve source notices explicitly as well: SDK-generated NOTICES can
    # contain a copyright stub that refers to a LICENSE file not shipped beside it.
    for p in dart:
        # The engine aggregate is already split into individual readable entries
        # by Flutter. Verify all its bodies in the artifact instead of adding a
        # second giant entry containing the entire aggregate.
        if p['noticeFile'] and p['name'] != 'sky_engine':
            source = paths[p['name']] / p['noticeFile']
            if not source.is_file() and p['source'] == 'sdk':
                source = sdk / 'LICENSE'
            add('Dart: ' + p['name'] + ' ' + p['version'], source.read_bytes(),
                'Dart ' + p['name'] + '/' + p['noticeFile'])

    bundle = ROOT / 'build/windows-ocr/bundle'
    ocr = json.loads((bundle / 'manifest.json').read_text())
    if ocr['sources'] != json.loads((ROOT / 'tools/windows_ocr/sources.json').read_text()):
        raise ValueError('Stale OCR preparation')
    for name, expected in ocr['files'].items():
        if file_digest(bundle / name) != expected:
            raise ValueError('Changed OCR bundle: ' + name)
        if name.startswith('notices/'):
            add('Windows OCR: ' + name.split('/')[-1], (bundle / name).read_bytes(), name)
    apache = (bundle / 'notices/tesseract.txt').read_bytes()
    if b'Apache License' not in apache:
        raise ValueError('Expected pinned Apache license')
    add('Dart native runtime', (sdk / 'bin/cache/dart-sdk/LICENSE').read_bytes(),
        'Dart SDK/LICENSE')
    for relative in ['src/third_party/global_jni_env.c', 'src/include/dart_api_dl.c']:
        raw = (paths['jni'] / relative).read_bytes()
        header = re.search(rb'/\*.*?\*/', raw, re.DOTALL)
        if header is None or b'Copyright' not in header.group():
            raise ValueError('Missing JNI source copyright header')
        add('Android JNI native bridge: ' + relative, header.group(),
            'Dart jni/' + relative + '#copyright-header')
    ndk_notice = android_sdk() / 'ndk' / inventory['ndkVersion'] / 'toolchains/llvm/prebuilt/windows-x86_64/sysroot/NOTICE'
    add('Android NDK sysroot/runtime notices', ndk_notice.read_bytes(),
        'Android NDK ' + inventory['ndkVersion'] + '/sysroot/NOTICE')

    android, seen = [], set()
    for row in inventory['artifacts']:
        artifact, pom = Path(row['file']), Path(row['pom'])
        component = row['component']
        artifact_hash = file_digest(artifact)
        identity = (component, artifact.name, artifact_hash)
        if identity in seen:
            continue
        seen.add(identity)
        declared = read_pom(pom)
        handling = 'POM license and embedded notices'
        if not declared:
            if component.startswith('io.flutter:') and component.endswith(flutter['engineRevision']):
                handling = 'Flutter engine aggregate in Flutter NOTICES.Z'
            elif component == 'com.google.guava:listenablefuture:1.0':
                declared = [{'name': 'Apache-2.0 (inherited from guava-parent:26.0-android)',
                    'url': 'https://repo.maven.apache.org/maven2/com/google/guava/guava-parent/26.0-android/guava-parent-26.0-android.pom'}]
            else:
                raise ValueError('Unreviewed Maven license: ' + component)
        elif not all(x['url'] in [GOOGLE_TERMS, ANDROID_TERMS,
                'http://www.apache.org/licenses/LICENSE-2.0.txt',
                'https://www.apache.org/licenses/LICENSE-2.0.txt'] for x in declared):
            raise ValueError('Review new Maven license: ' + component)
        if declared and all('Apache' in x['name'] for x in declared):
            add('Android: ' + component, apache, component + ' POM')
        for name, origin, raw in embedded_notices(artifact):
            label = ('Android Google SDK: ' + name if 'third_party_licenses.txt' in origin
                     else 'Android: ' + component + ': ' + name)
            add(label, raw, component + '!/' + origin)
        android.append({'component': component, 'artifact': artifact.name,
                        'artifactSha256': artifact_hash, 'pomSha256': file_digest(pom),
                        'declaredLicenses': declared, 'handling': handling})

    add('SQLite native engine', b'SQLite is dedicated to the public domain by its authors.\n'
        b'Source and copyright statement: https://sqlite.org/copyright.html\n'
        b'The separate sqlite3 Dart wrapper is MIT licensed; see its entry.\n',
        'https://sqlite.org/copyright.html')
    add('Microsoft Visual C++ runtime (Windows)',
        b'Microsoft Visual C++ runtime components are distributed unmodified with this application.\n'
        b'They remain subject to Microsoft terms, not an open-source license for this application.\n'
        b'Redistribution list: https://learn.microsoft.com/visualstudio/releases/2022/redistribution\n',
        'https://learn.microsoft.com/visualstudio/releases/2022/redistribution')
    add('Google ML Kit and Play services (Android)',
        b'These Google SDK components and bundled models are governed by their vendor terms.\n'
        b'ML Kit: https://developers.google.com/ml-kit/terms\n'
        b'Google APIs terms: https://developers.google.com/terms\n'
        b'Android SDK terms: https://developer.android.com/studio/terms.html\n'
        b'Data disclosure: https://developers.google.com/ml-kit/android-data-disclosure\n'
        b'Open-source notices supplied inside the SDK artifacts are retained separately below.\n', GOOGLE_TERMS)
    notices = SEPARATOR.join('\n'.join(sorted(e['names'])) + '\n\n' + e['text']
                             for _, e in sorted(blocks.items())) + '\n'
    manifest = {'schemaVersion': 1, 'reviewDate': '2026-11-25',
        'scope': 'Conservative supported-target inventory; includes upstream aggregate notices',
        'inputs': inventory['inputs'],
        'flutter': {k: flutter[k] for k in ['frameworkVersion', 'frameworkRevision', 'engineRevision', 'dartSdkVersion']},
        'dartRuntimePackages': dart,
        'androidReleaseArtifacts': sorted(android, key=lambda a: (a['component'], a['artifact'], a['artifactSha256'])),
        'androidNdk': {'version': inventory['ndkVersion'], 'sysrootNoticeSha256': file_digest(ndk_notice)},
        'windowsOcrSources': ocr['sources'],
        'sqliteNativeAssets': {name: value for name, value in re.findall(r"'([^']+)': '([0-9a-f]{64})'",
            (paths['sqlite3'] / 'lib/src/hook/asset_hashes.dart').read_text())
            if name in {'sqlite3.x64.windows.dll', 'libsqlite3.arm.android.so',
                        'libsqlite3.arm64.android.so', 'libsqlite3.x64.android.so'}},
        'noticeSources': sorted(evidence, key=lambda e: (e['origin'], e['name'])),
        'noticeBlocks': len(blocks), 'noticeSha256': digest(notices.encode('utf-8'))}
    return manifest, notices


def load_review():
    result = json.loads((THIRD / 'dependencies.json').read_text(encoding='utf-8'))
    for name, expected in result['inputs'].items():
        if file_digest(ROOT / name) != expected:
            raise ValueError('Review inventory is stale: ' + name)
    if file_digest(THIRD / 'NOTICES.txt') != result['noticeSha256']:
        raise ValueError('Changed or missing native notices')
    paths = config_packages()
    sdk = paths['flutter'].parent.parent
    flutter = json.loads((sdk / 'bin/cache/flutter.version.json').read_text())
    if any(flutter[k] != v for k, v in result['flutter'].items()):
        raise ValueError('Review inventory is stale for the Flutter SDK')
    for p in result['dartRuntimePackages']:
        if p['noticeFile']:
            source = paths[p['name']] / p['noticeFile']
            if not source.is_file() and p['source'] == 'sdk':
                source = sdk / 'LICENSE'
            if file_digest(source) != p['noticeSha256']:
                raise ValueError('Changed Dart notice: ' + p['name'])
    return result


def verify_notices(blob):
    review = load_review()
    text = gzip.decompress(blob).decode('utf-8')
    if (ROOT / 'LICENSE').read_text(encoding='utf-8').strip() not in text:
        raise ValueError('Packaged notices omit application MIT license')
    if (THIRD / 'NOTICES.txt').read_text(encoding='utf-8') not in text:
        raise ValueError('Packaged Flutter notices omit native notices')
    paths = config_packages()
    sdk = paths['flutter'].parent.parent
    for p in review['dartRuntimePackages']:
        if not p['noticeFile']:
            continue
        source = paths[p['name']] / p['noticeFile']
        if not source.is_file() and p['source'] == 'sdk':
            source = sdk / 'LICENSE'
        original = source.read_text(encoding='utf-8')
        parts = original.split(SEPARATOR)
        for part in parts:
            body = part.split('\n\n', 1)[-1] if len(parts) > 1 else part
            if body.strip() and body.strip() not in text:
                raise ValueError('Packaged notices omit Dart text: ' + p['name'])
    return text


def verify_windows(directory):
    review = load_review()
    text = verify_notices((directory / 'data/flutter_assets/NOTICES.Z').read_bytes())
    if file_digest(directory / 'sqlite3.dll') != review['sqliteNativeAssets']['sqlite3.x64.windows.dll']:
        raise ValueError('Unexpected Windows SQLite binary')
    return text


def verify_apk(path):
    review = load_review()
    ndk = android_sdk() / 'ndk' / review['androidNdk']['version']
    if file_digest(ndk / 'toolchains/llvm/prebuilt/windows-x86_64/sysroot/NOTICE') != review['androidNdk']['sysrootNoticeSha256']:
        raise ValueError('Changed Android NDK notices')
    strip = ndk / 'toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip.exe'
    with zipfile.ZipFile(path) as archive:
        verify_notices(archive.read('assets/flutter_assets/NOTICES.Z'))
        native = sorted(n for n in archive.namelist() if n.startswith('lib/') and n.endswith('.so'))
        for abi, arch in {'armeabi-v7a': 'arm', 'arm64-v8a': 'arm64', 'x86_64': 'x64'}.items():
            expected = review['sqliteNativeAssets']['libsqlite3.' + arch + '.android.so']
            source = ROOT / ('.dart_tool/hooks_runner/shared/sqlite3/build/download-' + expected[:8] + '/libsqlite3.so')
            if file_digest(source) != expected:
                raise ValueError('Unexpected SQLite input for ' + abi)
            # AGP strips the downloaded asset. Reproduce that transformation
            # rather than incorrectly comparing the stripped and input hashes.
            parent = ROOT / 'build/licenses'
            parent.mkdir(parents=True, exist_ok=True)
            with tempfile.TemporaryDirectory(prefix='license-strip-', dir=parent) as name:
                work = Path(name).resolve()
                if not work.is_relative_to(parent.resolve()):
                    raise ValueError('Unexpected temporary strip directory')
                target = work / 'libsqlite3.so'
                shutil.copy2(source, target)
                subprocess.run([str(strip), '--strip-unneeded', str(target)], check=True)
                if file_digest(target) != digest(archive.read('lib/' + abi + '/libsqlite3.so')):
                    raise ValueError('Unexpected packaged SQLite binary for ' + abi)
    tools = [p for p in (android_sdk() / 'build-tools').iterdir() if (p / 'aapt2.exe').is_file()]
    aapt = max(tools, key=lambda p: tuple(map(int, re.findall(r'\d+', p.name)))) / 'aapt2.exe'
    permissions = subprocess.check_output([str(aapt), 'dump', 'permissions', str(path)], encoding='utf-8')
    if any(p in permissions for p in ['android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE']):
        raise ValueError('Standalone release unexpectedly requests network permissions')
    return native, permissions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument('--generate', action='store_true')
    actions.add_argument('--windows', type=Path)
    actions.add_argument('--apk', type=Path)
    args = parser.parse_args()
    if args.windows:
        verify_windows(args.windows)
        print('Windows native notices and SQLite provenance verified')
    elif args.apk:
        native, permissions = verify_apk(args.apk)
        with zipfile.ZipFile(args.apk) as archive:
            native_hashes = {name: digest(archive.read(name)) for name in native}
        evidence = {'apkSha256': file_digest(args.apk), 'permissions': permissions,
                    'nativeLibraries': native_hashes,
                    'sqliteStrippingReproduced': True,
                    'noticeInventorySha256': file_digest(THIRD / 'dependencies.json')}
        (ROOT / 'build/licenses/android-release-evidence.json').write_text(
            canonical(evidence), encoding='utf-8', newline='\n')
        print('Android notices, SQLite provenance and offline permissions verified; native libraries: ' + str(len(native)))
    else:
        manifest, notices = collect()
        expected = {'dependencies.json': canonical(manifest), 'NOTICES.txt': notices}
        for name, text in expected.items():
            if args.generate:
                (THIRD / name).write_text(text, encoding='utf-8', newline='\n')
            elif (THIRD / name).read_text(encoding='utf-8') != text:
                raise ValueError('Stale generated notice evidence: ' + name)
        print(('Generated' if args.generate else 'Verified') + ' notices: ' +
            str(len(manifest['dartRuntimePackages'])) + ' Dart packages, ' +
            str(len(manifest['androidReleaseArtifacts'])) + ' Android artifacts, ' +
            str(manifest['noticeBlocks']) + ' supplemental notice blocks')


if __name__ == '__main__':
    main()
