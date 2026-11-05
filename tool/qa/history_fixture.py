"""Saved-history fixture for disposable hosted emulators only; never a real phone."""
import hashlib,json,os,re,sqlite3,subprocess,tempfile
from pathlib import Path
from report import ROOT,require
PACKAGE='com.vitalis.vitalis_app'
def validate_environment(serial,ci,qemu,hardware="",container_run="",run_id=""):
    if (ci=="true" and serial=="127.0.0.1:5555" and hardware=="redroid"
            and run_id and container_run==run_id): return
    require(ci=='true' and re.fullmatch(r'emulator-\d+',serial) and qemu.strip()=='1',
            'Database fixture is restricted to disposable hosted emulators')

def seed(report,chat_count=1):
    require(type(chat_count) is int and 1<=chat_count<=200,"Bounded fixture chat count required")
    def command(*args,**kwargs):
        return subprocess.run(['adb',*args],check=True,capture_output=True,timeout=30,**kwargs)
    serial=os.environ.get('ANDROID_SERIAL','')
    qemu=command('shell','getprop','ro.kernel.qemu').stdout.decode().strip()
    hardware=command('shell','getprop','ro.hardware').stdout.decode().strip()
    container_run=''
    container=os.environ.get('QA_ANDROID_CONTAINER','')
    if container and re.fullmatch(r'[a-zA-Z0-9_-]+',container):
        container_run=subprocess.run(['docker','inspect','--format',
            '{{index .Config.Labels "com.vitalis.ci"}}',container],check=True,
            capture_output=True,text=True,timeout=10).stdout.strip()
    validate_environment(serial,os.environ.get('GITHUB_ACTIONS',''),qemu,hardware,
                         container_run,os.environ.get('GITHUB_RUN_ID',''))
    constants=(ROOT/'lib/constants/app_constants.dart').read_text()
    match=re.search(r"databaseName\s*=\s*['\"]([A-Za-z0-9_.-]+)['\"]",constants)
    require(match is not None,'Cannot derive actual database identity')
    name=match.group(1); remote='databases/'+name
    command('shell','am','force-stop',PACKAGE)
    require(not subprocess.run(['adb','shell','pidof',PACKAGE],capture_output=True,text=True).stdout.strip(),
            'Database writer still owns app process')
    with tempfile.TemporaryDirectory(prefix='vitalis-ci-history-') as temporary:
        target=Path(temporary)/name
        for suffix in ['', '-wal', '-shm']:
            result=subprocess.run(['adb','exec-out','run-as',PACKAGE,'cat',remote+suffix],capture_output=True,timeout=30)
            if suffix=='': require(result.returncode==0,'Initialized database is unavailable')
            if result.returncode==0: Path(str(target)+suffix).write_bytes(result.stdout)
        original=hashlib.sha256(target.read_bytes()).hexdigest()
        with sqlite3.connect(target) as db:
            require(db.execute('PRAGMA quick_check').fetchone()[0]=='ok','Fixture source database is not healthy')
            version=db.execute('PRAGMA user_version').fetchone()[0]
            require(version>0,'App database initialization has not committed')
            require(db.execute('SELECT COUNT(*) FROM chats').fetchone()[0]==0,'Fixture requires empty disposable app data')
            db.executemany('INSERT INTO chats(title,created_at,updated_at) VALUES(?,?,?)',
                [('CI saved-history fixture' if chat_count==1 else f'CI fixture {i+1:03}',
                  '2026-11-04T00:00:00Z','2026-11-04T00:00:00Z') for i in range(chat_count)])
            db.commit(); require(db.execute('PRAGMA wal_checkpoint(TRUNCATE)').fetchone()[0]==0,'Fixture checkpoint is busy')
        db.close()
        blob=target.read_bytes()
        # All paths derive from the checked app constant and are regex constrained.
        command('shell',f"run-as {PACKAGE} sh -c 'rm -f {remote}-wal {remote}-shm'")
        command('shell',f"run-as {PACKAGE} sh -c 'cat > {remote}'",input=blob)
        copied=command('exec-out','run-as',PACKAGE,'cat',remote).stdout
        require(hashlib.sha256(copied).digest()==hashlib.sha256(blob).digest(),'Fixture copy identity mismatch')
        (report.out/'history-fixture.json').write_text(json.dumps({'scope':'Disposable CI emulator only',
            'database_schema':version,'original_database_sha256':original,'fixture_database_sha256':hashlib.sha256(blob).hexdigest(),
            'inserted_chats':chat_count,'model_records_inserted':0,'model_validation_fabricated':False},indent=2),encoding='utf-8')
