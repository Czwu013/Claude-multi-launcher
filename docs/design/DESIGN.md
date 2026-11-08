<!-- 用途：只写「打算做成什么样」。不写代码现状。设计变了，先改这里，再改代码。 -->
# claude-multi-launcher 设计文档

2026-11-08 · 项目负责人：用户（williamchanu013）· 开发：Claude

## 0. 开工前的批判性问题

| # | 问题 | 本项目的答案 |
| --- | --- | --- |
| 1 | 现在要做的，在不在最小可用版本里？ | 在：profile 增删改查 + 启动 + doctor + 双语。图形界面放在 M3，CLI 先行 |
| 2 | AI 能不能完整读懂、改动这个项目？ | 纯 PowerShell 5.1 + WinForms，零依赖，单文件模块加少量脚本，AI 可整体读写 |
| 3 | 改坏了能不能一键退回？ | git；用户数据（profile 目录）工具默认绝不删除 |
| 4 | 这次是不是只改了一件事？ | 一个里程碑 → 自测 → 人验收 → 存档 |
| 5 | 报 bug 时信息够不够？ | `doctor --report` 一键生成脱敏诊断文本（不含令牌、不含邮箱） |
| 6 | 新对话里的 AI 知不知道规则？ | 读 AGENTS.md 和 docs/dev |
| 7 | 主观的观感参数能不能让人现场调？ | 界面文案、颜色标记放 `config/` 与 i18n 文件，改文件即生效 |
| 8 | 新功能是否真的改变用户决策？ | 每加一项都回答这一问；不做的见 §4 |
| 9 | 版权、合规、上架风险？ | 见下方「合规底线」，同时是验收硬指标 |

### 合规底线（硬约束，违反即不通过验收）

1. **许可证**：本仓库从零新建，代码全部自写，采用 MIT。README 致谢并链接 Zoltak-Dev/ai-multi-instance（技术思路来源）和 vodongha/claude-desktop-clone（启发来源），不复制其源码。
2. **商标与命名**：项目名 `claude-multi-launcher`；README 首屏声明"非官方社区工具，与 Anthropic 无关联、未获其认可"；不使用官方 Logo 与图标作为项目素材。
3. **不动 Claude 应用本体**：不修改、不复制、不重新打包、不分发 Claude 安装文件；只通过官方安装位置启动，附加标准 Chromium 命令行参数 `--user-data-dir`。图标只在用户本机从已安装应用读取用于快捷方式，**不入库、不随发布物分发**。
4. **不碰凭据**：不读取、不解析、不复制、不上传任何登录令牌、Cookie、会话文件；profile 之间不迁移登录态。
5. **不改系统级设置**：不写 `claude://` 协议注册表、不改安全设置、不要求管理员权限。登录回调归属问题只检测并说明。
6. **用途边界**：定位是同一个人合法拥有的多个账号（如工作号与个人号）的并行使用；**不提供**规避用量限制、共享或转售账号、切换第三方 API 的功能，README 与 doctor 输出中写明须遵守 Anthropic 使用条款。
7. **无遥测、无联网**：工具自身不发起任何网络请求。
8. **破坏性操作默认安全**：卸载与删除先预览清单，需用户明确确认；默认只删快捷方式和配置，不删 profile 数据；删数据需额外确认且不可由脚本参数静默跳过。**专用文件夹（Workspaces）里是用户自己的文件，任何命令都不删除它，只可由用户手动处理。**

## 1. 参考与对标

| 项目 | 做法 | 可借鉴 / 要避开 |
| --- | --- | --- |
| Zoltak-Dev/ai-multi-instance | Python 图形界面，`--user-data-dir`，可选补丁 `claude://` 处理器 | 借鉴：抗 MSIX 更新、批量操作。避开：改协议处理器 |
| TonF1917 多窗口项目 | PowerShell + 图形界面，instances.json，主打多 API 并存 | 借鉴：`check` 审计思路。避开：第三方 API 切换、改 MCP 配置、junction 共享会话 |
| Oizopower/ClaudeSwitch | .NET 选择器，profile 存注册表，每次启动重新解析路径 | 借鉴：每次启动解析 exe 路径。避开：注册表存储（改为本地 json） |
| Store 上 Multi Instance | 复制 Claude 便携二进制后启动 | 避开：复制/分发应用二进制 |
| vodongha/claude-desktop-clone | PowerShell + VBS 快捷方式，Cowork VM 限制说明 | 借鉴：profile 数据放 `%APPDATA%` 才能让 Cowork VM 找到镜像；Cowork 同时只能一个 profile |

