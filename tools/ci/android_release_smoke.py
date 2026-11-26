"""Build/check optimized Android OCR code with the emulator key; never distribute it."""
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/releases'))
from android import tool_invocation, verify_mlkit_registrars


def check_release(env=None, run=subprocess.run, verify=verify_mlkit_registrars):
    env = dict(os.environ if env is None else env)
    home = Path(env.get('ANDROID_USER_HOME') or str(Path.home() / '.android'))
    key = home / 'debug.keystore'
    if not key.is_file():
        raise ValueError('Compile the debug APK first to create its emulator-only signing key')
    flutter = shutil.which('flutter.bat')
    if not flutter:
        raise ValueError('Windows Flutter is required on PATH')
    # No production identity, signing secret, versioned asset or upload is used.
    env.pop('RECEIPT_READER_KEYSTORE_BASE64', None)
    env.update({'RECEIPT_READER_STORE_FILE': str(key), 'RECEIPT_READER_STORE_PASSWORD': 'android',
                'RECEIPT_READER_KEY_ALIAS': 'androiddebugkey', 'RECEIPT_READER_KEY_PASSWORD': 'android'})
    command, child = tool_invocation(
        [flutter, 'build', 'apk', '--release', '--target=lib/main.dart',
         '--android-project-arg=kotlin.incremental=false'], env)
    run(command, cwd=ROOT, env=child, check=True)
    verify(ROOT / 'build/app/outputs/flutter-apk/app-release.apk', env)
    print('Optimized ML Kit registrar constructors verified; this emulator-key APK must not be distributed.')


if __name__ == '__main__':
    try:
        check_release()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from None
