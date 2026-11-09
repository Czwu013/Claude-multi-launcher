// Offline UI regression for lifecycle actions. No real Claude, accounts or MCP files.
const assert=require('node:assert/strict'),fs=require('node:fs/promises'),path=require('node:path');
const {execFileSync}=require('node:child_process');
const http=require('node:http');
const {chromium}=require(process.env.CML_PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(__dirname,'..'),evidence=path.resolve(process.argv[2]||path.join(__dirname,'evidence','local-runtime'));
(async()=>{
 const tables={};for(const lang of ['en','zh']) {
  const file=path.join(root,'src','i18n',lang+'.psd1').replace(/'/g,"''");
  tables[lang]=JSON.parse(execFileSync('powershell.exe',['-NoProfile','-Command',`[Console]::OutputEncoding=[Text.Encoding]::UTF8; Import-Module Microsoft.PowerShell.Utility; Import-PowerShellDataFile -LiteralPath '${file}' | ConvertTo-Json -Compress -Depth 4`],{encoding:'utf8'}).replace(/^\uFEFF/,''));
 }
 const html=await fs.readFile(path.join(root,'ui/index.html'),'utf8');await fs.mkdir(evidence,{recursive:true});
 const browser=await chromium.launch({channel:'msedge',headless:true});const errors=[],reports=[];
 try{for(const lang of ['en','zh'])for(const theme of ['light','dark']){
  const t=key=>tables[lang][key];let status='running',failLaunch=false,mcpExists=false,holdLaunch=null;
  const calls=[];const ctx=await browser.newContext({viewport:{width:1180,height:800},colorScheme:theme});const page=await ctx.newPage();page.on('pageerror',e=>errors.push(e.message));
  const profile=name=>({name,dataDir:'C:\\Profiles\\'+name+'\\Data',configDir:'C:\\Profiles\\'+name+'\\Config',workspaceDir:'C:\\Projects\\'+name,tempDir:'C:\\Temp\\'+name,launched:true,hasShortcut:true,violations:[],shortcutLabel:name==='Alpha'?'Baron':'',processStatus:name==='Alpha'?status:'stopped',processIds:name==='Alpha'&&status==='running'?[101]:[]});
  const stream=(steps,result,error)=>[...steps.map((step,i)=>({type:'progress',step,text:t('step.'+step),index:i+1,total:steps.length})),error?{type:'error',error}:{type:'result',result:{ok:true,...result}}].map(x=>JSON.stringify(x)).join('\n')+'\n';
  await ctx.route('**/*',async route=>{
   const req=route.request(),u=new URL(req.url());assert.equal(u.origin,'http://127.0.0.1:54321');
   if(u.pathname==='/')return route.fulfill({contentType:'text/html; charset=utf-8',body:html});
   const action=u.pathname.slice(5),body=req.postDataJSON();calls.push({action,body});
   if(action==='state')return route.fulfill({json:{ok:true,lang,strings:tables[lang],profiles:[profile('Alpha'),profile('Beta')]}});
   if(action==='ping')return route.fulfill({json:{ok:true}});
   if(action==='launch'){
    assert.equal(req.headers()['x-progress'],'1');if(holdLaunch)await holdLaunch;
    return route.fulfill({contentType:'application/x-ndjson',body:stream(['validate','install','process','start','wait_start'],{alreadyRunning:status==='running',focused:false,first:false},failLaunch?'test launch timed out':null)});
   }
   if(action==='stop'){
    assert.equal(body.name,'Alpha');
    if(body.force){assert.deepEqual(body.expectedIds,['101:creation']);status='stopped';}
    return route.fulfill({contentType:'application/x-ndjson',body:stream(['process','close','wait_close'],{stopped:!!body.force,remaining:body.force?[]:['101:creation']})});
   }
   if(action==='mcp-info')return route.fulfill({json:{ok:true,path:'C:\\Profiles\\Alpha\\Data\\claude_desktop_config.json',exists:mcpExists}});
   if(action==='mcp-open'){assert.equal(mcpExists,true);return route.fulfill({json:{ok:true}});}
   if(action==='repair-plan')return route.fulfill({json:{ok:true,exe:'C:\\Installed\\Claude.exe',version:'1.2.3',source:'test',items:[{name:'Alpha',protected:false},{name:'Beta',protected:true}]}});
   if(action==='repair')return route.fulfill({contentType:'application/x-ndjson',body:stream(['install','icon','shortcuts'],{results:[{name:'Alpha',status:'updated'},{name:'Beta',status:'protected'},{name:'Gamma',status:'failed'}]})});
   throw new Error('Unexpected API '+action);
  });
  await page.goto('http://127.0.0.1:54321/?t=mock');await page.locator('.row').first().waitFor();
  const alpha=()=>page.locator('.row[data-name="Alpha"]');
  assert.equal(await alpha().locator('.chip').innerText(),t('gui.running'));
  assert.equal(await page.locator('.row[data-name="Beta"] .chip').innerText(),t('gui.stopped'));
  assert.ok((await alpha().innerText()).includes('Alpha (Baron)'));
  for(const width of [1180,1000]){
   await page.setViewportSize({width,height:800});
   assert.ok(await page.locator('.row').evaluateAll(rows=>rows.every(r=>{const ops=r.querySelector('.ops');return ops.firstElementChild.getBoundingClientRect().left>=r.children[4].getBoundingClientRect().right-1&&ops.lastElementChild.getBoundingClientRect().right<=r.getBoundingClientRect().right;})),'running action buttons overlap at '+width);
  }
  await page.setViewportSize({width:1180,height:800});
  await page.screenshot({path:path.join(evidence,`runtime-${lang}-${theme}.png`)});
  const menu=async key=>{await alpha().locator('.icon').click();await page.locator('.menu').getByRole('button',{name:t(key),exact:true}).click();};
  const modalButton=key=>page.locator('.modal').getByRole('button',{name:t(key),exact:true});
  await menu('gui.stop');await modalButton('gui.cancel').click();assert.equal(calls.filter(c=>c.action==='stop').length,0);
  await menu('gui.stop');await modalButton('gui.stop_go').click();await modalButton('gui.force_go').waitFor();
  assert.equal(calls.filter(c=>c.action==='stop'&&c.body.force).length,0);
  await page.screenshot({path:path.join(evidence,`force-confirm-${lang}-${theme}.png`)});
  await modalButton('gui.cancel').click();assert.equal(status,'running');
  await menu('gui.stop');await modalButton('gui.stop_go').click();await modalButton('gui.force_go').click();await page.locator('.modal').getByText(t('gui.stopped_ok').replace('{0}','Alpha')).waitFor();
  assert.equal(status,'stopped');assert.equal(calls.filter(c=>c.action==='stop'&&c.body.force).length,1);
  await page.locator('.modal button').click();
  await menu('gui.mcp');assert.equal(await modalButton('gui.mcp_open').isDisabled(),true);await modalButton('gui.cancel').click();assert.equal(calls.filter(c=>c.action==='mcp-open').length,0);
  mcpExists=true;await menu('gui.mcp');await modalButton('gui.mcp_open').click();await page.locator('.modal').waitFor({state:'detached'});assert.equal(calls.filter(c=>c.action==='mcp-open').length,1);
  await page.locator('#repairBtn').click();await modalButton('gui.cancel').click();assert.equal(calls.filter(c=>c.action==='repair').length,0);
  await page.locator('#repairBtn').click();await modalButton('gui.repair_go').click();await page.locator('.modal .bad').waitFor();
  const repairText=await page.locator('.modal').innerText();for(const key of ['gui.repair_updated','gui.repair_protected','gui.repair_failed'])assert.ok(repairText.includes(t(key)));
  await page.locator('.modal button').click();
  failLaunch=true;let release;holdLaunch=new Promise(resolve=>release=resolve);
  await alpha().getByRole('button',{name:t('gui.launch'),exact:true}).click();await page.locator('progress').waitFor();
  assert.equal(await page.locator('#newBtn').isDisabled(),true);assert.equal(await alpha().locator('.primary').isDisabled(),true);
  await page.keyboard.press('Escape');assert.equal(await page.locator('progress').count(),1);
  release();holdLaunch=null;await page.locator('.modal .bad').waitFor();
  const errorText=await page.locator('.modal').innerText();assert.ok(errorText.includes(t('step.wait_start'))&&errorText.includes('test launch timed out'));
  assert.equal(await page.locator('#newBtn').isDisabled(),false);
  await page.screenshot({path:path.join(evidence,`step-error-${lang}-${theme}.png`)});
  await page.locator('.modal button').click();failLaunch=false;status='running';
  await page.evaluate(()=>refresh());await alpha().getByRole('button',{name:t('gui.focus'),exact:true}).click();await page.locator('.modal').getByText(t('gui.focus_failed').replace('{0}','Alpha')).waitFor();
  assert.equal(calls.filter(c=>c.action==='launch').length,2);
  reports.push({lang,theme,statusLabels:true,buttonsFit:true,normalCloseAndSeparateForce:true,cancelSafe:true,mcpMissingAndExisting:true,repairPartialResults:true,progressLocksUi:true,stepError:true,focusFailure:true});
  await ctx.close();
 }
 // A loopback mock server sends real delayed chunks, including a split UTF-8
 // character. This checks live rendering/decoding, beyond route.fulfill fixtures.
 for(const lang of ['en','zh']){
  let finish=null;
  const mock=http.createServer((req,res)=>{
   if(req.url==='/'||req.url.startsWith('/?')){res.setHeader('Content-Type','text/html; charset=utf-8');res.end(html);return;}
   if(req.headers['x-token']!=='mock'){res.writeHead(403);res.end();return;}
   if(req.url==='/api/state'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({ok:true,lang,strings:tables[lang],profiles:[{name:'Alpha',dataDir:'C:\\Data\\Alpha',configDir:'C:\\Config\\Alpha',workspaceDir:'C:\\Projects\\Alpha',hasShortcut:true,launched:false,violations:[],processStatus:'stopped'}]}));return;}
   if(req.url==='/api/launch'){
    res.writeHead(200,{'Content-Type':'application/x-ndjson; charset=utf-8'});
    const event=Buffer.from(JSON.stringify({type:'progress',step:'validate',text:tables[lang]['step.validate'],index:1,total:5})+'\n');
    const split=lang==='zh'?event.indexOf(Buffer.from('检查'))+1:Math.floor(event.length/2);
    res.write(event.subarray(0,split));setTimeout(()=>res.write(event.subarray(split)),20);
    setTimeout(()=>res.write(JSON.stringify({type:'progress',step:'wait_start',text:tables[lang]['step.wait_start'],index:5,total:5})+'\n'),50);
    finish=()=>res.end(JSON.stringify({type:'result',result:{ok:true,first:false,alreadyRunning:false}})+'\n');return;
   }
   res.setHeader('Content-Type','application/json');res.end('{"ok":true}');
  });
  await new Promise(resolve=>mock.listen(0,'127.0.0.1',resolve));
  const ctx=await browser.newContext({viewport:{width:1180,height:800},colorScheme:'dark'});
  try{
   const page=await ctx.newPage();page.on('pageerror',e=>errors.push(e.message));await page.goto('http://127.0.0.1:'+mock.address().port+'/?t=mock');
   await page.locator('.row .primary').click();await page.locator('.progress-list .current').getByText(tables[lang]['step.wait_start'],{exact:true}).waitFor();
   assert.equal(await page.locator('progress').getAttribute('value'),'4');assert.equal(await page.locator('.progress-list li').count(),2);
   assert.ok(!(await page.locator('.progress-list').innerText()).includes('\uFFFD'));
   await page.screenshot({path:path.join(evidence,`live-progress-${lang}-dark.png`)});
   finish();await page.locator('progress').waitFor({state:'detached'});
  }finally{if(finish)finish();await ctx.close();await new Promise(resolve=>mock.close(resolve));}
 }
 }finally{await browser.close();}
 assert.deepEqual(errors,[]);await fs.writeFile(path.join(evidence,'runtime-ui-checks.json'),JSON.stringify({reports,pageErrors:errors,allRequestsMocked:true,liveChunkedMockLanguages:['en','zh'],splitUtf8Decoded:true},null,2));
 console.log('PASS lifecycle mock UI: '+reports.length+' language/theme suites; screenshots and checks saved');
})().catch(error=>{console.error(error);process.exit(1)});
