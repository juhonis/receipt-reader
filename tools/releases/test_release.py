import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from android import inspect_apk, tool_invocation, verify_source_unchanged, verify_mlkit_registrars
import setup_signing
from version import check_history, parse, sync


class VersionTests(unittest.TestCase):
    def test_optimized_apk_requires_public_no_argument_mlkit_constructors(self):
        with tempfile.TemporaryDirectory() as directory:
            sdk = Path(directory)
            tools = sdk / 'Program Files (x86)/Android SDK/cmdline-tools/23.0'
            env = {'JAVA_HOME': str(sdk / 'Program Files/JDK')}
            public = subprocess.CompletedProcess([], 0, '.method public constructor <init>()V\n.end method\n', '')
            with patch('android.audit.android_command_line_tools', return_value=tools), \
                    patch('android.subprocess.run', return_value=public) as run:
                verify_mlkit_registrars(Path('app.apk'), env)
                self.assertEqual(run.call_count, 3)
                command = run.call_args.args[0]
                self.assertIsInstance(command, list)
                self.assertEqual(command[:5], [str(Path(env['JAVA_HOME']) / 'bin/java.exe'),
                    '-Dcom.android.sdklib.toolsdir=' + str(tools), '-classpath',
                    str(tools / 'lib/apkanalyzer-classpath.jar'),
                    'com.android.tools.apk.analyzer.ApkAnalyzerCli'])
            for result in [subprocess.CompletedProcess([], 0, '.method private constructor <init>()V\n', ''),
                           subprocess.CompletedProcess([], 0, '.method public constructor <init>(I)V\n', '')]:
                with self.subTest(result=result), patch('android.audit.android_command_line_tools', return_value=tools), \
                        patch('android.subprocess.run', side_effect=[public, public, result]), \
                        self.assertRaisesRegex(ValueError, 'TextRegistrar'):
                    verify_mlkit_registrars(Path('app.apk'), env)

    def test_analyzer_failure_reports_tool_diagnostic_without_signing_environment(self):
        failure = subprocess.CompletedProcess([], 1, '', 'SDK tool initialization failed')
        env = {**os.environ, 'JAVA_HOME': 'fixture JDK', 'RECEIPT_READER_STORE_PASSWORD': 'synthetic-password',
               'RECEIPT_READER_BATCH_ARG_99': 'stale-value'}
        with patch('android.audit.android_command_line_tools', return_value=Path('sdk/tools')), \
                patch('android.subprocess.run', return_value=failure) as run, \
                self.assertRaisesRegex(ValueError, 'APK analyzer failed') as error:
            verify_mlkit_registrars(Path('app.apk'), env)
        self.assertIn('SDK tool initialization failed', str(error.exception))
        self.assertNotIn('lacks a public', str(error.exception))
        child = run.call_args.kwargs['env']
        self.assertNotIn('RECEIPT_READER_STORE_PASSWORD', child)
        self.assertNotIn('RECEIPT_READER_BATCH_ARG_99', child)
        self.assertEqual(env['RECEIPT_READER_STORE_PASSWORD'], 'synthetic-password')

    def test_reusing_or_lowering_a_previously_tagged_android_build_is_rejected(self):
        for previous, accepted in [('0.2.0-alpha.1+2', True), ('0.2.0-alpha.1+3', False), ('0.2.0-alpha.1+4', False)]:
            with self.subTest(previous=previous), patch('version.subprocess.check_output', side_effect=[
                    'v0.2.0-alpha.1\nv0.2.0-alpha.2\n', 'version: ' + previous + '\n']):
                if accepted:
                    check_history(parse('0.2.0-alpha.2+3'))
                else:
                    with self.assertRaisesRegex(ValueError, 'must exceed'):
                        check_history(parse('0.2.0-alpha.2+3'))

    @unittest.skipUnless(os.name == 'nt', 'Windows batch invocation')
    def test_batch_tools_preserve_literal_paths_and_arguments(self):
        with tempfile.TemporaryDirectory(prefix='receipt-release-test-') as directory:
            root = Path(directory) / 'space & (%literal%)'
            root.mkdir()
            batch = root / 'tool.cmd'
            batch.write_text('@echo off\n@"%RECEIPT_TEST_PYTHON%" -c "import sys;print(sys.argv[1])" "%~1"\n')
            argument = 'one & two (three) %literal% !kept! ^'
            command, env = tool_invocation([batch, argument],
                                          {**os.environ, 'RECEIPT_TEST_PYTHON': sys.executable})
            actual = subprocess.check_output(command, env=env, encoding='utf-8').rstrip('\r\n')
            self.assertEqual(actual, argument)

    def test_distributable_cannot_claim_a_different_or_dirty_source_commit(self):
        with patch('android.source_state', return_value=('reviewed', False)):
            self.assertFalse(verify_source_unchanged('reviewed', allow_dirty=False))
        for current, dirty, rehearsal in [
            ('reviewed', True, False),
            ('different', False, False),
            ('different', True, True),
        ]:
            with self.subTest(current=current, dirty=dirty, rehearsal=rehearsal), \
                    patch('android.source_state', return_value=(current, dirty)), \
                    self.assertRaisesRegex(ValueError, 'Source changed'):
                verify_source_unchanged('reviewed', allow_dirty=rehearsal)
        with patch('android.source_state', return_value=('reviewed', True)):
            self.assertTrue(verify_source_unchanged('reviewed', allow_dirty=True))

    @unittest.skipUnless(os.name == 'nt', 'Signing bootstrap uses Windows file permissions')
    def test_signing_bootstrap_never_replaces_an_existing_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'android').mkdir()
            for name in ['key.properties', 'release-certificate.sha256']:
                path = root / 'android' / name
                path.write_text('existing identity')
                with self.subTest(existing=name), patch.object(setup_signing, 'ROOT', root), \
                        patch.dict('setup_signing.os.environ', {'LOCALAPPDATA': str(root / 'private')}), \
                        patch('setup_signing.subprocess.run') as run, \
                        self.assertRaisesRegex(ValueError, 'never replace'):
                    setup_signing.main()
                self.assertEqual(path.read_text(), 'existing identity')
                run.assert_not_called()
                path.unlink()

    def test_rejects_invalid_or_uninstallable_versions(self):
        for value in ['1.0.0', '1.0.0+0', '1.0.0+01', '01.0.0+1', '1.0.0-alpha.01+1',
                      '1.0.0+2100000001', '1.0.0+1;echo bad', '1.0.0-+1']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                parse(value)
        self.assertEqual(parse('0.2.0-alpha.1+2').build, 2)

    def test_stale_metadata_and_wrong_tag_stop_a_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'lib').mkdir()
            (root / 'pubspec.yaml').write_text('version: 0.2.0-alpha.1+2\n')
            with self.assertRaisesRegex(ValueError, 'stale'):
                sync(root, check=True)
            sync(root)
            self.assertEqual(sync(root, check=True, tag='v0.2.0-alpha.1').full, '0.2.0-alpha.1+2')
            with self.assertRaisesRegex(ValueError, 'tag'):
                sync(root, check=True, tag='v0.2.0-alpha.2')
            (root / 'pubspec.yaml').write_text('version: 0.2.0-alpha.2+3\n')
            with self.assertRaisesRegex(ValueError, 'stale'):
                sync(root, check=True)

    def test_apk_certificate_package_build_and_arm64_are_required(self):
        certificate = 'a' * 64
        signature = ('Signer #1 certificate SHA-256 digest: ' + certificate + '\n'
                     'Verified using v2 scheme (APK Signature Scheme v2): true\n')
        badging = ("package: name='fi.juhonis.receipt_reader' versionCode='2' versionName='0.2.0-alpha.1'\n"
                   "native-code: 'arm64-v8a' 'x86_64'\n")
        def inspect(sig=signature, badge=badging):
            with patch('android.subprocess.check_output', side_effect=[sig, badge]):
                return inspect_apk(Path('app.apk'), parse('0.2.0-alpha.1+2'), certificate,
                                   Path('aapt'), Path('signer'), {})
        self.assertTrue(inspect()['signatureV2Verified'])
        self.assertTrue(inspect(signature.replace('\n', ' \r\n'))['signatureV2Verified'])
        # Build Tools 37 changed the label even for the same correctly signed APK.
        # An unexpected tool format must not be reported as a different key.
        with self.assertRaisesRegex(ValueError, 'parsed 0'):
            inspect(signature.replace('Signer #1', 'V2 Signer:'))
        with self.assertRaisesRegex(ValueError, 'SHA-256 is ' + 'b' * 64 + '; expected ' + certificate):
            inspect(signature.replace(certificate, 'b' * 64))
        for sig, badge in [
            (signature.replace(certificate, 'b' * 64), badging),
            (signature + 'Signer #2 certificate SHA-256 digest: ' + certificate + '\n', badging),
            (signature.replace(': true', ': false'), badging),
            (signature, badging.replace("versionCode='2'", "versionCode='1'")),
            (signature, badging.replace('fi.juhonis.receipt_reader', 'another.package')),
            (signature, badging.replace("'arm64-v8a'", "'armeabi-v7a'")),
        ]:
            with self.subTest(sig=sig, badge=badge), self.assertRaises(ValueError):
                inspect(sig, badge)


if __name__ == '__main__':
    unittest.main()
