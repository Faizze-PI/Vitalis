"""Package retained executed evidence; never executes application tests."""
import csv
import hashlib
import json
import shutil
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
import zipfile
import xlsxwriter

EXPECTED = {'01_Behaviour_API_Security': dict(selenium=301, appium=302, bas=892, dast=304, load=302),
            '02_Performance_300': dict(latency=50, throughput=50, stress=50, spike=50, endurance=20, startup=20, resources=20, recovery=20, volume=20)}

def consolidate(root):
    rows = []
    tuning = []
    for programme, suites in EXPECTED.items():
        found = {}
        for path in (root / programme).rglob('results.json'):
            data = json.loads(path.read_text(encoding='utf-8'))
            suite = data.get('suite')
            if suite not in suites:
                continue
            if suite in found:
                raise ValueError('Duplicate suite: ' + suite)
            found[suite] = path
            cases = data['cases']
            if data['status'] != 'PASS' or len(cases) != suites[suite] or any(c['status'] != 'PASS' for c in cases):
                raise ValueError('Unexpected results: ' + suite)
            if len({c['id'] for c in cases}) != len(cases) or data['counts'].get('PASS') != len(cases) or any(v for k, v in data['counts'].items() if k != 'PASS'):
                raise ValueError('Inconsistent counts: ' + suite)
            with zipfile.ZipFile(path.parent / 'report.xlsx') as book:
                xml = ET.fromstring(book.read('xl/worksheets/sheet2.xml'))
                ns = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'
                if len(xml.findall(ns+'sheetData/'+ns+'row')) - 1 != len(cases):
                    raise ValueError('Excel count mismatch: ' + suite)
            with (path.parent / 'test-cases.csv').open(encoding='utf-8-sig', newline='') as stream:
                if len(list(csv.DictReader(stream))) != len(cases):
                    raise ValueError('CSV count mismatch: ' + suite)
            rows.append(dict(programme=programme, suite=suite, executed=len(cases), passed=len(cases), failed=0, skipped=0, verdict='PASS', counted_in_total=True, included_within='', source=data['source'], run_url=data['run_url']))
            if suite == 'bas':
                tuning = [c for c in cases if 'tun' in (c['name']+' '+c['category']).lower()]
        if set(found) != set(suites):
            raise ValueError('Missing suites: ' + programme)
    if len(tuning) != 38:
        raise ValueError('Unexpected tuning subset')
    rows.append(dict(programme='Supplemental coverage', suite='tuning_regressions', executed=38, passed=38, failed=0, skipped=0, verdict='PASS_REGRESSION_ONLY', counted_in_total=False, included_within='bas', source='', run_url=''))
    for suite in ['smoothness', 'concurrency', 'regression', 'device_tuning_benchmark']:
        rows.append(dict(programme='Not executed', suite=suite, executed=0, passed=0, failed=0, skipped=0, verdict='NOT_RUN' if suite == 'device_tuning_benchmark' else 'USER_EXCLUDED', counted_in_total=False, included_within='', source='', run_url=''))
    total = sum(row['executed'] for row in rows if row['counted_in_total'])
    if total != 2401:
        raise ValueError('Unexpected overall total')
    with (root/'FINAL_ASSESSMENT.csv').open('w', encoding='utf-8-sig', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    (root/'FINAL_ASSESSMENT.json').write_text(json.dumps(dict(executed=total, passed=total, failed=0, selected_suites=14, additional_programme_cases=300, rows=rows), indent=2), encoding='utf-8')
    with (root/'TUNING_REGRESSION_SUBSET.csv').open('w', encoding='utf-8-sig', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(tuning[0]), extrasaction='raise')
        writer.writeheader()
        writer.writerows(tuning)
    with xlsxwriter.Workbook(root/'FINAL_ASSESSMENT.xlsx') as book:
        sheet = book.add_worksheet('FINAL ASSESSMENT')
        sheet.write_row(0, 0, list(rows[0]))
        for index, row in enumerate(rows, 1):
            sheet.write_row(index, 0, list(row.values()))
        sheet.freeze_panes(1, 2)
        sheet.autofilter(0, 0, len(rows), len(rows[0])-1)
        sheet.set_column(0, 1, 30)
        sheet.set_column(2, 8, 21)
        sheet.set_column(9, 10, 65)
    (root/'README.md').write_text('# VITALIS consolidated test evidence\n\n14 executed suites: 2,401 passing case records. The additional performance programme contains 300 of these records. Original reports and source/run identities are preserved in the two numbered folders.\n\nThe 38 tuning regression cases are included within BAS, not added again. They do not establish physical-device tuning performance. Smoothness, concurrency and regression suites were excluded by user scope. No new application tests run during consolidation. These scoped results do not establish production, physical-phone or comprehensive security ratification.\n', encoding='utf-8')
    # Keep the original bundle layout; append newer tests in their own folder.
    original = root/'01_Behaviour_API_Security'
    for entry in original.iterdir():
        target = root/entry.name
        if target.exists():
            raise ValueError('Original bundle path collision: ' + entry.name)
        shutil.move(str(entry), str(target))
    original.rmdir()
    (root/'02_Performance_300').rename(root/'Additional-Tests')
    inventory = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file() and p.name != 'SHA256_INVENTORY.json'}
    (root/'SHA256_INVENTORY.json').write_text(json.dumps(inventory, indent=2), encoding='utf-8')
    print(f'Verified {total} passing case records across 14 suites; final CSV/XLSX included.')

if __name__ == '__main__':
    consolidate(Path(sys.argv[1]))
