import base64
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/releases'))
from ci_signing import signed_build
from draft import create_draft, validate_assets
from version import parse


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.version = parse('0.2.0-alpha.2+3')
        self.commit = 'a' * 40
        self.certificate = 'b' * 64
        inventory = hashlib.sha256((ROOT / 'third_party/dependencies.json').read_bytes()).hexdigest()
        for name in [self.version.artifact, self.version.windows_artifact]:
            artifact = self.directory / name
            artifact.write_bytes(b'synthetic artifact')
            checksum = hashlib.sha256(artifact.read_bytes()).hexdigest()
            artifact.with_suffix(artifact.suffix + '.sha256').write_text(checksum + '  ' + name + '\n')
            metadata = {'version': self.version.full, 'tag': self.version.tag, 'commit': self.commit,
                'workingTreeDirty': False, 'developmentBuild': False, 'applicationLicense': 'MIT',
                'noticeInventorySha256': inventory}
            if name.endswith('.apk'):
                metadata.update({'apkSha256': checksum, 'certificateSha256': self.certificate,
                    'signatureV2Verified': True, 'arm64Included': True, 'packagedNoticesVerified': True,
                    'applicationId': 'fi.juhonis.receipt_reader', 'versionName': self.version.name,
                    'versionCode': self.version.build})
            else:
                metadata.update({'zipSha256': checksum, 'nativeImportAudit': True,
                    'nativeNoticesVerified': True, 'modelInitialization': True})
            artifact.with_suffix('.json').write_text(json.dumps(metadata))

    def validate(self):
        return validate_assets(self.directory, self.version, self.commit, self.certificate)

    def test_exact_clean_artifacts_can_prepare_a_draft(self):
        self.assertEqual(len(self.validate()), 6)

    def test_unexpected_files_or_tampered_downloads_are_rejected(self):
        extra = self.directory / 'private-key.p12'
        extra.write_bytes(b'not a key')
        with self.assertRaisesRegex(ValueError, 'unexpected'):
            self.validate()
        extra.unlink()
        (self.directory / self.version.artifact).write_bytes(b'changed download')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            self.validate()

    def test_wrong_commit_signer_or_development_provenance_are_rejected(self):
        path = (self.directory / self.version.artifact).with_suffix('.json')
        original = json.loads(path.read_text())
        for field, value in [('commit', 'c' * 40), ('certificateSha256', 'd' * 64),
                             ('developmentBuild', True), ('workingTreeDirty', True)]:
            path.write_text(json.dumps({**original, field: value}))
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.validate()

    def test_existing_draft_or_published_release_is_never_replaced(self):
        for draft in [False, True]:
            calls = []
            def request(method, url, token, *args, **kwargs):
                calls.append(method)
                return [{'tag_name': self.version.tag, 'draft': draft}]
            with self.subTest(draft=draft), self.assertRaisesRegex(ValueError, 'already exists'):
                create_draft('example/receipts', self.version, self.commit, [], 'notes', 'fake', request)
            self.assertEqual(calls, ['GET'])

    def test_new_release_is_always_draft_and_prerelease(self):
        calls = []
        def request(method, url, token, payload=None, **kwargs):
            calls.append((method, url, payload))
            if method == 'GET': return []
            if url.endswith('/releases'): return {'id': 123, 'draft': True, 'html_url': 'https://github.com/example/receipts/releases/123'}
            return {}
        create_draft('example/receipts', self.version, self.commit, self.validate(), 'notes', 'fake', request)
        self.assertIs(calls[1][2]['draft'], True)
        self.assertIs(calls[1][2]['prerelease'], True)
        self.assertEqual(len(calls), 8)
        self.assertTrue(all(url.startswith('https://uploads.github.com/repos/example/receipts/')
                            for _, url, _ in calls[2:]))


class SigningTests(unittest.TestCase):
    def test_missing_credentials_never_start_a_build(self):
        with patch('ci_signing.sync'), self.assertRaisesRegex(ValueError, 'four Android signing secrets'):
            signed_build('v0.2.0-alpha.2', env={})

    def test_temporary_private_key_is_removed_after_success_or_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            encoded = base64.b64encode(b'synthetic key').decode()
            env = {'RUNNER_TEMP': directory, 'RECEIPT_READER_KEYSTORE_BASE64': encoded[:8] + '\n' + encoded[8:] + '\n',
                'RECEIPT_READER_STORE_PASSWORD': 'synthetic-password', 'RECEIPT_READER_KEY_ALIAS': 'fixture',
                'RECEIPT_READER_KEY_PASSWORD': 'synthetic-password'}
            for fail in [False, True]:
                def run(arguments, **kwargs):
                    child = kwargs['env']
                    self.assertNotIn('RECEIPT_READER_KEYSTORE_BASE64', child)
                    path = Path(child['RECEIPT_READER_STORE_FILE'])
                    self.assertEqual(path.read_bytes(), b'synthetic key')
                    if fail: raise RuntimeError('synthetic interrupted build')
                with self.subTest(failure=fail), patch('ci_signing.sync'), patch('ci_signing.protect'):
                    if fail:
                        with self.assertRaisesRegex(RuntimeError, 'interrupted'):
                            signed_build('v0.2.0-alpha.2', env=env, run=run)
                    else:
                        signed_build('v0.2.0-alpha.2', env=env, run=run)
                self.assertEqual(list(Path(directory).iterdir()), [])


if __name__ == '__main__':
    unittest.main()
