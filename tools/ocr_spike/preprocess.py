"""Controlled, manually guided preprocessing; never an automatic receipt crop."""

import argparse
import json
from pathlib import Path
import subprocess
import time

import cv2
import numpy as np

from run import OUTPUT, PRIVATE, MODEL_HASHES, load_manifest, parse_tsv, save, sha256, validate


def transform_points(points, matrix):
    points = np.asarray(points, dtype=np.float64)
    homogeneous = np.column_stack((points, np.ones(len(points)))) @ np.asarray(matrix).T
    if np.any(np.abs(homogeneous[:, 2]) < 1e-10):
        raise ValueError('Point maps to infinity')
    return homogeneous[:, :2] / homogeneous[:, 2:]


def validate_quad(quad, width, height):
    q = np.asarray(quad, dtype=np.float32)
    if q.shape != (4, 2) or not np.isfinite(q).all():
        raise ValueError('Expected four finite corners: TL, TR, BR, BL')
    if np.any(q < 0) or np.any(q[:, 0] > width - 1) or np.any(q[:, 1] > height - 1):
        raise ValueError('Crop corners outside image')
    if not cv2.isContourConvex(q) or cv2.contourArea(q, oriented=True) < 100:
        raise ValueError('Corners must be clockwise, convex, and nondegenerate')
    return q


def variants(image, quad):
    height, width = image.shape[:2]
    q = validate_quad(quad, width, height)
    left, top = np.floor(q.min(axis=0)).astype(int)
    right, bottom = np.ceil(q.max(axis=0)).astype(int) + 1
    crop = image[top:bottom, left:right]
    translation = np.array([[1, 0, -left], [0, 1, -top], [0, 0, 1]], dtype=float)
    # Preserve approximate source resolution rather than tuning scale per sample.
    target_w = max(2, round(max(np.linalg.norm(q[1] - q[0]), np.linalg.norm(q[2] - q[3]))))
    target_h = max(2, round(max(np.linalg.norm(q[3] - q[0]), np.linalg.norm(q[2] - q[1]))))
    destination = np.float32([[0, 0], [target_w - 1, 0],
                             [target_w - 1, target_h - 1], [0, target_h - 1]])
    matrix = cv2.getPerspectiveTransform(q, destination)
    rectified = cv2.warpPerspective(image, matrix, (target_w, target_h),
                                    flags=cv2.INTER_CUBIC, borderValue=(255, 255, 255))
    gray = cv2.cvtColor(rectified, cv2.COLOR_BGR2GRAY)
    low, high = np.percentile(gray, (1, 99))
    contrast = gray if high <= low else np.clip((gray.astype(float) - low) * 255 / (high - low), 0, 255).astype('uint8')
    return {'crop': (crop, translation), 'rectified': (rectified, matrix),
            'rectified-gray': (contrast, matrix)}


def evaluate_regions(result, annotations):
    """Probe manually annotated amount regions only; does not parse receipt rows."""
    inverse = np.asarray(result.get('transform', {}).get('toPreparedImage', np.eye(3)))
    words = []
    for block in result['blocks']:
        for line in block['lines']:
            for word in line['words']:
                b = word['box']
                center = transform_points([[(b['left'] + b['right']) / 2,
                                            (b['top'] + b['bottom']) / 2]], inverse)[0]
                words.append((center, word['text']))
    probes = []
    for region in annotations:
        left, top, right, bottom = region['box']
        selected = sorted(((xy[0], text) for xy, text in words
                           if left <= xy[0] < right and top <= xy[1] < bottom))
        text = ''.join(text for _, text in selected).replace('\u00a0', '').replace(' ', '')
        # Decimal comma/point only; never fix O/0 or guess missing digits.
        import re
        match = re.fullmatch(r'(-?)([0-9]+)[,.]([0-9]{2})', text)
        amount = None if not match else (-1 if match[1] else 1) * (int(match[2]) * 100 + int(match[3]))
        probes.append({'id': region['id'], 'expectedCents': region['amountCents'],
                       'observedCents': amount, 'observedText': text,
                       'matched': amount == region['amountCents']})
    return probes


def experiment(executable):
    manifest = load_manifest()
    config = json.loads((OUTPUT / 'annotations.json').read_text(encoding='utf-8'))
    model_root = OUTPUT / 'models'
    for language, digest in MODEL_HASHES.items():
        if sha256(model_root / f'{language}.traineddata') != digest:
            raise ValueError('Model hash changed')
    version = subprocess.run([executable, '--version'], capture_output=True, check=True,
                             encoding='utf-8').stdout.splitlines()[0]
    report = []
    for entry in manifest:
        if sha256(PRIVATE / entry['source']) != entry['sha256']:
            raise ValueError('Original image differs from preparation manifest')
        sample = entry['sampleId']
        annotation = config[sample]
        if annotation['inputSha256'] != entry['preparedSha256']:
            raise ValueError('Annotations belong to a different input')
        source = OUTPUT / 'inputs' / f'{sample}.png'
        image = cv2.imdecode(np.frombuffer(source.read_bytes(), dtype=np.uint8), cv2.IMREAD_COLOR)
        prepared_variants = variants(image, annotation['quad'])
        # Re-run baseline with the exact same executable/models as the variants.
        prepared_variants = {'baseline': (image, np.eye(3)), **prepared_variants}
        for variant, (pixels, matrix) in prepared_variants.items():
            folder = OUTPUT / 'preprocessing' / variant
            folder.mkdir(parents=True, exist_ok=True)
            path = folder / f'{sample}.png'
            path.write_bytes(cv2.imencode('.png', pixels)[1].tobytes())
            height, width = pixels.shape[:2]
            for psm in (3, 6):
                started = time.perf_counter()
                process = subprocess.run([executable, str(path), 'stdout', '--tessdata-dir', str(model_root),
                                          '-l', 'fin+eng', '--psm', str(psm), '-c', 'tessedit_create_tsv=1'],
                                         capture_output=True, encoding='utf-8', check=True, timeout=120)
                blocks = parse_tsv(process.stdout)
                result = {'schemaVersion': 1, 'sampleId': sample, 'engine': version,
                          'adapterVersion': 'tsv-v1', 'inputSha256': sha256(path),
                          'preparedInputSha256': entry['preparedSha256'],
                          'configuration': {'psm': psm, 'languages': 'fin+eng', 'variant': variant},
                          'modelHashes': MODEL_HASHES,
                          'image': {'width': width, 'height': height, 'orientation': 'upright'},
                          'transform': {'fromPreparedImage': matrix.tolist(),
                                        'toPreparedImage': np.linalg.inv(matrix).tolist(),
                                        'preparedWidth': entry['width'], 'preparedHeight': entry['height']},
                          'elapsedMs': round((time.perf_counter() - started) * 1000),
                          'text': '\n'.join(b['text'] for b in blocks), 'blocks': blocks}
                validate(result)
                save(folder / f'{sample}-psm{psm}.json', result)
                probes = evaluate_regions(result, annotation['amountRegions'])
                report.append({'sampleId': sample, 'variant': variant, 'psm': psm,
                               'matched': sum(p['matched'] for p in probes), 'count': len(probes),
                               'probes': probes})
            if sha256(PRIVATE / entry['source']) != entry['sha256']:
                raise ValueError('Original image changed during experiment')
            print(f'{sample}: {variant} complete; original unchanged.')
    save(OUTPUT / 'preprocessing/report.json', report)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tesseract', default=r'C:\Program Files\Tesseract-OCR\tesseract.exe')
    experiment(parser.parse_args().tesseract)
