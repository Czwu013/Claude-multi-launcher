<!-- 用途：记录代码实际状态，机器通过不代表用户验收通过。 -->
# 当前状态

最后更新：2026-11-09 · v19 · M1 / M3 待验收（机器验收与实机人工验收分开记录）

## 已实现
- 核心模块及 CLI：档案增删改查、路径与独立性校验、启动、扫描导入、记录删除、删除预览及回收站删除。
- 网页界面 `claude-multi-server.ps1` + `ui/index.html`，`Claude Multi Launcher.cmd` 为主入口；旧 WPF 暂保留。
- 名称括号显示外部快捷方式标签（如 Personal (Baron)），只读取快捷方式参数及小型启动脚本，不读取登录数据。
- **v15 图标**：launcher 桌面图标与档案快捷方式共用 `Get-CmlIconPath`，只在本机从已安装的 Claude 提取，不随 zip 分发。修复 launcher 原先使用 PowerShell 图标的问题；同名非本工具快捷方式不覆盖。
- **v16 删除**：已按用户最新要求移除每行“删除记录”；“···”菜单内保留记录删除确认和单独的“连数据一起删除”。
- **v15 排序**：左侧圆点按住上下拖动，松手后写入 profiles 数组顺序，刷新/重开保留；支持键盘上下键、Esc 取消、长列表边缘滚动。重复/缺失/未知名称的旧列表被拒绝，失败时界面回退。
- 用户明确不加 usage 和重置时间，未加入官方用量页或手动倒计时（D-027）；不读取令牌、cookie、登录数据，不改注册表。

## 本轮机器验证
- Windows PowerShell 5.1.26100.9818 与 PowerShell 7.6.9：核心自测分别 78/78，新增特性自测分别 19/19；StrictMode 2.0。
- 特性测试验证排序持久化、档案字段不变、拒绝非法列表、真实 server dispatcher、图标字节、沙箱 .lnk 的创建/重建与保护。真实桌面未修改，Claude 未启动。
- `Test-Static.ps1`：10 个 PowerShell 文件均有效 UTF-8 BOM / AST 解析通过；中英各 165 键及占位符一致；保守词法变量审计通过，不代表所有分支的运行证明。
- `Test-Ui.cjs`：Playwright + Edge，全请求 mock；4 组中英/深浅色截图，2 组交互套件通过（真鼠标拖动、刷新保序、取消、失败回退、键盘、删除确认、长列表自动滚动），无页面错误。
- 文档检查：`python docs/dev/tools/check_docs.py`：0 ERROR / 0 WARN；原偏好/反馈模板占位符仅为 INFO。
- 证据：`tests/evidence/v16/`；历史 v14/v15 证据保留。验收卡：`docs/dev/reviews/M3_r1.md`。

## 用户验收与使用
- 解压到稳定位置，运行 `create-desktop-shortcut.cmd` 重建 launcher 桌面图标；档案图标用“··· → 重建快捷方式”更新。核对真实 Explorer 图标显示，不操作注册表或清理系统缓存。
- 在真实窗口拖动圆点，关闭重开确认顺序；取消删除不变，确认后记录消失、数据目录保留；手感由用户判断。
- 原待验项仍在：真实标签映射（尤其 Personal → Baron）、所有按钮、关闭 launcher 后 Claude 继续运行且无残留 PowerShell；test/test2 实际回收站/大目录行为；launch.vbs 启动参数；CLAUDE_CONFIG_DIR / CLAUDE_CODE_TMPDIR 的实际隔离。

## 后续范围
- doctor、inventory、协议归属检测、条件性 Cowork 检查仍未实现。未替用户将任何里程碑标为完成。

## v17 GitHub 发布整理
- 已按最新要求移除行内删除，记录删除在“···”菜单；新增官方政策核查 `docs/POLICY_REVIEW.md`，纠正 README 对隔离与额度的过度承诺。
- 自动化验收记录见 `tests/evidence/v16/VALIDATION.md`；未代填人的评分或将里程碑标完成。
- 用户确认保留现名与本机原图标。README 中英文注明非官方、不用于规避限制；政策说明区分未发现专门禁令、未获明确许可与具体用途，不把缺少许可直接判为违规（D-030）。
- v17 仅整理文档；程序、UI、测试脚本与 v16 字节一致，沿用 v16 已有运行证据；本轮只重跑静态/文档及打包检查。GitHub 交付为源码包，尚未上传仓库。

## v18 动图演示
- README 加入 `docs/media/clone-demo.gif`：真实 UI 交互创建 Personal / Work，各发出一次 mock 启动请求，含不同数据目录的原理说明。
- 约 29 秒，1040×790，68 帧，循环播放；每个画面明确模拟数据，未录制官方登录、未启动 Claude，未访问真实 profile。
- 程序和原测试保持与 v17 相同；沿用 v16 运行证据，本轮只验证演示交互、GIF 解码/内容、文档和打包。M1 / M3 仍待验收。

## v19 英文发布材料
- README.md 改为英文首页并嵌入英文 GIF，中文保留在 README.zh-CN.md，双向链接；增加英文政策说明 docs/POLICY_REVIEW.en.md。
- docs/media/clone-demo-en.gif 使用英文 UI 和字幕：68 帧、28.96 秒，全 mock；原中文 GIF 保留。演示没有真实 Claude 进程、登录或账号读取。
- 程序与原测试不变，沿用 v16 运行证据；本轮验证英文演示交互、图像、双语相对链接、文档与打包。M1 / M3 仍待验收。
