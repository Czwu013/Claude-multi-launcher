> 归档于 2026-11-09：旧 WinForms/WPF/exe 阶段计划，原任务结果保留，不补写通过。当前网页反馈范围见 ../plans/M3_table_controls.md；旧 WPF 未验收项保留在 DEBT-009，真实服务与生命周期等保留在 DEBT-010/DEBT-013。

<!-- 单个里程碑的方案、实施过程和自测结果。 -->
# M3 图形界面与 exe 启动器

状态：进行中（2026-11-08，已提前到 M2 之前，见 D-016）

## 目标
用户双击一个程序就能打开窗口：输入名称点“一键生成”建好四件套和桌面快捷方式，在列表里启动、打开专用文件夹、查看路径、重建快捷方式、删除记录、切换语言，全程不需要开 PowerShell。

## 最可能返工的点
布局与操作流（按钮位置、提示文案）；exe 编译与启动是否顺利。

## 方案
- `claude-multi-gui.ps1`：WinForms 窗口，只调用模块函数，不含自己的业务逻辑。删除记录前自己弹确认框，再以 `-AssumeYes` 调用 `Remove-CmlProfile`；仍然只删记录和本工具创建的快捷方式。
- 模块新增 `Get-CmlProfileSummary`（无控制台输出的纯数据）并导出 `Get-CmlItemLabel`。
- `tools/Launcher.cs` + `build-exe.cmd`：用 Windows 自带 `csc.exe`（.NET Framework 4，C# 5）在本机编译 winexe，它只隐藏地启动 `claude-multi-gui.ps1`。不发布预编译 exe。
- `claude-multi-launcher.vbs`：免编译备选。
- 新增 24 个 `gui.*` 文案键（中英同键）。

## 任务拆分
| # | 任务 | 文件范围 | 机器验证 | 路由 | 结果 |
| --- | --- | --- | --- | --- | --- |
| T1 | 模块新增摘要函数与导出，补自测断言 | src/ClaudeMultiLauncher.psm1, tests/Test-Core.ps1 | 括号配对；自测在 Windows 通过 | 主 | |
| T2 | 窗口脚本与 gui 文案键 | claude-multi-gui.ps1, src/i18n/*.psd1 | 括号配对、BOM、中英键一致、引用的键都存在、无删除/注册表调用 | 主 | |
| T3 | exe 启动器与一键编译、vbs 备选 | tools/Launcher.cs, build-exe.cmd, claude-multi-launcher.vbs | 静态检查；你在 Windows 上编译并启动 | 主 | 一次通过 |
| T4 | 扫描并导入已有 clone：scan、import、窗口对话框 | src/ClaudeMultiLauncher.psm1, claude-multi.ps1, claude-multi-gui.ps1, src/i18n/*.psd1, tests/Test-Core.ps1 | 括号配对、BOM、中英键一致、引用键都存在；自测新增 7 条；grep 确认无新增删除/移动/注册表调用 | 主 | |
| T5 | WPF 新界面（卡片、深浅色）替换 WinForms 窗口，含扫描对话框 | claude-multi-gui.ps1, src/i18n/*.psd1 | XAML 按 XML 解析且资源键齐全；括号配对、BOM、中英键一致、引用键都存在 | 主 | |
| T6 | 本地网页界面与服务，exe 启动器改为启动服务 | claude-multi-server.ps1, ui/index.html, tools/Launcher.cs, build-exe.cmd | 页面用 Chromium 加模拟接口渲染并截图检查（深浅色、中英文、新建/扫描弹窗）；脚本括号配对与 BOM | 主 | |

## 自测结果（AI 完成）
括号配对、BOM、中英键集合一致（108 键）、引用的键均存在：通过。窗口、编译、exe 启动均未在 Windows 上运行过（DEBT-007）。

## 追加（2026-11-09）
用户要求自动检测这台电脑上已有的手搓 clone，找不到可手动输入路径。新增 T4：`scan`（只读检测：运行中进程的命令行、桌面与开始菜单的快捷方式/启动脚本、按文件夹内文件名判断的 Claude 数据目录）、`import`（只登记，不复制不改动原目录）、窗口里的“扫描已有 clone”对话框（勾选导入、可改名、手动添加路径）。
识别方式补充（2026-11-09）：用户桌面快捷方式是 `wscript.exe launch.vbs <数据目录> <配置目录>`，参数里没有 `--user-data-dir`；扫描改为：目标是 wscript/cscript/cmd/powershell、参数里有脚本且脚本提到 Claude 时，把脚本后的路径依次当作数据目录与配置目录。

## 追加（2026-11-09）
窗口改写为 WPF（D-017）：卡片列表、圆角、深浅色跟随系统；扫描对话框同步改写。任务迁移经你实测各 profile 的本地会话文件夹接近 0 KB（没有可迁移内容），已从计划中划掉。

再次改写（D-019）：界面改为本地网页，由 `claude-multi-server.ps1` 提供并用 Edge 应用窗口显示；新增 T6：网页界面与本地服务。
