"""Create the permanent Windows-local Android signing identity once; never print secrets."""
import csv
import hashlib
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def protect(path):
    # Use the current user's SID; no dependence on localized account/group names.
    sid = next(csv.reader(subprocess.check_output(
        ['whoami', '/user', '/fo', 'csv', '/nh'], encoding='utf-8').splitlines()))[1]
    result = subprocess.run(['icacls', str(path), '/inheritance:r', '/grant:r',
                             f'*{sid}:(OI)(CI)F' if path.is_dir() else f'*{sid}:F'],
                            capture_output=True)
    if result.returncode:
        raise RuntimeError('Could not restrict signing-file access to the current user')


def main():
    if os.name != 'nt':
        raise ValueError('Bootstrap the permanent key on the Windows owner machine')
    keytool = Path(os.environ.get('JAVA_HOME', 'C:/Program Files/Android/Android Studio/jbr')) / 'bin/keytool.exe'
    config = ROOT / 'android/key.properties'
    pin = ROOT / 'android/release-certificate.sha256'
    final = Path(os.environ['LOCALAPPDATA']) / 'ReceiptReader/signing'
    if config.exists() or pin.exists() or final.exists():
        raise ValueError('Signing identity/configuration already exists. Restore or reuse it; never replace the permanent key.')
    if final.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError('Signing directory must be outside the repository')
    if not keytool.is_file():
        raise ValueError('Android Studio JDK keytool is required')
    final.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='signing-new-', dir=final.parent)).resolve()
    try:
        protect(stage)
        password = secrets.token_urlsafe(36)
        env = {**os.environ, 'RECEIPT_READER_NEW_KEY_PASSWORD': password}
        key = stage / 'receipt-reader-release.p12'
        common = ['-storepass:env', 'RECEIPT_READER_NEW_KEY_PASSWORD']
        subprocess.run([str(keytool), '-genkeypair', '-keystore', str(key), '-storetype', 'PKCS12',
            '-alias', 'receipt-reader', '-keyalg', 'RSA', '-keysize', '4096', '-sigalg', 'SHA256withRSA',
            '-validity', '10000', '-dname', 'CN=Receipt Reader, O=Receipt Reader, C=FI',
            *common, '-keypass:env', 'RECEIPT_READER_NEW_KEY_PASSWORD'], env=env, check=True,
            capture_output=True)
        subprocess.run([str(keytool), '-exportcert', '-keystore', str(key), '-alias', 'receipt-reader',
            '-file', str(stage / 'certificate.der'), *common], env=env, check=True, capture_output=True)
        fingerprint = hashlib.sha256((stage / 'certificate.der').read_bytes()).hexdigest()
        properties = (f'storeFile={(final / key.name).as_posix()}\nstorePassword={password}\n'
                      f'keyAlias=receipt-reader\nkeyPassword={password}\n')
        (stage / 'key.properties').write_text(properties, encoding='utf-8', newline='\n')
        (stage / 'BACKUP.txt').write_text(
            'PRIVATE SIGNING MATERIAL. Keep an independent protected backup of this entire folder.\n'
            'The PKCS12 key and key.properties passwords are both required for future APK updates.\n'
            'Never upload this folder to Git or a public release.\n'
            'On another machine restore these files and update storeFile in the ignored android/key.properties.\n'
            f'Public certificate SHA-256: {fingerprint}\n', encoding='utf-8')
        stage.rename(final)
        with config.open('x', encoding='utf-8', newline='\n') as target:
            # Restrict the empty file before writing credentials into the checkout.
            protect(config)
            target.write(properties)
        with pin.open('x', encoding='ascii') as target:
            target.write(fingerprint + '\n')
        print('Permanent signing identity created; passwords were not printed.')
        print('Private folder to back up independently:', final)
        print('Public certificate SHA-256:', fingerprint)
    finally:
        if stage.exists():
            if not stage.is_relative_to(final.parent.resolve()) or not stage.name.startswith('signing-new-'):
                raise RuntimeError('Unexpected signing staging directory')
            shutil.rmtree(stage)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from None
