"""Restore a CI signing key only for the APK build, then remove the temporary copy."""
import base64
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from setup_signing import protect
from version import ROOT, sync


def verify_keystore(path, env, certificate):
    """Compare public certificate bytes without exposing keytool credentials/output."""
    if not re.fullmatch(r'[0-9a-f]{64}', certificate):
        raise ValueError('Missing or invalid pinned release certificate')
    keytool = Path(env.get('JAVA_HOME', 'C:/Program Files/Android/Android Studio/jbr')) / 'bin/keytool.exe'
    result = subprocess.run([
        str(keytool), '-exportcert', '-keystore', str(path),
        '-alias', env['RECEIPT_READER_KEY_ALIAS'],
        '-storepass:env', 'RECEIPT_READER_STORE_PASSWORD',
    ], env=env, capture_output=True)
    if result.returncode or not result.stdout:
        raise ValueError('Cannot read the CI signing certificate. Check ANDROID_KEYSTORE_BASE64, '
                         'ANDROID_STORE_PASSWORD and ANDROID_KEY_ALIAS; keytool output is withheld.')
    actual = hashlib.sha256(result.stdout).hexdigest()
    if actual != certificate:
        raise ValueError(f'CI keystore certificate SHA-256 is {actual}; expected {certificate}. '
                         'Restore ANDROID_KEYSTORE_BASE64 from the existing permanent .p12 file. '
                         'Do not generate a new key or change the certificate pin.')
    print('CI keystore certificate SHA-256:', actual, flush=True)


def signed_build(tag, env=None, run=subprocess.run):
    env = dict(os.environ if env is None else env)
    sync(check=True, tag=tag)
    required = ['RECEIPT_READER_KEYSTORE_BASE64', 'RECEIPT_READER_STORE_PASSWORD',
                'RECEIPT_READER_KEY_ALIAS', 'RECEIPT_READER_KEY_PASSWORD']
    if any(not env.get(name) for name in required):
        raise ValueError('Configure all four Android signing secrets in the protected release environment')
    # Standard WSL/base64 output may be line-wrapped when entered as a secret.
    key = base64.b64decode(''.join(env['RECEIPT_READER_KEYSTORE_BASE64'].split()), validate=True)
    if not key or len(key) > 32 * 1024:
        raise ValueError('Invalid signing-keystore size')
    parent = Path(env['RUNNER_TEMP']).resolve()
    work = Path(tempfile.mkdtemp(prefix='receipt-ci-signing-', dir=parent)).resolve()
    if not work.is_relative_to(parent):
        raise ValueError('Unexpected signing staging directory')
    try:
        protect(work)
        path = work / 'release.p12'
        with path.open('xb') as output:
            output.write(key)
        env['RECEIPT_READER_STORE_FILE'] = str(path)
        # The encoded private key is unnecessary in the Gradle/Flutter child environment.
        env.pop('RECEIPT_READER_KEYSTORE_BASE64')
        certificate = (ROOT / 'android/release-certificate.sha256').read_text(encoding='ascii').strip()
        verify_keystore(path, env, certificate)
        run([sys.executable, str(ROOT / 'tools/releases/android.py'), '--tag', tag],
            cwd=ROOT, env=env, check=True)
    finally:
        if not work.resolve().is_relative_to(parent) or not work.name.startswith('receipt-ci-signing-'):
            raise RuntimeError('Unexpected signing cleanup directory')
        shutil.rmtree(work)


if __name__ == '__main__':
    try:
        signed_build(os.environ['RELEASE_TAG'])
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from None