差异化：**合规优先 + doctor 深度诊断 + 中英双语 + 卸载预览确认 + 按 profile 隔离 Claude Code 配置目录**。

## 2. 概述

一句话：在 Windows 上让同一个人的多个 Claude 账号各用独立 profile 并行运行的、合规透明的、中英双语的小工具。
目标用户：有工作号和个人号的 Claude 桌面版用户（含中文用户）。平台：Windows 10/11，PowerShell 5.1 起，无需管理员权限。

### 2.1 承诺边界（README 与 doctor 必须如实写出，不得夸大）

**能做到：**
- 多个 profile 的窗口同时运行：各自独立的单实例锁、登录、对话与会话记录、Claude Code 配置与记忆、临时目录。
- 各账号的额度由 Anthropic 按账号分别计算，本工具不参与、不干预；工具不提供也不暗示任何规避用量限制的方法。
- 各账号可同时进行各自的普通对话和任务。

**做不到或有条件：**
1. **（条件性，仅当你的版本仍有本地 Cowork）本地 Cowork 同时只能一个 profile 运行**：它依赖整机唯一的 Hyper-V 虚拟机，不分 profile。若你的版本是统一版 Claude、任务只在云端运行、没有本地选项，则本条不适用，工具不得对你显示任何 Cowork 冲突提示。这是应用与系统层面的限制，不修改应用就无法在本工具里消除（合规底线第 3 条）。可行的办法：
   - **改用 Cowork 云端模式**（官方功能，所有付费套餐的桌面版可用：设置 → Cowork → "Run new tasks in the cloud"，或新建会话时点右上角 Beta）。任务在 Anthropic 服务器上运行，理论上不占用本机虚拟机，各账号可各自同时进行；但官方页面未说明它与本地虚拟机的关系，也未说明并发或多账号上限，需你实测。云端模式不保留未交付的工作文件，访问本机文件需要桌面版保持打开。
   - **本地 Cowork 轮换**：`cowork-status` 告诉你哪个 profile 占用，`stop <名称>`（经确认后正常关闭）用于交接。
   其余 profile 仍可同时用于普通对话。
2. **`~/Claude/`（Artifacts 与计划任务输出）很可能共用**：除非实测发现可隔离（§9），否则只提示。
3. **`claude://` 登录回调可能落到别的 profile**：登录时一次只登一个，完成后再登下一个；工具只检测并说明，不改系统注册表。
   提醒方式：首次启动某个 profile 时提醒一次（命令行打印；从桌面快捷方式启动则弹一次对话框），若检测到本机已有其他 Claude 进程在运行则额外警告。工具只记录“是否由本工具启动过”，**不判断你是否已登录**（那需要读取登录数据，违反合规底线 4）。
4. 以上行为依赖 Claude 桌面版本身，版本更新后可能变化；doctor 以实测为准。

## 3. 核心流程

