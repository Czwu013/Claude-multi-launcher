<!-- 用途：记录当前代码状态；机器检查不代替用户验收。 -->
# 当前状态

最后更新：2026-11-09 · v24 · M1 / M3 待验收

## 主入口与图标
- 主入口 `claude-multi-launcher.exe`：自编译 WinForms + WebView2 窗口，保留 ui/index.html，不打开 Edge/Chrome 浏览器。CMD 缺少 EXE 时先构建再启动。
- Windows x64、Windows PowerShell 5.1、.NET Framework 4.8、WebView2 Evergreen Runtime。源码首次构建下载固定微软 SDK，校验 SHA-256；便携包含 EXE / SDK DLL / LICENSE / NOTICE，不含 Claude 或运行时安装程序。程序未签名。
- 顶部自绘标题栏与页面背景同步；保留原生拖动、边缘缩放、最小化、最大化/还原、关闭；启动 loading 也用深色底，不显示白色系统标题条。
- 启动器 EXE / 标题栏 / .lnk / 中英文 README 用原创灰色双窗口图标。profile .lnk 使用本机 Claude 原图标，创建/重建刷新；修复 Windows PowerShell 5.1 空字符串备份路径导致原子图标替换失败。
- WebView2 独立缓存；只允许当前本地页面/接口，拒绝外部导航、弹窗、下载；无原生对象或消息桥。随机本机端口与随机令牌保留，令牌仅经父子管道传递，不写 URL 文件。
- 关闭 EXE 仅停止自己绑定的子服务；操作中拦截普通关闭；宿主异常退出由绑定的父进程句柄检测退出服务。未按名称结束 Claude、Edge 或 Chrome。
- 旧浏览器服务入口 / 旧 WPF 保留作历史后备，不是主入口。

## 保留功能
- 档案增删改查、独立性校验、扫描导入、启动、名称括号快捷方式标签、圆点拖动/键盘排序及持久化、中英界面。
- 删除记录只在“···”确认菜单；显式连数据删除仍走预览、独立性/进程/重解析点检查及回收站。
- v23 实例状态、重复启动聚焦、启动等待、真实分块进度、正常关闭/独立强制确认、MCP 路径入口、安装检查及批量修复保留。
- MCP 仅确认后用记事本打开已有文件，不读取/复制配置内容。状态只描述进程，不判断登录。
- 不做登录状态、邮箱、套餐、usage、重置时间；不读令牌/cookie/登录数据、不改注册表、不调用订阅用量接口。
- README 原中英创建演示、Gmail 登录示意 GIF、用户双窗口截图保留，仍注明模拟/未验证边界。

## v24 机器验证
- Windows PowerShell 5.1.26100.9818 与 PowerShell 7.6.9：核心各 78/78、特性各 26/26、运行管理各 42/42。
- 静态：15 个 PowerShell 文件 UTF-8 BOM / AST / 保守词法变量审计，214 UI 键及占位符、14 native JSON 键中英一致；不是全部分支的形式证明。
- 新图标测试：旧 launcher 链接迁移、同名外部链接保护、向缓存注入原创灰图后新建及重建 profile 链接会恢复本机 Claude 图标；只在沙箱生成 .lnk。
- 原网页 mock：4 组中英/深浅截图及 2 套交互；运行管理 mock：4 套交互及 2 套真实分块/UTF-8 流，均通过，无页面错误。
- 真实 EXE / WebView2 / 实际本地后端：13 项通过；中英、取消新建、无浏览器应用子进程、外部导航/资源阻断、无令牌 403、窗口和子服务退出。
- 实际 caption 子窗口截图与 WebView2 正文 CSS 核对深浅背景同色；Win32 按钮句柄验证最大化/还原/最小化。测试 CDP 仅测试进程启用，生产不主动打开调试端口。
- 证据 `tests/evidence/v24/`，最新卡 `reviews/M3_r3.md`。未运行真实 Claude、未登录；验收结论留空。

## 用户验收
- 完整解压便携包直接运行 EXE；运行 create-desktop-shortcut.cmd 重建启动器图标，确认原创图标、顶部同色、拖动/缩放及窗口按钮手感。
- 新建一个可丢弃 profile，确认桌面链接是本机 Claude 原图标；已有 profile 用菜单“重建快捷方式”更新。关闭启动器后 Claude 应继续运行。
- 原待验项保留：Personal → Baron 等真实标签映射、所有按钮、真实两实例聚焦/托盘/关闭、MCP 实际位置及版本更新后修复；test/test2 回收站和大目录；launch.vbs 参数；CLAUDE_CONFIG_DIR / CLAUDE_CODE_TMPDIR / ~/Claude 的实际隔离。
- Windows 10、缺少 Runtime 的电脑、多显示器/高 DPI 及系统主题实时变化仍需实机复验。无自动安装/更新功能。
- doctor、inventory、协议归属与条件性 Cowork 检查仍待做。所有里程碑仅待验收。
