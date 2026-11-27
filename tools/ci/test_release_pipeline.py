import base64
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from subprocess import CompletedProcess
from unittest.mock import Mock, patch
import sys

ROOT = Path(__file__).resolve().parents[2]
from prepare import install_kotlin_guard, prepare_android_tools
from android_release_smoke import check_release
sys.path.insert(0, str(ROOT / 'tools/releases'))
from ci_signing import signed_build, verify_keystore
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
                    'mlkitRegistrarConstructorsVerified': True,
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
                             ('mlkitRegistrarConstructorsVerified', False),
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
                with self.subTest(failure=fail), patch('ci_signing.sync'), patch('ci_signing.protect'), \
                        patch('ci_signing.verify_keystore'):
                    if fail:
                        with self.assertRaisesRegex(RuntimeError, 'interrupted'):
                            signed_build('v0.2.0-alpha.2', env=env, run=run)
                    else:
                        signed_build('v0.2.0-alpha.2', env=env, run=run)
                self.assertEqual(list(Path(directory).iterdir()), [])

    def test_wrong_keystore_never_starts_a_build_and_is_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            env = {'RUNNER_TEMP': directory,
                'RECEIPT_READER_KEYSTORE_BASE64': base64.b64encode(b'synthetic key').decode(),
                'RECEIPT_READER_STORE_PASSWORD': 'synthetic-password',
                'RECEIPT_READER_KEY_ALIAS': 'fixture', 'RECEIPT_READER_KEY_PASSWORD': 'synthetic-password'}
            with patch('ci_signing.sync'), patch('ci_signing.protect'), \
                    patch('ci_signing.verify_keystore', side_effect=ValueError('wrong certificate')), \
                    patch('ci_signing.subprocess.run') as run, \
                    self.assertRaisesRegex(ValueError, 'wrong certificate'):
                signed_build('v0.2.0-alpha.2', env=env, run=run)
            run.assert_not_called()
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_matching_keystore_checks_public_certificate_without_password_arguments(self):
        env = {'RECEIPT_READER_KEY_ALIAS': 'fixture', 'RECEIPT_READER_STORE_PASSWORD': 'synthetic-password'}
        certificate = hashlib.sha256(b'synthetic DER certificate').hexdigest()
        with patch('ci_signing.subprocess.run', return_value=CompletedProcess(
                [], 0, stdout=b'synthetic DER certificate')) as run, redirect_stdout(StringIO()) as output:
            verify_keystore(Path('fixture.p12'), env, certificate)
        self.assertIn(certificate, output.getvalue())
        self.assertNotIn(env['RECEIPT_READER_STORE_PASSWORD'], run.call_args.args[0])
        self.assertEqual(run.call_args.kwargs['env'], env)

    def test_different_certificate_reports_only_public_fingerprints(self):
        actual = hashlib.sha256(b'other DER certificate').hexdigest()
        with patch('ci_signing.subprocess.run', return_value=CompletedProcess(
                [], 0, stdout=b'other DER certificate')), \
                self.assertRaisesRegex(ValueError, actual + '; expected ' + 'a' * 64):
            verify_keystore(Path('fixture.p12'), {'RECEIPT_READER_KEY_ALIAS': 'fixture'}, 'a' * 64)

    def test_keytool_failure_withholds_output_and_credentials(self):
        with patch('ci_signing.subprocess.run', return_value=CompletedProcess(
                [], 1, stdout=b'', stderr=b'synthetic private diagnostic')), \
                self.assertRaisesRegex(ValueError, 'Cannot read the CI signing certificate') as failure:
            verify_keystore(Path('fixture.p12'), {'RECEIPT_READER_KEY_ALIAS': 'fixture'}, 'a' * 64)
        self.assertNotIn('synthetic private diagnostic', str(failure.exception))


