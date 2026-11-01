"""Fetch JUnit evidence from the results location printed by gcloud."""
import pathlib
import re
import shutil
import subprocess
import sys


def results_root(log):
    matches = re.findall(r'https://console\.developers\.google\.com/storage/browser/(test-lab-[a-z0-9-]+)/([A-Za-z0-9_.:-]+)/', log)
    if len(set(matches)) != 1:
        raise ValueError('Expected one managed Firebase results location')
    bucket, directory = matches[0]
    return f'gs://{bucket}/{directory}'


if __name__ == '__main__':
    directory = pathlib.Path(sys.argv[1])
    root = results_root((directory / 'gcloud.log').read_text())
    gcloud = shutil.which('gcloud')
    if not gcloud:
        raise RuntimeError('Google Cloud CLI must be on PATH')
    for api in ('28', '35'):
        subprocess.run([gcloud, 'storage', 'cp',
                        f'{root}/MediumPhone.arm-{api}-en-portrait/test_result_1.xml',
                        str(directory / f'api{api}.xml')], check=True)
