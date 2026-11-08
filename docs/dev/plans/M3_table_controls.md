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