1. `add <名称>` 一次创建 profile 的「四件套」，每个 profile 完全独立、互不共用：
   - 登录数据：`%APPDATA%\<名称>`（例：`C:\Users\<你>\AppData\Roaming\Study`）
   - 工作区记忆（Claude Code 配置目录）：`%USERPROFILE%\.claude-<名称>`（例：`C:\Users\<你>\.claude-study`，目录名小写）
   - 桌面快捷方式：`Claude (<名称>)`
   - 专用文件夹：`%USERPROFILE%\Workspaces\<名称>`（例：`C:\Users\<你>\Workspaces\Study`），已存在则直接沿用，不存在则创建空目录
   四项都可在 `add` 时用参数改路径；默认值按上面规则生成，用户名不写死。
   另有两项可指定位置的生成物：**临时目录**（通过 `CLAUDE_CODE_TMPDIR` 让 Claude Code 的 scratchpad 和图片缓存落在该 profile 自己的目录）和 **输出目录**（对应共用的 `~/Claude/`，实验性，见 §9）。
   查看和修改位置：`paths <名称>` 列出该 profile 所有位置及其是否独立；`set-path <名称> <类型> <路径>` 修改某一项。`-Root <目录>` 可一次把该 profile 除登录数据外的所有目录放到同一根目录下。**修改位置只更新配置并创建空目录，不移动、不复制、不删除任何已有数据**，旧位置的数据会提示用户自行处理。
   **独立性校验**：`add`、`set-path`、`launch` 前和 `doctor` 都会检查，任何一项不通过则拒绝并说明原因（见 §5「独立性规则」）。
2. `launch <名称>` 启动：每次实时解析 Claude 安装路径，附带 `--user-data-dir`，并只对该子进程设置 `CLAUDE_CONFIG_DIR` 指向该 profile 的工作区记忆目录；专用文件夹可用 `open <名称>` 在资源管理器中打开。
3. 已运行则聚焦现有窗口，不重复启动。
4. `doctor` 随时体检，给出中文修复建议。
5. `remove` / `uninstall` 先预览后确认。

## 4. 最小可用版本（MVP）范围

| 做 | 不做（推后 / 永不做） |
| --- | --- |
| `profiles.json` 存储；list / add / rename / remove / launch / open | 第三方 API 切换（永不做） |
| 每个 profile 的四件套：登录数据、工作区记忆、桌面快捷方式、专用文件夹，均独立 | 在 profile 之间共享或同步记忆、会话（不做，保持独立） |
| 各生成位置可指定（`paths` / `set-path` / `-Root`）+ 独立性校验 + 临时目录隔离 | 自动迁移已有数据到新位置（不做，避免误删或损坏）；强制重定向 `~/Claude/`（未验证前不做，见 §9） |
| 实时解析 Claude 路径（抗更新） | 修改 `claude://` 协议注册表（永不做） |
| doctor：安装检测、路径、profile 位置、Cowork 冲突、协议归属检测、脱敏报告 | 读写或迁移登录态与令牌（永不做） |
| 中英双语（CLI 与界面，自动跟随系统，可手动切换） | macOS / Linux（推后） |
| WinForms 管理窗口（M3，已提前到 M2 之前）；用户本机一键编译出的小 exe 启动器 | 发布预编译的 exe（不做，只发源码；见 D-016） |
| 桌面快捷方式（用户本机生成） | 自动更新、遥测（永不做） |
| 卸载与删除：预览 + 确认 | 多 profile 并行 Cowork VM（受官方限制，仅提示） |

**完成标准：**
- [ ] 合规底线 8 条逐条有证据（见各里程碑自测）
- [ ] 两个 profile 能并行启动并各自独立登录（用户在 Windows 上冒烟验证）
- [ ] doctor 能识别至少：未安装、profile 目录不在 %APPDATA%、Cowork 冲突、协议归属
- [ ] 中英文切换后无漏翻文案
- [ ] 删除类操作无法静默执行

## 5. 实体与可调参数

