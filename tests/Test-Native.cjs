// Real EXE + WebView2 + loopback service smoke test, with isolated launcher storage.
// CDP is enabled only in this test child's environment. No Claude process is started.
const assert=require('node:assert/strict'),fs=require('node:fs/promises'),path=require('node:path');
const {spawn,execFileSync}=require('node:child_process'),net=require('node:net');
const {chromium}=require(process.env.CML_PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(__dirname,'..'),evidence=path.resolve(process.argv[2]||path.join(__dirname,'evidence/local-native'));
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const ps=code=>execFileSync('powershell.exe',['-NoProfile','-Command',code],{encoding:'utf8'}).trim();
async function freePort(){const s=net.createServer();await new Promise(r=>s.listen(0,'127.0.0.1',r));const p=s.address().port;await new Promise(r=>s.close(r));return p;}
(async()=>{
 console.log('Starting native EXE smoke test');
 await fs.mkdir(evidence,{recursive:true});const sandbox=await fs.mkdtemp(path.join(require('node:os').tmpdir(),'cml-native-'));
 const home=path.join(sandbox,'Home'),local=path.join(sandbox,'Local');await fs.mkdir(home,{recursive:true});await fs.mkdir(local,{recursive:true});
 await fs.mkdir(path.join(sandbox,'Roaming'),{recursive:true});await fs.mkdir(path.join(sandbox,'User'),{recursive:true});
 await fs.writeFile(path.join(home,'profiles.json'),JSON.stringify({version:1,language:'en',claudeExe:'',profiles:[]}));
 const port=await freePort(),exe=path.join(root,'claude-multi-launcher.exe');
 console.log('Starting isolated child');
 // Keep Windows account environment intact for the installed Runtime. Isolate only the
 // launcher's config/cache; directory creation is covered by the separate PS sandbox suites.
 const child=spawn(exe,[],{cwd:root,env:{...process.env,CML_HOME:home,WEBVIEW2_USER_DATA_FOLDER:path.join(local,'WebView2'),
  WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS:'--remote-debugging-port='+port}});
 child.stderr.on('data',data=>console.error(data.toString()));
 let browser,serviceIds=[],report={checks:[]};
 const check=(x,message)=>{assert.ok(x,message);report.checks.push(message);console.log('PASS '+message);};
 try{
  const deadline=Date.now()+40000;
  while(Date.now()<deadline){if(child.exitCode!==null)throw new Error('Native host exited before rendering: '+child.exitCode);try{const q=await fetch('http://127.0.0.1:'+port+'/json/version',{signal:AbortSignal.timeout(1000)});if(q.ok)break;}catch{}await delay(250);}
  browser=await chromium.connectOverCDP('http://127.0.0.1:'+port,{timeout:5000});
  console.log('Connected to native WebView2');
  const context=browser.contexts()[0];let page;
  while(Date.now()<deadline){page=context.pages().find(p=>p.url().startsWith('http://127.0.0.1:'));if(page)break;await delay(250);}
  assert.ok(page,'native host navigated to loopback UI');page.setDefaultTimeout(10000);
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.locator('#status').filter({hasText:'v24'}).waitFor({timeout:15000});
  await page.locator('#empty').waitFor({state:'visible'});
  check(await page.title()==='Claude Multi Launcher','real native host renders existing launcher UI');
  for(const theme of ['dark','light']){
   await page.emulateMedia({colorScheme:theme});await delay(1500);
   const output=execFileSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'Test-NativeWindow.ps1'),'-HostProcessId',String(child.pid),'-EvidenceDir',evidence,'-Theme',theme],{encoding:'utf8',timeout:15000,windowsHide:true});
   const body=await page.evaluate(()=>getComputedStyle(document.body).backgroundColor);
   check(output.includes('PASS')&&body===(theme==='dark'?'rgb(15, 14, 13)':'rgb(245, 244, 238)'),'native '+theme+' caption matches body; native window buttons verified');
  }
  await page.emulateMedia({colorScheme:'dark'});await delay(1200);
  await page.screenshot({path:path.join(evidence,'native-en.png')});
  serviceIds=JSON.parse(ps(`ConvertTo-Json -Compress -InputObject @(Get-CimInstance Win32_Process -Filter 'ParentProcessId=${child.pid}' | Where-Object Name -eq 'powershell.exe' | Select-Object -ExpandProperty ProcessId)`));
  check(serviceIds.length===1,'native host owns exactly one PowerShell loopback service');
  const childNames=JSON.parse(ps(`ConvertTo-Json -Compress -InputObject @(Get-CimInstance Win32_Process -Filter 'ParentProcessId=${child.pid}' | Select-Object -ExpandProperty Name)`));
  check(!childNames.some(x=>/^(msedge|chrome)\.exe$/i.test(x)),'native host starts no Edge or Chrome browser application');
  await page.locator('#langBtn').click();await page.waitForFunction(()=>document.documentElement.lang==='zh');
  await page.screenshot({path:path.join(evidence,'native-zh.png')});
  check(true,'language toggle works through the real local backend');
  await page.locator('#newBtn').click();await page.locator('#cname').fill('NativeAlpha');
  await page.locator('.modal .foot button').first().click();
  const config=JSON.parse(await fs.readFile(path.join(home,'profiles.json'),'utf8'));
  check(config.profiles.length===0,'opening and cancelling the native create dialog creates no profile');
  const before=page.url();await page.evaluate(()=>{location.href='https://example.com/';});await delay(500);
  check(page.url()===before,'external top-level navigation is blocked');
  const external=await page.evaluate(async()=>{try{const r=await fetch('https://example.com/',{signal:AbortSignal.timeout(1500)});return r.status;}catch{return 0;}});
  check(external===0||external===403,'external resource requests are blocked');
  const unauthorized=await page.evaluate(async()=>{const r=await fetch('/api/state',{method:'POST',body:'{}'});return r.status;});
  check(unauthorized===403,'real local service rejects requests without its nonce');
  check(errors.length===0,'no JavaScript page errors in native WebView2');
  ps(`$p=Get-Process -Id ${child.pid}; [void]$p.CloseMainWindow()`);
  const exitDeadline=Date.now()+8000;while(child.exitCode===null&&Date.now()<exitDeadline)await delay(100);
  check(child.exitCode===0,'native window closes cleanly');
  const remaining=JSON.parse(ps(`ConvertTo-Json -Compress -InputObject @(${serviceIds.join(',')} | Where-Object {Get-Process -Id $_ -ErrorAction SilentlyContinue})`));
  check(remaining.length===0,'owned PowerShell service exits with the native window');
  report.status='PASS';await fs.writeFile(path.join(evidence,'native-validation.json'),JSON.stringify(report,null,2));
  console.log('PASS native EXE/WebView2: '+report.checks.length+' checks, actual backend, screenshots, clean shutdown');
 }finally{
  if(browser)await Promise.race([browser.close().catch(()=>{}),delay(2000)]);if(child.exitCode===null)child.kill();
  await delay(500);await Promise.race([fs.rm(sandbox,{recursive:true,force:true,maxRetries:1,retryDelay:100}).catch(()=>{}),delay(3000)]);
 }
})().catch(e=>{console.error(e.stack);process.exitCode=1;});
