# v24 — Native window and original launcher icon

- Added an original gray overlapping-window icon to the launcher EXE, title strip, launcher desktop shortcut and bilingual READMEs. Profile shortcuts retain the locally installed Claude icon and refresh it on create/rebuild.
- Replaced the browser-app wrapper with a WinForms / WebView2 EXE that embeds the existing UI. Native caption and page backgrounds match in dark/light themes; drag/resize and caption controls remain.
- Pinned the Microsoft SDK package/hash, included its license/notice in portable builds, kept random loopback authentication and scoped child-service cleanup. External content/navigation is blocked.
- Fixed Windows PowerShell 5.1 icon-refresh replacement with NullString.Value.
- Machine checks: both PowerShell versions core 78/78, features 26/26, runtime 42/42; static 15 files / 214 UI keys / 14 native keys. Native EXE smoke 13 checks plus existing mock UI regression. No real Claude process/sign-in tested.
- Windows x64, .NET Framework 4.8, Windows PowerShell 5.1 and WebView2 Evergreen Runtime required. Unsigned portable EXE, not a single-file distribution. No Claude binaries/icons/account data included. Pending human acceptance: M3_r3.
# v23 — Instance lifecycle and maintenance

November 9, 2026

- Added live process status, idle refresh, duplicate-launch focus and a bounded launch check. Process status is separate from login.
- Added streamed operation steps and step-specific errors. Closing an instance first requests normal shutdown; force termination requires a separate confirmation and verified process identities/handles.
- Added an existing-file-only MCP config entry and preview/confirmation for local installation checks, icon refresh and profile shortcut repair. External same-name shortcuts remain protected; failures are reported per item.
- Core 78/78, existing features 19/19 and new runtime 42/42 passed on both Windows PowerShell 5.1 and PowerShell 7. Actual Windows process/HTTP tests used inert self-built helpers; UI checks used mock actions. Real Claude acceptance remains pending.
- Existing GIFs/screenshots, ordering, menu-only record removal, naming and locally sourced icon behavior are preserved. No account data, login status, usage/reset tracking, app installer or registry modification was added.

# v22 — Gmail-style sign-in tutorial

November 9, 2026

- Replaced generic cards with separate Claude desktop, Gmail inbox/message, browser handoff and manual-code scenes.
- Updated both embedded GIFs: 1280×900, 39.02 seconds, English or Chinese captions, cursor highlights and persistent reconstruction labels.
- This is an illustrated reconstruction using sample data, not a live sign-in test or a verified copy of current authentication screens. Existing application code/tests and previous media are unchanged; Windows acceptance remains pending.

# v21 — Email sign-in tutorial

November 9, 2026

- Added illustrated English and Chinese Test sign-in GIFs and detailed steps to both READMEs.
- Emphasized Cancel on the browser handoff prompt, Log in with code, and entering the code in the new Test desktop window.
- Distinguished browser-only sign-out (user-described behavior, not independently tested here) from all-session logout, which official help says also signs out desktop apps.
- Both animations use placeholder email/code and schematics, not live authentication. Application code and existing tests remain unchanged; Windows acceptance remains pending.

# v20 — Side-by-side screenshot

November 9, 2026

- Added the user-provided screenshot of two Claude Desktop windows to both READMEs, before the existing animated demo.
- The original screenshot and both language versions of the GIF are preserved.
- Application code and existing tests are unchanged. Documentation and package checks only; no new claims about account isolation or sign-in.
- Not uploaded to GitHub by this task; Windows acceptance remains pending.

# v19 — English documentation and demo

November 9, 2026

- English README as the repository homepage, with a link to README.zh-CN.md.
- Embedded English GIF with English UI, captions and an explanation of separate profile data directories. The Chinese GIF is retained.
- English policy notes distinguish implementation facts, applicable scope and unresolved questions; unofficial status and the prohibition on limit evasion are preserved.
- Application name, local shortcut icon, program code and existing tests are unchanged.
- The English demo uses mock responses. No real Claude process or sign-in was recorded.
- Existing v16 runtime evidence is retained. This update validates demo interactions, GIF decoding, bilingual links, documents and packaging. Real Windows acceptance is still pending.
- This package has not been uploaded to GitHub. Internal development documentation remains primarily Chinese.

# v18

2026-11-09

- README 加入约 29 秒的 profile 创建/启动 GIF，演示 Personal 和 Work 两个示例以及数据目录原理。
- 动图全程注明模拟数据；启动请求使用 mock，官方登录未录制，未启动 Claude。
- 名称、图标、程序及既有测试保持不变；沿用 v16 运行证据。本轮验证演示交互、GIF、文档与打包。
- 尚未上传 GitHub，里程碑仍待验收。

# v17

2026-11-09

- 保留现有项目名、窗口名和本机 Claude Desktop 快捷方式图标。
- README 中英文明确非官方身份，禁止用于绕过限制、封禁、共享或转售账号。
- 政策说明改为区分实现事实、条款适用范围及尚未确认事项；不把缺少明确许可直接认定为违规，也不保证官方认可。
- 本轮仅更新文档；程序、UI、测试与 v16 相同，沿用下列运行证据；本轮另行检查静态、文档、打包完整性。
- 源码包已整理，尚未上传 GitHub；里程碑仍为待验收。

# v16

2026-11-09

- 按最新要求移除每行“删除记录”按钮，保留“··· → 删除记录”的确认流程及独立的数据删除预览。
- 保留左侧圆点拖动排序、持久化、键盘操作，以及用户选择的本机 Claude Desktop 图标。
- PowerShell 7 与 Windows PowerShell 5.1 核心测试各 78/78、特性各 19/19；静态检查通过，Playwright mock 4 组截图用例与 2 组交互套件通过。
- 新增 [官方政策核查](docs/POLICY_REVIEW.md)，纠正未经验证的隔离/额度承诺。品牌许可及 Desktop 多开授权仍未明确，不宣称官方认可或完全合规。

源码包无第三方程序、官方图标、凭据或用户配置。解压后直接双击 `Claude Multi Launcher.cmd`；桌面快捷方式需运行 `create-desktop-shortcut.cmd` 重建。

机器验收通过，里程碑保持待验收；真实启动、隔离、回收站和窗口生命周期见 [当前状态](docs/dev/CURRENT_STATE.md)。此包尚未上传 GitHub。
