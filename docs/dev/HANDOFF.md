# 历史交接说明（v13）

> 本文是 v13 历史交接，不代表当前运行环境、验证结果或政策授权。当前以 CURRENT_STATE.md、D-023 / D-027 / D-028 / D-029 / D-030 及 ../POLICY_REVIEW.md 为准；原未决实机清单仍保留。公开包已将本机用户名路径替换为 %USERPROFILE%。

# 任务交接（给接手的 AI，例如 Codex）

时间：2026-11-09。接手前先读 `AGENTS.md` 和 `docs/dev/README.md`，再读本文件。不要通读整个 docs。

## v15 用户反馈补记（2026-11-09）
- 用户已确认图标要与 Claude Desktop 相同；不是灰色自定义图标。launcher 桌面图标脚本现共用本机图标读取函数。
- 每行直接删除记录；左侧圆点拖动排序并保存；用户已明确不加入 usage 或重置时间（包括手动方案）。
- 核心 78/78、特性 19/19，均在 PowerShell 7 和 Windows PowerShell 5.1 通过；静态 10 文件/165 键通过；mock 4 组截图、2 组交互通过。
- 本轮待验收 M3；见 CURRENT_STATE.md、reviews/M3_r1.md。原下文交接及 v14 记录保留为历史，不代表 v15 尚未修改。

## 接手验证补记（2026-11-09，v14）
- 本文件以下为 v13 原始交接记录。当前状态以 CURRENT_STATE.md 为准；原文“云端无 pwsh”“未验证”描述不代表本轮环境。
- 本轮用户已授权使用 Windows pwsh；先跑原测试，修复空桌面路径、旧测试删除预览顺序，再新增 12 条断言。
- PowerShell 7 / Windows PowerShell 5.1 核心自测分别 78/78；9 个 PowerShell 文件 BOM/语法检查通过；i18n 各 160 键一致。
- Playwright + Edge mock 的中英、深浅色 4 组截图通过；源码界面未修改。D-022 与 DEBT-012 已记录“不做”的范围。
- 真实桌面验收清单仍适用，另核对括号标签映射及 cmd/桌面图标闪窗问题；详见 M1_r2 验收卡。

## 项目一句话
`claude-multi-launcher`（窗口名 Claude Multi Launcher）：Windows 上并排运行多个 Claude Desktop profile 的工具。PowerShell 5.1 模块加本地网页界面，中英双语，MIT，只发源码。云端工作区是 Linux，没有 pwsh，只能做静态检查；运行验证由用户在 Windows 上做。

## 代码结构
- `src/ClaudeMultiLauncher.psm1`：核心模块（档案、隔离规则、启动、扫描导入、删除）。
- `claude-multi.ps1`：命令行入口。
- `claude-multi-server.ps1`：本地网页服务（127.0.0.1 随机端口加随机令牌），用 Edge/Chrome `--app` 打开 `ui\index.html`。
- `ui/index.html`：单文件界面，字符串全部来自 `src/i18n/zh.psd1` 和 `en.psd1`，两边键必须一致。
- `Claude Multi Launcher.cmd`：双击直接打开（本次新增，免编译）。
- `create-desktop-shortcut.cmd` 加 `tools/New-DesktopShortcut.ps1`：一次性在桌面生成隐藏 PowerShell 的图标（本次新增）。
- `build-exe.cmd` 加 `tools/Launcher.cs`：可选，本机编译一个 exe 启动器。
- `claude-multi-gui.ps1`：旧 WPF 界面，已被网页界面取代，待用户确认网页版后删除。
- 决策见 `docs/dev/DECISIONS.md`（D-001 到 D-021），债务见 `docs/dev/DEVELOP_DEBT.md`。