profiles.json（位于 `%APPDATA%\claude-multi-launcher\`，非 profile 数据目录）：

| 字段 | 说明 |
| --- | --- |
| name | 唯一，限字母数字、连字符、下划线、中文，长度 1–32 |
| dataDir | 登录数据，默认 `%APPDATA%\<name>`；必须在 `%APPDATA%` 下，否则 doctor 警告 |
| configDir | 工作区记忆（Claude Code 配置目录），默认 `%USERPROFILE%\.claude-<name 小写>`，每个 profile 必须不同，不允许指向 `~/.claude` 或其他 profile 的目录 |
| workspaceDir | 专用文件夹，默认 `%USERPROFILE%\Workspaces\<name>`；已存在则沿用；工具只创建空目录，**不写入、不删除其中任何文件** |
| shortcut | 桌面快捷方式，默认生成，名称 `Claude (<name>)`；快捷方式只指向本工具的启动入口，不指向版本化的 Claude 路径 |
| tempDir | 临时目录，默认 `%LOCALAPPDATA%\claude-multi-launcher\tmp\<name>`；启动时仅对该子进程设置 `CLAUDE_CODE_TMPDIR`，不改系统 `TEMP` |
| outputsDir | 实验性，默认空（不管理）；对应 Claude 桌面版把 Artifacts 与计划任务结果写入的共用目录 `~/Claude/`，能否按 profile 重定向待验证（§9） |

**独立性规则**（校验不通过则拒绝，M1 必须全部实现）：
1. 同一 profile 的各位置两两不重复、不互相嵌套。
2. 不同 profile 之间的任何位置不重复、不嵌套（路径先展开环境变量、转为绝对路径、统一大小写与结尾分隔符后再比较）。
3. 任何位置不得等于或位于共用位置之内：`~/.claude`、`~/Claude`、`~/Documents/Claude`、默认应用的数据目录（`%APPDATA%\Claude`、`%LOCALAPPDATA%\Claude`）。若用户在 `add` 时用 `-ReuseDefault` 明确选择沿用默认应用数据，则仅此一项豁免并在 `list` 中标注"沿用默认"。
4. 位置本身或其任一上级不得是符号链接或目录联接（reparse point），避免表面独立、实际共用；doctor 同样检查已存在的目录。
5. 专用文件夹（workspaceDir）允许沿用已有目录，但不得位于任何其他 profile 的登录数据或工作区记忆目录内。
| note | 备注（如"工作"），不得包含凭据，界面提示 |

全局：`language`（auto / zh / en）。

## 6. 验收基准（人怎么打分）

| 维度 | 本项目的 4 分是什么样 | 参考对象 |
| --- | --- | --- |
| 能用 | 两个 profile 并行启动；重复点击只聚焦；更新 Claude 后仍可启动；无报错弹窗 | 原项目 Setup/Launch 的可用程度 |
| 看着 | WinForms 窗口整洁对齐、字体不糊、中英文不截断；CLI 输出对齐有颜色但可关闭 | 系统自带设置窗口 |
| 手感 | 常用操作（启动某个 profile）不超过 2 次点击或 1 条命令；启动反馈在 1 秒内 | — |
| 清晰 | 报错说明原因和下一步；doctor 每条结论带"为什么 / 怎么修"；合规声明显眼 | 好的 CLI 报错（如 git） |
| 想继续 | 比手写脚本省事，doctor 真能解决问题，愿意推荐给同事 | — |

**合规硬指标**：§0 合规底线 8 条任何一条被违反，该里程碑直接判不通过，不看分数。

## 7. 技术方案与里程碑

- PowerShell 5.1 兼容（Windows 自带），WinForms 来自系统 .NET Framework，零依赖。
- 结构：`src/ClaudeMultiLauncher.psm1`（核心）· `src/i18n/zh.psd1`、`en.psd1` · `src/gui.ps1` · `claude-multi.ps1`（入口，子命令）· `LICENSE` · `README.md`。
- 路径解析：用 `Get-AppxPackage` 按包名精确匹配并校验发布者，不用 `*Claude*` 通配；多个版本时用 `[version]` 比较取最新；直接启动 `app\Claude.exe`，不走 MSIX 激活（后者不能可靠转发 `--user-data-dir`）；找不到就中文报错并指引，不猜路径。
- 安全编码：所有路径参数校验后再用；删除前强制预览；不使用 `Invoke-Expression`；不写注册表；`-WhatIf` 全面支持。
- 验证方式：开发端是 Linux 云工作区，无法运行 Windows 程序。AI 做静态检查（语法解析、若有 pwsh 则跑解析与单元测试、逻辑走查、合规 grep），用户在 Windows 上走验收路线冒烟。

| 里程碑 | 内容 | 最易返工点 |
| --- | --- | --- |
| M1 核心 CLI | profiles.json、list/add/rename/remove/launch/open/paths/set-path、四件套 + 临时目录、位置可指定、独立性校验、i18n、LICENSE 与 README 合规声明 | 命令体验与中文文案；各位置是否符合预期；独立性校验是否误拒或漏拒 |
| M2 doctor | 体检各项、协议归属检测、脱敏报告、`inventory`（每个 profile 实际生成了哪些目录、占多大、是否写到共用位置）、独立性审计、`cowork-status` 与 `stop <名称>`（均为条件性功能，仅当检测到本机存在本地 Cowork 时启用：前者报告谁占用并建议云端模式，后者经确认后正常关闭该 profile 用于交接） | 结论是否准确、修复建议是否看得懂 |
| M3 图形界面 | WinForms 管理窗口（新建、启动、打开文件夹、查看路径、重建快捷方式、删除记录、切换语言）；`build-exe.cmd` 用 Windows 自带编译器在本机生成小 exe 启动器，另有 .vbs 免编译备选 | 布局与操作流 |
| M4 卸载与收尾 | 预览确认的卸载（快捷方式、登录数据、工作区记忆分级确认；专用文件夹不删）、README 完善、合规总核对 | 删除安全性 |

## 8. 路线图（MVP 之后）

| 顺序 | 系统 | 内容 | 给用户的新决策 |
| --- | --- | --- | --- |
| 1 | macOS 支持 | `open -n -a Claude --args --user-data-dir` | 是否需要 Mac 版 |
| 2 | 签名 exe | 代码签名后再发布二进制 | 是否愿意承担证书成本 |

## 9. 待决问题
- [ ] Claude 桌面版在 Windows 上的可执行文件当前确切位置与包名（默认方案：用 `Get-AppxPackage` 按名称含 Claude 解析，并在 M1 让 doctor 打印所见路径，由用户冒烟时确认）
- [ ] `CLAUDE_CONFIG_DIR` 对桌面版内嵌 Claude Code 是否生效（默认方案：按原项目说法实现并在 README 标注"依赖应用行为，可能随版本变化"）
- [ ] 重复点击同一 profile 是否会聚焦已有窗口（默认方案：不自写检测，依赖 Chromium 的单实例行为；参考项目的 README 也是这样描述的；由你实测确认，doctor 只做诊断）
- [ ] `~/Claude/`（Artifacts 与计划任务输出）能否按 profile 重定向。目前没有找到官方的环境变量或设置项；对子进程改 `USERPROFILE` 风险大（会影响应用对 home 目录的所有解析），不采用（默认方案：M1 不重定向，只在 doctor 里提示"该目录多个 profile 共用"；由你在 Windows 上实测 `Study` 的输出实际写到哪里，再决定是否做）
- [ ] 登录数据目录的实际位置（`%APPDATA%` 还是 `%LOCALAPPDATA%`）与"自定义位置后 Cowork 是否仍能启动"（默认方案：允许自定义，但 doctor 对不在 `%APPDATA%` 下的 profile 警告"Cowork 可能无法启动"，以你的实测为准）
- [ ] `CLAUDE_CODE_TMPDIR` 对桌面版内嵌 Claude Code 是否生效（默认方案：设置它，README 标注依赖应用行为）
- [ ] **如何判断本机是否存在本地 Cowork**（默认方案：doctor 检查登录数据目录里是否出现 `vm_bundles/`、`cowork_vm_node.log` 等本地 Cowork 痕迹；有痕迹才启用 Cowork 相关检查与提示，没有就完全不提示。需你在 Windows 上确认你的 `Study` 目录里有没有这些）
- [ ] **Code 标签页是否也会占用本地虚拟机**（官方数据目录里有 `claude-code-vm/`，用途未说明）。这决定两个 profile 能否同时跑 Code 会话（默认方案：按"Code 可并行，靠 `CLAUDE_CONFIG_DIR` 隔离记忆与记录"设计，由你实测两个 profile 同时开 Code 会话是否报错）
- [ ] **Cowork 云端模式在两个 profile 上能否同时运行、是否仍触发本地虚拟机冲突**（默认方案：README 推荐为首选办法，实测后再定措辞）