class GradleGuardTests(unittest.TestCase):
    def test_prepare_installs_pinned_analyzer_even_when_other_packages_exist(self):
        with tempfile.TemporaryDirectory() as directory:
            sdk = Path(directory)
            manager = sdk / 'cmdline-tools/latest/bin/sdkmanager.bat'
            manager.parent.mkdir(parents=True)
            manager.touch()
            (sdk / 'build-tools/36.0.0').mkdir(parents=True)
            tools = sdk / 'cmdline-tools/23.0'
            with patch('prepare.android_command_line_tools', side_effect=[ValueError('old tools'), tools]), \
                    patch('prepare.run') as run, redirect_stdout(StringIO()):
                prepare_android_tools(sdk, ['build-tools;36.0.0'], {})
            self.assertEqual(run.call_count, 2)
            self.assertEqual(run.call_args.args[0],
                             [manager, '--sdk_root=' + str(sdk), 'cmdline-tools;23.0'])
            with patch('prepare.android_command_line_tools', return_value=tools), \
                    patch('prepare.run') as run, redirect_stdout(StringIO()):
                prepare_android_tools(sdk, ['build-tools;36.0.0'], {})
            run.assert_not_called()

    def test_guard_install_preserves_unrelated_init_scripts_and_is_repeatable(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / 'init.d').mkdir()
            unrelated = home / 'init.d/owner.gradle'
            unrelated.write_text('owner configuration')
            target = install_kotlin_guard(home)
            before = target.read_bytes()
            self.assertEqual(install_kotlin_guard(home).read_bytes(), before)
            self.assertEqual(unrelated.read_text(), 'owner configuration')

    def test_guard_install_refuses_to_replace_an_existing_different_script(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            target = home / 'init.d/receipt-reader-release.gradle'
            target.parent.mkdir()
            target.write_text('existing configuration')
            with self.assertRaisesRegex(ValueError, 'Refusing to replace'):
                install_kotlin_guard(home)
            self.assertEqual(target.read_text(), 'existing configuration')


class OptimizedAndroidSmokeTests(unittest.TestCase):
    def test_smoke_build_replaces_inherited_signing_values_and_verifies_dex(self):
        with tempfile.TemporaryDirectory() as directory:
            key = Path(directory) / 'debug.keystore'
            key.write_bytes(b'synthetic emulator key')
            env = {'ANDROID_USER_HOME': directory, 'RECEIPT_READER_STORE_FILE': 'unused-production-path',
                'RECEIPT_READER_STORE_PASSWORD': 'unused-secret', 'RECEIPT_READER_KEY_ALIAS': 'unused-alias',
                'RECEIPT_READER_KEY_PASSWORD': 'unused-secret', 'RECEIPT_READER_KEYSTORE_BASE64': 'unused-key'}
            run, verify = Mock(), Mock()
            with patch('android_release_smoke.shutil.which', return_value='flutter.bat'), \
                    patch('android_release_smoke.tool_invocation', side_effect=lambda command, child: (command, child)), \
                    redirect_stdout(StringIO()):
                check_release(env, run=run, verify=verify)
            child = run.call_args.kwargs['env']
            self.assertEqual(child['RECEIPT_READER_STORE_FILE'], str(key))
            self.assertEqual(child['RECEIPT_READER_KEY_ALIAS'], 'androiddebugkey')
            self.assertNotIn('RECEIPT_READER_KEYSTORE_BASE64', child)
            self.assertIn('--release', run.call_args.args[0])
            verify.assert_called_once()
            self.assertEqual(env['RECEIPT_READER_KEYSTORE_BASE64'], 'unused-key')

    def test_smoke_build_never_generates_a_replacement_key(self):
        with tempfile.TemporaryDirectory() as directory:
            run, verify = Mock(), Mock()
            with self.assertRaisesRegex(ValueError, 'Compile the debug APK first'):
                check_release({'ANDROID_USER_HOME': directory}, run=run, verify=verify)
            run.assert_not_called()
            verify.assert_not_called()
            self.assertEqual(list(Path(directory).iterdir()), [])


if __name__ == '__main__':
    unittest.main()
