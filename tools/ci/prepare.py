"""Prepare the reviewed Windows build inputs on a fresh GitHub-hosted runner."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/releases'))
from android import tool_invocation


def run(arguments, env, **kwargs):
    command, child_env = tool_invocation(arguments, env)
    return subprocess.run(command, cwd=ROOT, env=child_env, check=True, **kwargs)


def prepare(existing=False):
    if os.name != 'nt':
        raise ValueError('The audited release toolchain currently targets Windows runners')
    reviewed = json.loads((ROOT / 'third_party/dependencies.json').read_text(encoding='utf-8'))
    pin = reviewed['flutter']
    env = dict(os.environ)
    if existing:
        env.setdefault('JAVA_HOME', 'C:/Program Files/Android/Android Studio/jbr')
        entry = shutil.which('flutter.bat')
        if not entry:
            raise ValueError('Existing Windows Flutter was not found')
        sdk = Path(entry).resolve().parent.parent
    else:
        temporary = Path(env['RUNNER_TEMP']).resolve()
        sdk = temporary / 'receipt-flutter'
        if sdk.exists():
            raise ValueError('Expected a fresh runner Flutter directory')
        run(['git', '-c', 'core.autocrlf=false', 'clone', '--depth=1', '--branch',
             pin['frameworkVersion'], 'https://github.com/flutter/flutter.git', sdk], env)
        actual = subprocess.check_output(['git', '-C', str(sdk), 'rev-parse', 'HEAD'], text=True).strip()
        if actual != pin['frameworkRevision']:
            raise ValueError('Flutter release tag differs from the reviewed commit')
    env['FLUTTER_ROOT'] = str(sdk)
    flutter = sdk / 'bin/flutter.bat'
    run([flutter, '--version'], env)
    command, child_env = tool_invocation([flutter, '--version', '--machine'], env)
    actual = json.loads(subprocess.check_output(command, env=child_env, encoding='utf-8'))
    if any(actual.get(key) != value for key, value in pin.items()):
        raise ValueError('Flutter/Dart/engine revisions differ from the reviewed toolchain')
    android = Path(env.get('ANDROID_HOME') or env.get('ANDROID_SDK_ROOT') or
                   str(Path(env['LOCALAPPDATA']) / 'Android/Sdk')).resolve()
    if not android.is_dir():
        raise ValueError('Android SDK is not configured on this runner')
    env['ANDROID_HOME'] = env['ANDROID_SDK_ROOT'] = str(android)
    packages = ['platform-tools', 'platforms;android-35', 'platforms;android-36',
                'build-tools;36.0.0', 'ndk;' + reviewed['androidNdk']['version']]
    required = [android / item.replace(';', '/') for item in packages]
    if not all(path.is_dir() for path in required):
        manager = android / 'cmdline-tools/latest/bin/sdkmanager.bat'
        if not manager.is_file():
            raise ValueError('Install Android SDK command-line tools before CI setup')
        run([manager, '--sdk_root=' + str(android), '--licenses'], env, input='y\n' * 100, text=True)
        run([manager, '--sdk_root=' + str(android), *packages], env)
    if not existing:
        run([flutter, 'precache', '--windows', '--android'], env)
    run([flutter, 'pub', 'get', '--enforce-lockfile'], env)
    run([flutter, 'build', 'apk', '--debug', '--config-only'], env)
    run([ROOT / 'android/gradlew.bat', '-p', ROOT / 'android', '-I',
         ROOT / 'tools/licenses/android-inventory.init.gradle', ':app:receiptLicenseInventory',
         '--console=plain'], env)
    # These downloads/builds are public dependencies only, with source/model hashes.
    run([sys.executable, ROOT / 'tools/windows_ocr/setup.py'], env)
    # Verification must fail on drift; CI never blesses regenerated license evidence.
    run([sys.executable, ROOT / 'tools/licenses/audit.py'], env)
    for name in ['receipt_domain', 'receipt_parser', 'receipt_storage']:
        command, child_env = tool_invocation([sdk / 'bin/dart.bat', 'pub', 'get', '--enforce-lockfile'], env)
        subprocess.run(command, cwd=ROOT / 'packages' / name, env=child_env, check=True)
    if 'GITHUB_PATH' in env:
        with Path(env['GITHUB_PATH']).open('a', encoding='utf-8') as output:
            output.write(str(sdk / 'bin') + '\n')
        with Path(env['GITHUB_ENV']).open('a', encoding='utf-8') as output:
            output.write(f'FLUTTER_ROOT={sdk}\nANDROID_HOME={android}\nANDROID_SDK_ROOT={android}\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--existing', action='store_true', help='Local rehearsal using installed SDKs')
    args = parser.parse_args()
    try:
        prepare(args.existing)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from None
