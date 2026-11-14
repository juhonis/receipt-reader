"""Synthetic transform and financial-region checks, without private receipts."""

import unittest
import numpy as np

from preprocess import evaluate_regions, transform_points, validate_quad, variants


class PreprocessingTest(unittest.TestCase):
    def test_transforms_roundtrip_and_crop_origin(self):
        image = np.full((120, 100, 3), 255, dtype=np.uint8)
        quad = [[10, 5], [85, 15], [90, 110], [15, 100]]
        outputs = variants(image, quad)
        np.testing.assert_allclose(transform_points([[10, 5]], outputs['crop'][1]), [[0, 0]])
        for _, matrix in outputs.values():
            points = [[20, 30], [70, 80]]
            np.testing.assert_allclose(transform_points(transform_points(points, matrix),
                                                       np.linalg.inv(matrix)), points)

    def test_invalid_corners_rejected(self):
        for quad in ([[[0, 0], [99, 99], [99, 0], [0, 99]],
                      [[0, 0], [100, 0], [99, 99], [0, 99]],
                      [[0, 0], [0, 99], [99, 99], [99, 0]],
                      [[0, 0], [1, 0], [1, 1], [0, 1]]]):
            with self.assertRaises(ValueError):
                validate_quad(quad, 100, 100)

    def test_probe_maps_coordinates_and_excludes_footer(self):
        def word(text, x, y):
            return {'text': text, 'box': {'left': x, 'top': y, 'right': x+8, 'bottom': y+8}}
        result = {'transform': {'toPreparedImage': [[1, 0, 50], [0, 1, 20], [0, 0, 1]]},
                  'blocks': [{'lines': [{'words': [word('-1,23', 10, 10), word('9,99', 10, 40)]}]}]}
        regions = [{'id': 'posted', 'box': [55, 25, 75, 45], 'amountCents': -123}]
        self.assertTrue(evaluate_regions(result, regions)[0]['matched'])
        result['blocks'][0]['lines'][0]['words'][0]['text'] = '-I,23'
        self.assertIsNone(evaluate_regions(result, regions)[0]['observedCents'])


if __name__ == '__main__':
    unittest.main()
