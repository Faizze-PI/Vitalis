import json, re, time, urllib.request
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from report import require

def run(report):
    options=webdriver.ChromeOptions()
    for flag in ['--headless=new','--no-sandbox','--disable-dev-shm-usage']: options.add_argument(flag)
    options.set_capability('goog:loggingPrefs',{'performance':'ALL','browser':'ALL'})
    driver=webdriver.Chrome(options=options)
    url='https://huggingface.co/api/models?filter=gguf&sort=downloads&direction=-1&limit=50&full=true'
    try:
        driver.set_page_load_timeout(90); driver.get(url)
        text=WebDriverWait(driver,30).until(lambda d:d.find_element(By.TAG_NAME,'pre').text)
        data=json.loads(text); (report.out/'hub-browser-response.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
        require(isinstance(data,list) and len(data)==50,'Expected 50 actual GGUF search records')
        fields={
            'repository identity':lambda e:isinstance(e.get('id'),str) and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',e['id']),
            'immutable revision':lambda e:isinstance(e.get('sha'),str) and re.fullmatch(r'[a-fA-F0-9]{40}',e['sha']),
            'download count':lambda e:type(e.get('downloads',0)) is int and e.get('downloads',0)>=0,
            'tags':lambda e:isinstance(e.get('tags',[]),list) and all(isinstance(t,str) for t in e.get('tags',[])),
            'private access flag':lambda e:type(e.get('private',False)) is bool,
            'gated access flag':lambda e:isinstance(e.get('gated',False),(str,bool)),
        }
        for entry in data:
            for field,check in fields.items(): report.case(f"{entry.get('id')}: {field}",lambda e=entry,c=check:require(c(e),'VITALIS API contract mismatch'),field)
        def direct():
            start=time.perf_counter()
            with urllib.request.urlopen(urllib.request.Request(url,headers={'Accept':'application/json'}),timeout=45) as r:
                require(r.status==200 and 'json' in r.headers.get('Content-Type',''),'Unexpected API response')
                require(isinstance(json.load(r),list),'API shape')
            report.metrics['direct_api_response_ms']=(time.perf_counter()-start)*1000
        report.case('Direct API status, content type and schema',direct,'HTTP connectivity')
        (report.out/'browser-network.json').write_text(json.dumps(driver.get_log('performance')),encoding='utf-8')
        driver.save_screenshot(str(report.out/'api-browser.png'))
        report.metrics['scope']='300 field-contract checks across 50 real GGUF search records, plus direct HTTP validation. Two read-only public requests; not native inference or 300 user journeys.'
    finally: driver.quit()
