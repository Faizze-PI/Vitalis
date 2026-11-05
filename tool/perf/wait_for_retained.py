"""Wait on one existing GitHub run; never restart it after a polling timeout."""
import json,os,subprocess,time
from pathlib import Path
from common import POLICY,require

def wait_terminal(read,clock=time.monotonic,sleep=time.sleep):
    deadline=clock()+POLICY['prior_run_wait_seconds'];last=None
    while clock()<deadline:
        try:
            run=read()
            if run['status']!=last: print('Existing run:',run['status'],flush=True);last=run['status']
            if run['status']=='completed': return run
        except (subprocess.SubprocessError,OSError,ValueError) as error:
            print('Transient polling error:',type(error).__name__,flush=True)
        sleep(POLICY['prior_run_poll_seconds'])
    raise TimeoutError('Existing run remains non-terminal; no restart was attempted')

if __name__=='__main__':
    run_id=os.environ['PRIOR_RUN'];require(run_id.isdigit(),'Numeric prior run required')
    def read():
        return json.loads(subprocess.run(['gh','api',f'repos/{os.environ["GITHUB_REPOSITORY"]}/actions/runs/{run_id}'],check=True,capture_output=True,text=True,timeout=30).stdout)
    result=wait_terminal(read)
    Path('retained-run-state.json').write_text(json.dumps({key:result.get(key) for key in ['id','head_sha','status','conclusion','html_url']},indent=2))
    print('Prior run terminal result:',result['conclusion'],flush=True)
