"""Native host reports from two independently terminated real test runners."""
import argparse
import json
import re
from pathlib import Path

from validation_report import parse_events, write_reports


def make_native_report(inputs, root, source, run_url):
    cases, problems, identities = [], [], set()
    if set(inputs) != {'lifecycle', 'fault'}:
        problems.append('Both native runner partitions are required')
    for partition in ('lifecycle', 'fault'):
        actual, failures, _ = parse_events(inputs.get(partition, ''), root)
        problems.extend(f'{partition}: {failure}' for failure in failures)
        for case in actual:
            identity = (case['file'], case['name'])
            if identity in identities:
                problems.append('Duplicate native test identity across runners')
                continue
            identities.add(identity)
            cases.append({**case, 'id': len(cases) + 1, 'partition': partition})
    if not re.fullmatch(r'[a-f0-9]{40}', source):
        problems.append('Missing or invalid source commit identity')
    counts = {status: sum(case['status'] == status for case in cases)
              for status in ('PASS', 'FAIL', 'SKIP')}
    return {'source': source, 'run_url': run_url,
            'status': 'PASS' if not problems and not counts['FAIL'] and not counts['SKIP'] else 'FAIL',
            'counts': counts, 'test_count': len(cases), 'cases': cases,
            'runner_elapsed_ms': None, 'measurements': [], 'problems': problems,
            'scope': 'Host native lifecycle and isolated fault assertions. Separate runner clocks; '
                     'no combined wall-time, phone performance, storage workload or sanitizer result inferred.'}


def main():
    parser = argparse.ArgumentParser()
    for name in ('directory', 'root', 'source', 'run-url'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    directory = Path(args.directory)
    def read(name):
        path = directory / name
        return path.read_text(encoding='utf-8-sig') if path.exists() else ''
    report = make_native_report({'lifecycle': read('machine.log'), 'fault': read('fault-machine.log')},
                                args.root, args.source, args.run_url)
    write_reports(report, directory / 'reports')
    print(json.dumps({key: report[key] for key in ('status', 'test_count', 'counts', 'problems')}))
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