## 本轮刚做完、但未验证的改动
1. **名称后面显示桌面快捷方式名**（用户要的：例如 `Personal (Baron)`）。
   - 新函数 `Get-CmlShortcutLabelMap`（模块，已导出）：只读扫描桌面和开始菜单的 `.lnk`，跳过本工具自己创建的（参数含 `claude-multi.ps1` 或 `claude-multi-server.ps1`）；对 wscript/cscript/cmd/powershell 指向的启动脚本，读脚本文本和脚本后第一个路径参数，得到 dataDir，映射成快捷方式的文件名。
   - `Get-CmlProfileSummary` 新增字段 `ShortcutLabel`，server 的 state 输出 `shortcutLabel`，`ui/index.html` 名称列渲染为 `名称 (快捷方式名)`，样式类 `.name .tag`。
   - **没有运行过**。需要在 Windows 上确认：用户桌面上 Baron/Clinton/Doss/Ether/Floyd/Henry/William 这些 `wscript launch.vbs` 快捷方式能否正确对回 profile（用户的 profile 有 test、test2、Personal、Plan、Presentation、Preview、Review、Study、Urban、Work，其中 Personal 应显示 Baron，由用户自己核对）。
   - 还没给 `tests/Test-Core.ps1` 加断言，也没写 `Get-CmlShortcutLabelMap` 的静态检查。
2. **直接打开的程序**：`Claude Multi Launcher.cmd` 加桌面图标脚本。README 快速开始和 DECISIONS（D-021）已更新。未在 Windows 验证 `start "" powershell -WindowStyle Hidden` 是否不闪窗。

## 必须先做的收尾（顺序）
1. 给 `tests/Test-Core.ps1` 补 `Get-CmlShortcutLabelMap` 的断言（可用临时目录里造 `.lnk` 的方式，或只测纯函数部分），把预期断言总数更新到文档里。
2. 静态检查：.ps1/.psm1 保持 UTF-8 带 BOM；中英 i18n 键一致（本轮没有新增键）；`Set-StrictMode 2.0` 下没有未定义变量。
3. 用云端 Playwright 和 `scratchpad` 里的 mock 方式截图验证名称列的括号标签显示（mock 的 state 里加 `shortcutLabel`）。注意旧 mock 在 `/tmp/claude-0/-home-claude/ed3a448b-89f5-54e8-8904-a87a3818a940/scratchpad/mock.py`，会话结束后可能不在。
4. 运行 `python docs/dev/tools/check_docs.py`，处理 ERROR。
5. 更新 `docs/dev/CURRENT_STATE.md`，重新打 zip 给用户。

## 已决定不做的事（不要重新打开）
- **登录状态、邮箱、套餐、额度、重置时间：不做。** 用户已明确决定「一切必须按照 Anthropic 的政策来」。实际调查结论：官方 `claude auth status` 只能看命令行登录，桌面版登录与它是两套（用户实测 Study、Personal 都显示 `loggedIn: false`）；实时额度只能靠读订阅 OAuth 令牌并调用 `api.anthropic.com/api/oauth/usage`，这是 Anthropic 明文不允许的用法，且需解密桌面版本地令牌，项目不做。可行的无令牌替代只有「打开 claude.ai 用量页（地址未核实，疑为 `/settings/usage`）」按钮，用户尚未决定要不要。
- **待补记录**：这条结论还没写进 `DECISIONS.md`（建议编号 D-022）和 `DEVELOP_DEBT.md`，请补上，写清已确认和未确认的事实。
- 不读取令牌、cookie、登录数据；不改注册表；不复制或分发 Claude 二进制。

## 用户尚未回复的 Windows 验证项
- 网页界面所有按钮是否正常：新建、扫描导入、启动、打开文件夹、重建快捷方式、删除记录、语言切换。
- 从界面启动的 Claude 是否在关闭 launcher 窗口后继续独立运行（DEBT-006）。
- test 与 test2 的「连数据一起删除」：是否进回收站、大文件夹是否被 Windows 永久删除。
- 关闭窗口后是否残留 powershell 进程。
- `%USERPROFILE%\ClaudeProfiles\bin\launch.vbs` 的内容（用户还没贴）。
- DEBT-005：桌面版是否真的遵守 `CLAUDE_CONFIG_DIR`（各 `.claude-<名称>` 目录目前是空的）。

## 工作约定（用户偏好）
- 用中文回复，简洁，不写流水账。
- 里程碑只能标「待验收」，只有用户签字才算「完成」。
- 同一问题连续两轮没过就换方案并记 DECISIONS。
- 用户的界面要求：简洁、字体清晰、窗口内不标「非官方」（README 首屏的非官方声明保留）。
- 交付 zip 用 `SendUserFile`。云端 Bash 无网络，不要尝试安装包。
