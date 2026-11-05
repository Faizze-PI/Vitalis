"""Performance evidence helpers. Unknown measurements are not passing results."""
import csv,io,json,math,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tool/qa'))
from report import Report,require
POLICY=json.loads((ROOT/'tool/perf/policy.json').read_text())
CATALOGUE=json.loads((ROOT/'tool/perf/catalogue.json').read_text())
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

def regression_pairs(current,baseline):
    if baseline is None: raise EvidenceUnavailable('No retained comparable performance baseline run was supplied')
    if current.get('measurements',{}).get('environment')!=baseline.get('measurements',{}).get('environment'):
        raise EvidenceUnavailable('Baseline environment/workload/build mode differs')
    a=current.get('measurements',{}).get('samples',[]); b=baseline.get('measurements',{}).get('samples',[])
    if len(a)!=POLICY['cases'] or len(b)!=POLICY['cases'] or baseline.get('status')!='PASS':
        raise EvidenceUnavailable('Baseline or current latency sample set is incomplete')
    for left,right in zip(a,b):
        if left['name']!=right['name']: raise EvidenceUnavailable('Baseline workloads differ')
        before=right['measurements']['ui_ready_ms'];after=left['measurements']['ui_ready_ms']
        if not all(type(v) in (int,float) and math.isfinite(v) and v>0 for v in [before,after]):
            raise EvidenceUnavailable('Non-finite or missing baseline timing')
    return list(zip(a,b))

def host_cpu_identity(path=Path('/proc/cpuinfo')):
    keys={'CPU implementer','CPU architecture','CPU variant','CPU part','CPU revision','model name'}
    return sorted(set(line.strip() for line in path.read_text().splitlines() if line.partition(':')[0].strip() in keys)) or ['unknown']
