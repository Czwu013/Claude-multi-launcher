# M3 网页表格与桌面图标

状态：待验收（2026-11-09，v16）

## 目标与实施选择
用户确认快捷方式用本机 Claude Desktop 图标；删除记录仅保留在“···”菜单（v16 用户最新要求）；左侧圆点按住拖动排序。usage 和重置时间都不加。
图标复用现有本机读取函数，不分发资源；删除复用已有确认流程，不扩大删除范围；用 profiles 数组顺序持久化，兼容现有配置。界面保持原配色和系统字体。

## 任务拆分
| # | 任务 | 文件范围 | 机器验证 | 路由 | 结果 |
| --- | --- | --- | --- | --- | --- |
| T1 | 桌面 launcher 使用本机 Claude 图标，保护非本工具同名快捷方式 | tools/New-DesktopShortcut.ps1, src/ClaudeMultiLauncher.psm1 | 沙箱生成 .lnk，比较 IconLocation 与本机提取图标字节，验证重建和拒绝覆盖 | 主 | 一次通过 |
| T2 | 移除行内删除按钮，菜单保留确认流程 | ui/index.html | Playwright mock：行内仅启动/打开/菜单三按钮；点菜单删除不立即删除、取消不变、确认只调用 remove | 主 | 一次通过 |
| T3 | 圆点拖动、键盘排序、Esc 取消、失败回退与保存 | ui/index.html, claude-multi-server.ps1, src/ClaudeMultiLauncher.psm1 | Windows 真模块/dispatcher 重读配置；Playwright 真鼠标、刷新保序、失败回退、边缘滚动 | 主 | 返修1次 |
| T4 | i18n 与回归、交付证据 | src/i18n/*.psd1, tests/* | 两种 PowerShell 核心 78/78、特性 19/19；静态 10 文件、165 键；mock 中英/深浅色及交互 | 主 | 一次通过 |

旧 WinForms/WPF/exe 阶段计划已移至 `../archive/M3_gui_v14.md`，原未验证任务没有补写通过。旧 WPF、真实服务及生命周期等未验收事项保留在 DEBT-009/010/013；本轮任务表只列三个反馈改动。

## 验证结果与边界
- PowerShell 7、Windows PowerShell 5.1 核心各 78/78；特性测试各 19/19（读取本机已安装 Claude 图标，不启动应用）。
- 静态 10 个 PowerShell 文件 BOM / AST / 保守词法审计通过；中英各 165 键及占位符一致。
- Playwright + Edge 全 mock：4 组中英/深浅色截图、2 组深浅色交互套件通过，无页面错误；初版拖动的指针捕获问题已定位修复，见 D-026。
- 图标和快捷方式都仅生成在临时沙箱并清理；没有修改真实桌面，没有启动 Claude、读账号数据或调用用量接口。
- 真实 Explorer 图标观感、操作手感与实际服务关闭重开由用户验收。

## 验收
见 `../reviews/M3_r1.md`；证据见 `../../../tests/evidence/v16/`。

## v23 范围扩展（2026-11-09）
状态：待验收；最新验收卡 `../reviews/M3_r2.md`。上方 v16 记录作为历史保留。

| # | 任务 | 文件范围 | 机器验证 | 状态 |
| --- | --- | --- | --- | --- |
| T5 | 当前会话主进程状态、聚焦与启动等待 | src/CmlProcesses.ps1、src/CmlActions.ps1、核心 summary、server、UI | 双 PowerShell 精确路径/未知/超时/环境恢复；实际 ShellExecute/CIM 测试进程 | 待验收 |
| T6 | 正常关闭及独立强制确认 | 同上 | 身份变化拒绝；句柄绑定；实际 Alpha 退出后 Beta 仍运行；UI 取消/强制参数检查 | 待验收 |
| T7 | 真实分块进度、步骤错误 | 核心、server、UI | 实际 HttpListener；双语延迟分块 mock，含 UTF-8 拆包 | 待验收 |
| T8 | MCP 入口、安装与快捷方式维护 | CmlActions、图标、server、UI、i18n | 不读/复制配置、缺失拒绝、外部快捷方式保护及逐项失败 | 待验收 |

回归：双 PowerShell 核心 78/78、原特性 19/19、新运行管理 42/42；静态 13 文件/214 键；旧 UI 4 组截图+2 套交互，新 UI 4 套交互+2 套分块流。证据 `../../../tests/evidence/v23/`。
未启动真实 Claude，实际前台窗口、托盘行为、当前版本 MCP 路径及更新后维护待用户检查。未加入自动安装、更新、强制账号切换或认证读取。

## v24 原生宿主与品牌资产（2026-11-09）

状态：待验收；当前卡 `../reviews/M3_r3.md`。原 v16/v23 记录保留。

- T9：原创图标用于 launcher EXE / .lnk / README；profile 创建、重建继续本机 Claude 图标；修复 PS 5.1 原子刷新空串路径。沙箱特性 26/26。
- T10：WinForms/WebView2 宿主、固定 SDK 构建、保留 HTML 与 loopback 后端、关闭/父进程异常退出清理；不打开浏览器应用。
- T11：同色标题区、拖动/边缘调整、最大化/还原/最小化/关闭；深浅定向标题区截图及 Win32 实际按钮验证。
- T12：双 PowerShell 核心 78/78、特性 26/26、运行 42/42；静态 15 文件、214/14 翻译键；原 UI 回归及 native 13 项；附便携版、GitHub 源码、验收卡。证据 `../../../tests/evidence/v24/`。

不宣称真实 Claude 登录、隔离或所有系统验收通过；待用户按卡复验。
