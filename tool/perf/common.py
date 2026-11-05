"""Performance evidence helpers. Unknown measurements are not passing results."""
import csv,io,json,math,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tool/qa'))
from report import Report,require
__all__=['Report','ROOT','POLICY','CATALOGUE','require','EvidenceUnavailable','percentile','frame_durations','regression_pairs','host_cpu_identity','case_count','baseline_samples']
POLICY=json.loads((ROOT/'tool/perf/policy.json').read_text())
CATALOGUE=json.loads((ROOT/'tool/perf/catalogue.json').read_text())
def case_count(suite):
    return next(row['minimum'] for row in CATALOGUE if row['name']==suite)

class EvidenceUnavailable(Exception): pass

def percentile(values,fraction):
    require(bool(values),'No samples')
    values=sorted(values)
    return values[max(0,math.ceil(fraction*len(values))-1)]

def frame_durations(text):
    header=None;values=[]
    for row in csv.reader(io.StringIO(text)):
        if 'IntendedVsync' in row and 'FrameCompleted' in row:
            header={name:i for i,name in enumerate(row)};continue
        if not header: continue
        try:
            flags=int(row[header['Flags']]);start=int(row[header['IntendedVsync']]);end=int(row[header['FrameCompleted']])
            if flags==0 and 0<start<end<9223372036854775807: values.append((end-start)/1e6)
        except (ValueError,IndexError,KeyError): continue
    return values

def baseline_samples(environment,apk_source,baseline):
    if baseline is None: raise EvidenceUnavailable('No retained comparable performance baseline run was supplied')
    values=baseline.get('measurements',{})
    if not apk_source or apk_source==values.get('apk_source'):
        raise EvidenceUnavailable('Cross-build regression requires a separately built candidate; use fresh_candidate')
    if environment!=values.get('environment'): raise EvidenceUnavailable('Baseline environment/workload/build mode differs')
    samples=values.get('samples',[])
    if len(samples)<case_count('regression') or baseline.get('status')!='PASS':
        raise EvidenceUnavailable('Baseline latency sample set is incomplete')
    selected=samples[:case_count('regression')]
    for sample in selected:
        value=sample['measurements']['ui_ready_ms']
        if not(type(value) in (int,float) and math.isfinite(value) and value>0):
            raise EvidenceUnavailable('Non-finite or missing baseline timing')
    return selected

def regression_pairs(current,baseline):
    values=current.get('measurements',{})
    before=baseline_samples(values.get('environment'),values.get('apk_source'),baseline)
    after=values.get('samples',[])[:case_count('regression')]
    if len(after)!=case_count('regression'): raise EvidenceUnavailable('Current latency sample set is incomplete')
    for left,right in zip(after,before):
        if left['name']!=right['name']: raise EvidenceUnavailable('Baseline workloads differ')
        value=left['measurements']['ui_ready_ms']
        if not(type(value) in (int,float) and math.isfinite(value) and value>0):
            raise EvidenceUnavailable('Non-finite or missing candidate timing')
    return list(zip(after,before))


def host_cpu_identity(path=Path('/proc/cpuinfo')):
    keys={'CPU implementer','CPU architecture','CPU variant','CPU part','CPU revision','model name'}
    return sorted(set(line.strip() for line in path.read_text().splitlines() if line.partition(':')[0].strip() in keys)) or ['unknown']
