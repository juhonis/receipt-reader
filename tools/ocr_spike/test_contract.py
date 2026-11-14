"""Synthetic adapter tests; no real receipts are embedded here."""

import copy
import unittest

from run import parse_tsv, validate


class GeometryContractTest(unittest.TestCase):
    def setUp(self):
        self.tsv = ('level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n'
                    '4\t1\t1\t1\t1\t0\t10\t20\t80\t10\t-1\t\n'
                    '5\t1\t1\t1\t1\t1\t10\t20\t20\t10\t90\tTESTI\n'
                    '5\t1\t1\t1\t1\t2\t70\t20\t20\t10\t90\t1,23\n'
                    '5\t1\t1\t2\t1\t1\t10\t40\t20\t10\t90\tTOINEN\n')
        self.result = {'schemaVersion': 1, 'image': {'width': 100, 'height': 100, 'orientation': 'upright'},
                       'blocks': parse_tsv(self.tsv)}

    def test_tsv_preserves_words_and_paragraph_scoped_lines(self):
        block = self.result['blocks'][0]
        self.assertEqual(len(block['lines']), 2)
        self.assertEqual(block['lines'][0]['text'], 'TESTI 1,23')
        self.assertEqual(block['box'], {'left': 10, 'top': 20, 'right': 90, 'bottom': 50})
        self.assertIsNone(block['lines'][0]['words'][0]['corners'])
        validate(self.result)

    def test_out_of_bounds_geometry_is_rejected(self):
        result = copy.deepcopy(self.result)
        result['blocks'][0]['lines'][0]['words'][0]['box']['right'] = 101
        with self.assertRaises(ValueError):
            validate(result)

    def test_plain_text_cannot_silently_pass_as_tsv(self):
        with self.assertRaises(ValueError):
            parse_tsv('TESTI 1,23')

    def test_unsupported_orientation_is_rejected(self):
        self.result['image']['orientation'] = 'exif-rotated'
        with self.assertRaises(ValueError):
            validate(self.result)


if __name__ == '__main__':
    unittest.main()
