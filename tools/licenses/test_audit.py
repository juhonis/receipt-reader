import gzip
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import audit


class NoticeTests(unittest.TestCase):
    def test_upstream_ranges_are_utf8_byte_offsets(self):
        prefix = 'ä'.encode()
        expected = 'Copyright Ä; all terms retained.'.encode()
        index = json.dumps({'Example': {'start': len(prefix), 'length': len(expected)}})
        self.assertEqual(list(audit.notice_sections(index, prefix + expected)), [('Example', expected)])

    def test_invalid_ranges_are_refused(self):
        for start, length in [(-1, 2), (0, 0), (True, 2), (0, 4), ('0', 2)]:
            with self.subTest(start=start, length=length), self.assertRaises(ValueError):
                list(audit.notice_sections(json.dumps({'Example': {'start': start, 'length': length}}), b'123'))

    def test_aar_notices_and_nested_jar_notices_are_both_retained(self):
        jar, aar = io.BytesIO(), io.BytesIO()
        with zipfile.ZipFile(jar, 'w') as z:
            z.writestr('META-INF/NOTICE', b'Nested copyright and conditions')
        with zipfile.ZipFile(aar, 'w') as z:
            z.writestr('classes.jar', jar.getvalue())
            z.writestr('third_party_licenses.json', '{"Example":{"start":1,"length":5}}')
            z.writestr('third_party_licenses.txt', b'xterms')
        self.assertEqual(set((origin, raw) for _, origin, raw in audit.embedded_notices(aar)), {
            ('third_party_licenses.txt', b'terms'),
            ('classes.jar!/META-INF/NOTICE', b'Nested copyright and conditions'),
        })

    def test_packaged_notices_must_include_native_and_full_dart_terms(self):
        with tempfile.TemporaryDirectory(prefix='receipt-notice-test-') as directory:
            root = Path(directory)
            sdk = root / 'sdk'
            flutter = sdk / 'packages/flutter'
            flutter.mkdir(parents=True)
            version = sdk / 'bin/cache/flutter.version.json'
            version.parent.mkdir(parents=True)
            version.write_text('{"frameworkVersion":"test"}')
            flutter.joinpath('LICENSE').write_text('Copyright example\nComplete redistribution conditions\n', newline='\n')
            third = root / 'third_party'
            third.mkdir()
            native = b'Native copyright and complete terms\n'
            third.joinpath('NOTICES.txt').write_bytes(native)
            manifest = {'inputs': {}, 'flutter': {'frameworkVersion': 'test'},
                'noticeSha256': audit.digest(native), 'dartRuntimePackages': [
                    {'name': 'flutter', 'source': 'sdk', 'noticeFile': 'LICENSE',
                     'noticeSha256': audit.file_digest(flutter / 'LICENSE')}]}
            third.joinpath('dependencies.json').write_text(json.dumps(manifest))
            with patch.object(audit, 'ROOT', root), patch.object(audit, 'THIRD', third), \
                    patch.object(audit, 'config_packages', return_value={'flutter': flutter}):
                full = native + (flutter / 'LICENSE').read_bytes()
                self.assertEqual(audit.verify_notices(gzip.compress(full)), full.decode())
                with self.assertRaisesRegex(ValueError, 'omit Dart text'):
                    audit.verify_notices(gzip.compress(native + b'Copyright stub only'))
                with self.assertRaisesRegex(ValueError, 'omit native notices'):
                    audit.verify_notices(gzip.compress((flutter / 'LICENSE').read_bytes()))
                third.joinpath('NOTICES.txt').write_bytes(b'Truncated terms')
                with self.assertRaisesRegex(ValueError, 'Changed or missing native notices'):
                    audit.load_review()


if __name__ == '__main__':
    unittest.main()
