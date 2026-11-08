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
