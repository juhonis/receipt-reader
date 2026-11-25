"""Validate tagged artifacts and create a new draft pre-release; never publish it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import quote
from urllib.request import Request, urlopen

from version import ROOT, check_history, sync


def validate_assets(directory, version, commit, certificate):
    names = [version.artifact, version.windows_artifact]
    expected = {name for artifact in names for name in [artifact, artifact + '.sha256', str(Path(artifact).with_suffix('.json'))]}
    if {p.name for p in directory.iterdir()} != expected or any(not p.is_file() or p.is_symlink() for p in directory.iterdir()):
        raise ValueError('Release assets are missing or contain unexpected files')
    assets = []
    for name in names:
        artifact = directory / name
        metadata = json.loads(artifact.with_suffix('.json').read_text(encoding='utf-8'))
        if (metadata.get('version') != version.full or metadata.get('tag') != version.tag or
                metadata.get('commit') != commit or metadata.get('workingTreeDirty') is not False or
                metadata.get('developmentBuild') is not False or metadata.get('applicationLicense') != 'MIT' or
                metadata.get('thirdPartyInventorySha256', metadata.get('noticeInventorySha256')) !=
                hashlib.sha256((ROOT / 'third_party/dependencies.json').read_bytes()).hexdigest()):
            raise ValueError('Release provenance does not match the reviewed tag: ' + name)
        checksum = hashlib.sha256(artifact.read_bytes()).hexdigest()
        sidecar = artifact.with_suffix(artifact.suffix + '.sha256')
        if sidecar.read_text(encoding='ascii').strip() != checksum + '  ' + name:
            raise ValueError('Artifact checksum sidecar mismatch: ' + name)
        if name.endswith('.apk'):
            if (metadata.get('apkSha256') != checksum or metadata.get('certificateSha256') != certificate or
                    metadata.get('signatureV2Verified') is not True or metadata.get('arm64Included') is not True or
                    metadata.get('packagedNoticesVerified') is not True or
                    metadata.get('applicationId') != 'fi.juhonis.receipt_reader' or
                    metadata.get('versionName') != version.name or metadata.get('versionCode') != version.build):
                raise ValueError('Android artifact verification is incomplete')
        elif (metadata.get('zipSha256') != checksum or metadata.get('nativeImportAudit') is not True or
              metadata.get('nativeNoticesVerified') is not True or metadata.get('modelInitialization') is not True):
            raise ValueError('Windows artifact verification is incomplete')
        assets.extend([artifact, sidecar, artifact.with_suffix('.json')])
    return assets


def api(method, url, token, payload=None, content_type='application/json'):
    data = json.dumps(payload).encode('utf-8') if isinstance(payload, dict) else payload
    request = Request(url, data=data, method=method, headers={
        'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'receipt-reader-release',
        'Content-Type': content_type,
    })
    with urlopen(request, timeout=120) as response:
        return json.load(response)


def create_draft(repository, version, commit, assets, notes, token, request=api):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Invalid GitHub repository')
    base = 'https://api.github.com/repos/' + repository
    # Listing with write access includes drafts; the by-tag endpoint alone may not.
    for page in range(1, 11):
        releases = request('GET', base + f'/releases?per_page=100&page={page}', token)
        if not isinstance(releases, list):
            raise ValueError('Invalid GitHub release list')
        if any(release.get('tag_name') == version.tag for release in releases):
            raise ValueError('A release already exists for this tag; it will not be replaced')
        if len(releases) < 100:
            break
    else:
        raise ValueError('Release history exceeds the reviewed lookup bound')
    release = request('POST', base + '/releases', token, {
        'tag_name': version.tag, 'target_commitish': commit, 'name': version.tag,
        'body': notes, 'draft': True, 'prerelease': True,
    })
    if type(release.get('id')) is not int or release['id'] <= 0 or release.get('draft') is not True:
        raise ValueError('GitHub did not return the expected draft release')
    upload = f"https://uploads.github.com/repos/{repository}/releases/{release['id']}/assets?name="
    for path in assets:
        request('POST', upload + quote(path.name, safe=''), token, path.read_bytes(),
                content_type='application/octet-stream')
    return release['html_url']


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--assets', type=Path, default=ROOT / 'build/release-assets')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    try:
        version = sync(check=True, tag=args.tag)
        check_history(version)
        commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip():
            raise ValueError('Draft release requires a clean reviewed checkout')
        subprocess.run(['git', 'rev-parse', '--verify', 'refs/tags/' + version.tag + '^{commit}'],
                       cwd=ROOT, check=True, capture_output=True)
        tagged = subprocess.check_output(['git', 'rev-parse', 'refs/tags/' + version.tag + '^{commit}'],
                                         cwd=ROOT, text=True).strip()
        if tagged != commit:
            raise ValueError('Tag does not identify the checked-out source')
        certificate = (ROOT / 'android/release-certificate.sha256').read_text(encoding='ascii').strip()
        assets = validate_assets(args.assets, version, commit, certificate)
        notes = (ROOT / 'docs/release-notes.md').read_text(encoding='utf-8')
        if not notes.startswith('# ' + version.tag + '\n'):
            raise ValueError('Release notes do not identify the tagged version')
        if args.dry_run:
            print('Validated draft assets:', ', '.join(path.name for path in assets))
        else:
            print('Created draft pre-release:', create_draft(os.environ['GITHUB_REPOSITORY'],
                  version, commit, assets, notes, os.environ['GITHUB_TOKEN']))
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from None
