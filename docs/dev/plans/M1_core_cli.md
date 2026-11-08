<!-- 单个里程碑的方案、实施过程和自测结果。 -->
# M1 核心 CLI

状态：待验收（2026-11-08）

## 目标
用户在 Windows 上能用 `claude-multi.ps1` 创建两个 profile、列出、改名、删除记录，并并行启动，各自独立登录；界面文案中英双语；仓库带 MIT 许可证和合规声明。

## 最可能返工的点
命令体验与中文文案（输出是否清楚、报错是否说人话）；其次是四个位置的默认值与独立性校验是否误拒或漏拒。（"重复点击是否聚焦"依赖 Chromium，不是我们的代码，由你实测。）

## 方案
- `src/ClaudeMultiLauncher.psm1`：核心函数（读写 profiles.json、名称校验、解析 Claude 路径、启动）。
- `src/i18n/zh.psd1`、`en.psd1`：所有文案键值；`auto` 跟随系统界面语言。所有 PowerShell 文件必须是 UTF-8 带 BOM，否则 Windows PowerShell 5.1 会把中文读成乱码。
- `claude-multi.ps1`：入口，子命令 list / add / launch / open / paths / set-path / rename / remove / shortcut / lang / help。
- 每个 profile 的四件套：登录数据 `%APPDATA%\<名称>`、工作区记忆 `%USERPROFILE%\.claude-<名称小写>`、桌面快捷方式 `Claude (<名称>)`、专用文件夹 `%USERPROFILE%\Workspaces\<名称>`，另有临时目录。路径全部由环境变量展开，不写死用户名。
- 快捷方式：用 WScript.Shell 在用户本机生成，目标是 `powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File <入口> launch <名称> -FromShortcut`；`-ExecutionPolicy Bypass` 只对该进程生效，不改系统策略；失败时用消息框提示。图标在本机从已安装应用提取到 `%APPDATA%\claude-multi-launcher\icons\`，失败则用系统默认图标，不入库。
- `remove` 只删除 profiles.json 记录和本工具创建的桌面快捷方式（先预览，输入 y 才执行），不碰任何数据目录。命令行没有跳过确认的参数。
- 独立性校验是纯函数 `Test-CmlIsolation`，5 条规则见 DESIGN §5；`add`、`set-path`、`launch` 之前都会跑。比设计略严：任何位置若**包含**共用位置（例如把专用文件夹设为整个用户目录）也会被拒绝。
- 启动：先 `claudeExe` 配置，其次 `Get-AppxPackage -Name Claude`（精确名、发布者须含 Anthropic、`[version]` 取最新、直接启动 `app\Claude.exe`），最后经典安装目录 `%LOCALAPPDATA%\AnthropicClaude\app-*`（须有有效 Anthropic 签名）；都找不到就报错，不猜路径。子进程环境变量只对启动的进程设置：`CLAUDE_CONFIG_DIR`、`CLAUDE_CODE_TMPDIR`。`-ReuseDefault` 的 profile 不传 `--user-data-dir`。
- `~/Claude/` 在 M1 不重定向，只在输出中提示可能共用。
- 首次启动提醒（D-014）：profile 记录里有 `launched` 标记；首次 `launch` 打印登录须知，若精确路径匹配到其他正在运行的 Claude 进程则加一条警告；从快捷方式启动则弹一次对话框。不判断是否已登录。

## 任务拆分
| # | 任务 | 文件范围 | 机器验证 | 路由 | 结果 |
| --- | --- | --- | --- | --- | --- |
| T1 | 仓库骨架：LICENSE(MIT)、README 合规声明与致谢、.gitignore，且无任何 Claude 图标/二进制 | LICENSE, README.md, .gitignore | grep 确认含"非官方"声明与致谢；find 确认无 .ico/.exe/.png | 主 | 一次通过 |
| T2 | i18n 文案文件与加载函数，中英键集合完全一致 | src/i18n/*.psd1, src/ClaudeMultiLauncher.psm1 | 脚本比对两个 psd1 的键集合相等 | 主 | 一次通过 |
| T3 | profiles.json 读写与 list/add/rename/remove，含名称与路径校验 | src/ClaudeMultiLauncher.psm1, claude-multi.ps1 | 若有 pwsh：对临时目录跑增删改查断言；否则语法解析加走查 | 主 | 一次通过 |
| T3b | 四件套生成：默认路径推导、互不冲突校验、创建专用文件夹（已有则沿用）、生成桌面快捷方式、open 命令 | src/ClaudeMultiLauncher.psm1, claude-multi.ps1 | 用 `Study` 走查四个默认路径与期望一致；grep 确认无删除专用文件夹的代码；若有 pwsh 则对临时目录断言 | 主 | 一次通过 |
| T3c | 位置映射与独立性校验：`paths`、`set-path`、`-Root`、tempDir；实现 DESIGN §5 的 5 条独立性规则；修改位置不移动或删除数据 | src/ClaudeMultiLauncher.psm1, claude-multi.ps1 | 校验函数的用例表逐条走查或在有 pwsh 时断言；grep 确认无 Move-Item/Copy-Item/Remove-Item 作用于用户数据目录 | 主 | 一次通过 |
| T4 | 路径解析（包名精确匹配、发布者校验、[version] 比较）与 launch（含 configDir、tempDir；重复启动依赖 Chromium 单实例，不自写检测） | src/ClaudeMultiLauncher.psm1 | 语法解析；grep 确认无注册表写入、无 Invoke-Expression、无网络调用 | 主 | 一次通过 |
| T5 | 合规自查并生成验收路线 | docs/dev/plans/M1_core_cli.md | grep 合规项逐条记录证据 | 主 | 一次通过 |

## 实施内容
| 文件 | 做了什么 |
| --- | --- |
| `LICENSE`、`.gitignore` | MIT；忽略图标、exe、快捷方式、本机配置 |
| `README.md` | 首屏非官方声明；四件套；命令表；"能做到与做不到"；致谢；中英文摘要 |
| `claude-multi.ps1` | 命令入口；`-WhatIf` 只预演；`-FromShortcut` 出错时弹消息框 |
| `src/ClaudeMultiLauncher.psm1` | 配置读写、路径规范化、独立性校验、profile 增删改查、快捷方式、路径解析与启动 |
| `src/i18n/zh.psd1`、`en.psd1` | 各 160 个文案键 |
| `tests/Test-Core.ps1` | 在 Windows 上可运行的沙箱自测（78 条断言；含 11 条快捷方式标签断言及 1 条摘要空标签断言），不创建桌面快捷方式、不启动 Claude |

## 自测结果（2026-11-09 更新，待用户验收）
| 检查 | 结果 | 证据 |
| --- | --- | --- |
| Windows PowerShell 5.1 / PowerShell 7 核心沙箱自测，StrictMode 2.0 | 各 78/78 通过 | `tests/Test-Core.ps1`；不会启动 Claude，不写真实桌面快捷方式 |
| BOM / PowerShell 语法解析 / 词法变量引用 | 9 个文件通过 | `tests/Test-Static.ps1`；词法审计不代替未覆盖分支的运行验证 |
| i18n 键及占位符 | 各 160 键一致 | `tests/Test-Static.ps1` |
| 标签显示、中英切换、深浅色 | 4 组通过 | `tests/Test-Ui.cjs`，全 mock；`tests/evidence/v14/` |
| 删除预览、导入与既有文件不变 | 沙箱通过 | 核心自测；不覆盖回收站实际删除 |
| T4 启动路径相关机器检查 | 语法解析及代码走查通过 | 未执行真实 launch；运行行为仍由用户验收 |

原 2026-11-08 用户运行结果为 53/53。本轮基于 v13 原有 66 条断言增加 12 条至 78 条，并修复桌面空路径和删除预览用例顺序。

**未验证：** 真实 Claude 启动、真实快捷方式标签映射与图标、关闭 launcher 后子进程独立性、回收站删除和大目录行为、桌面版目录隔离、Cowork/Code 并行。见 `../HANDOFF.md` 与最新验收卡。

## 验收
见 `../reviews/M1_r2.md`（历史卡 M1_r1 保留）
