// Optional visual regression test. Needs Playwright and installed Microsoft Edge.
// node tests/Test-Ui.cjs <evidence-directory>
// All requests are mocked; no launcher server, Claude process, or user profile is accessed.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { chromium } = require(process.env.CML_PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const evidence = path.resolve(process.argv[2] || path.join(root, 'tests', 'ui-evidence'));
const inventory = [
  'Personal (Baron) is visible and label fits the name cell',
  'Empty or absent labels render no parentheses',
  'Chinese labels and HTML-like text are safely rendered',
  'Language switch and light/dark themes preserve labels',
  'Mouse drag persists order after reload; keyboard and Escape are supported',
  'Rejected reorder rolls back; dragging at scroll edge reaches offscreen rows',
  'No inline remove button; menu remove requires confirmation and cancel leaves records unchanged',
];
(async () => {
  const tables = {};
  for (const lang of ['zh', 'en']) {
    const file = path.join(root, 'src', 'i18n', lang + '.psd1').replace(/'/g, "''");
    tables[lang] = JSON.parse(execFileSync('powershell.exe', ['-NoProfile','-Command',
      `[Console]::OutputEncoding = [Text.Encoding]::UTF8; Import-Module Microsoft.PowerShell.Utility; Import-PowerShellDataFile -LiteralPath '${file}' | ConvertTo-Json -Depth 4 -Compress`], {encoding:'utf8'}).replace(/^\uFEFF/,''));
  }
  const html = await fs.readFile(path.join(root, 'ui', 'index.html'), 'utf8');
  const fixtures = [
    {name:'Personal', shortcutLabel:'Baron'},
    {name:'Work', shortcutLabel:''},
    {name:'学习', shortcutLabel:'中文标签'},
    {name:'Review', shortcutLabel:'<b>Henry</b>'},
    {name:'Legacy'},
  ].map((p) => ({dataDir:'C:\\Users\\Demo\\AppData\\Roaming\\'+p.name,
    configDir:'C:\\Users\\Demo\\.claude-'+p.name.toLowerCase(),
    workspaceDir:'C:\\Users\\Demo\\Workspaces\\'+p.name,
    tempDir:'C:\\Temp\\'+p.name, hasShortcut:true, launched:true, violations:[], note:'',...p}));
  let browser;
  const errors = [];
  const results = [];
  try {
    await fs.mkdir(evidence,{recursive:true});
    browser = await chromium.launch({channel:'msedge',headless:true});
    for (const theme of ['light','dark']) {
      let lang = 'zh';
      let profiles = fixtures.map(p=>({...p}));
      const reorderCalls = [], removeCalls = [];
      let failNextReorder = false;
      const context = await browser.newContext({viewport:{width:1180,height:800},colorScheme:theme});
      const page = await context.newPage();
      page.on('pageerror',e=>errors.push(e.message));
      await context.route('**/*', async route => {
        const u = new URL(route.request().url());
        if (u.origin !== 'http://127.0.0.1:54321') throw new Error('Unexpected external request');
        if (u.pathname === '/') return route.fulfill({contentType:'text/html; charset=utf-8',body:html});
        if (u.pathname === '/api/lang') lang = route.request().postDataJSON().value;
        if (u.pathname === '/api/reorder') {
          const names=route.request().postDataJSON().names; reorderCalls.push(names);
          if (failNextReorder) { failNextReorder=false; return route.fulfill({json:{ok:false,error:'mock reorder failure'}}); }
          assert.equal(new Set(names).size,profiles.length);
          assert.ok(names.every(n=>profiles.some(p=>p.name===n)));
          profiles=names.map(n=>profiles.find(p=>p.name===n));
        }
        if (u.pathname === '/api/remove') {
          const name=route.request().postDataJSON().name; removeCalls.push(name);
          profiles=profiles.filter(p=>p.name!==name);
        }
        if (!['/api/state','/api/lang','/api/ping','/api/reorder','/api/remove'].includes(u.pathname)) throw new Error('Unexpected API '+u.pathname);
        return route.fulfill({json:u.pathname==='/api/state' ? {ok:true,lang,strings:tables[lang],profiles} : {ok:true}});
      });
      await page.goto('http://127.0.0.1:54321/');
      await page.locator('.name').first().waitFor();
      for (const currentLang of ['zh','en']) {
        if (currentLang === 'en') {
          await page.locator('#langBtn').click();
          await page.waitForFunction(()=>document.documentElement.lang==='en');
        }
        const names = await page.locator('.name').allTextContents();
        assert.deepEqual(names,['Personal (Baron)','Work','学习 (中文标签)','Review (<b>Henry</b>)','Legacy']);
        assert.equal(await page.locator('.name .tag b').count(),0);
        const bounds = await page.locator('.name').evaluateAll(els=>els.map(e=>{
          const cell=e.getBoundingClientRect(),tag=e.querySelector('.tag');
          return {text:e.textContent,overflow:e.scrollWidth>e.clientWidth,tagFits:!tag||tag.getBoundingClientRect().right<=cell.right+1};
        }));
        assert.ok(bounds.every(b=>!b.overflow&&b.tagFits),JSON.stringify(bounds));
        await page.screenshot({path:path.join(evidence,`labels-${currentLang}-${theme}.png`)});
        results.push({theme,lang:currentLang,names,bounds});
      }
      await page.setViewportSize({width:1000,height:800});
      const compact = await page.locator('.row').evaluateAll(rows=>rows.map(row=>{
        const folder=row.children[4].getBoundingClientRect(),ops=row.querySelector('.ops');
        return {noOverlap:ops.firstElementChild.getBoundingClientRect().left>=folder.right,
          fits:ops.lastElementChild.getBoundingClientRect().right<=row.getBoundingClientRect().right};
      }));
      assert.ok(compact.every(c=>c.noOverlap&&c.fits),JSON.stringify(compact));
      await page.screenshot({path:path.join(evidence,`table-en-compact-${theme}.png`)});
      await page.setViewportSize({width:1180,height:800});
      const row = name=>page.locator('.row').filter({has:page.locator(`.name`,{hasText:new RegExp('^'+name+'(?: |$)')})});
      const handle = name=>row(name).locator('.drag-handle');
      const namesNow = ()=>page.locator('.row').evaluateAll(els=>els.map(e=>e.dataset.name));
      const waitOrder = async expected=>{
        await page.waitForFunction(expected=>JSON.stringify([...document.querySelectorAll('.row')].map(e=>e.dataset.name))===JSON.stringify(expected),expected);
        await page.waitForFunction(()=>document.querySelectorAll('.drag-handle:disabled').length===0);
      };
      assert.equal(await page.locator('.remove-record').count(),0);
      assert.equal(await page.locator('.row .ops button').count(),fixtures.length*3);
      const start=await handle('Work').boundingBox(), end=await row('Legacy').boundingBox();
      await page.mouse.move(start.x+start.width/2,start.y+start.height/2); await page.mouse.down();
      await page.mouse.move(end.x+12,end.y+end.height-2,{steps:20});
      await page.waitForFunction(()=>document.querySelector('#rows').lastElementChild.dataset.name==='Work');
      await page.mouse.up();
      const moved=['Personal','学习','Review','Legacy','Work'];
      await waitOrder(moved); assert.equal(reorderCalls.length,1);
      await page.reload(); await waitOrder(moved);
      assert.deepEqual(await namesNow(),moved);
      // Escape cancels a drag without writing order.
      const cancelStart=await handle('Work').boundingBox(), cancelEnd=await row('Personal').boundingBox();
      await page.mouse.move(cancelStart.x+12,cancelStart.y+16); await page.mouse.down();
      await page.mouse.move(cancelEnd.x+12,cancelEnd.y+2,{steps:15});
      await page.waitForFunction(()=>document.querySelector('#rows').firstElementChild.dataset.name==='Work');
      await page.keyboard.press('Escape'); await page.mouse.up();
      assert.deepEqual(await namesNow(),moved); assert.equal(reorderCalls.length,1);
      assert.equal(await page.locator('body.reordering').count(),0);
      // Reject a write to check that UI retains the server's saved order.
      failNextReorder=true;
      await handle('Work').press('ArrowUp');
      await page.getByText('mock reorder failure',{exact:true}).waitFor();
      assert.deepEqual(await namesNow(),moved);
      await page.locator('#layer .primary').click();
      await handle('Work').press('ArrowUp');
      const keyboardMoved=['Personal','学习','Review','Work','Legacy'];
      await waitOrder(keyboardMoved);
      const callCount=reorderCalls.length;
      await handle('Personal').press('ArrowUp');
      assert.equal(reorderCalls.length,callCount);
      // No inline remove; the menu retains the existing record-only confirmation flow.
      await row('Work').locator('button.icon').click();
      await page.locator('.menu button').filter({hasText:tables[lang]['gui.remove']}).click();
      await page.locator('#layer p').filter({hasText:tables[lang]['gui.confirm_note']}).waitFor();
      assert.equal(removeCalls.length,0);
      await page.locator('#layer button').first().click();
      assert.deepEqual(await namesNow(),keyboardMoved);
      await row('Work').locator('button.icon').click();
      await page.locator('.menu button').filter({hasText:tables[lang]['gui.remove']}).click();
      await page.locator('#layer .primary').click();
      await waitOrder(['Personal','学习','Review','Legacy']);
      assert.deepEqual(removeCalls,['Work']);
      // Auto-scroll while holding the dot must reach rows initially below the viewport.
      profiles=[...fixtures.map(p=>({...p})),...Array.from({length:14},(_,i)=>({...fixtures[1],name:'Extra'+i}))];
      await page.reload(); await page.locator('.row').first().waitFor();
      const scroll=await page.locator('.scroll').boundingBox(), longStart=await handle('Personal').boundingBox();
      await page.mouse.move(longStart.x+12,longStart.y+16); await page.mouse.down();
      await page.mouse.move(longStart.x+12,scroll.y+scroll.height-3,{steps:20});
      await page.waitForFunction(()=>document.querySelector('#rows').lastElementChild.dataset.name==='Personal',null,{timeout:15000});
      await page.mouse.up();
      await waitOrder([...fixtures.slice(1).map(p=>p.name),...Array.from({length:14},(_,i)=>'Extra'+i),'Personal']);
      assert.ok(await page.locator('.scroll').evaluate(e=>e.scrollTop>0));
      results.push({theme,interactions:'PASS drag, reload, cancel, keyboard, rejection rollback, remove confirmation, edge auto-scroll',reorderWrites:reorderCalls.length,removed:removeCalls});
      // Final screenshot shows the new controls without transient toast/modal state.
      profiles=fixtures.map(p=>({...p})); lang='zh';
      await page.reload(); await page.locator('.row').first().waitFor();
      assert.ok(await page.locator('.row').evaluateAll(rows=>rows.every(r=>r.scrollWidth<=r.clientWidth)));
      await page.screenshot({path:path.join(evidence,`table-zh-${theme}.png`)});
      await context.close();
    }
    assert.deepEqual(errors,[]);
    await fs.writeFile(path.join(evidence,'ui-results.json'),JSON.stringify({inventory,results,pageErrors:errors},null,2));
    console.log(`PASS mock UI: ${results.filter(r=>r.lang).length} language/theme cases + ${results.filter(r=>r.interactions).length} interaction suites; no page errors; screenshots: ${evidence}`);
  } finally { if (browser) await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1;});
