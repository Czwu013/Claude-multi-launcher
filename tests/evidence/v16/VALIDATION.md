# v16 自动化验收记录

日期：2026-11-09。Windows 上真实运行测试；UI 使用 Playwright + Edge 全 mock，不连接真实账号或 Claude 服务。

| 检查 | 结果 | 边界 |
| --- | --- | --- |
| PowerShell 7.6.9 `tests/Test-Core.ps1 -NoPause` | 78 通过 / 0 失败 | 临时 profile、快捷方式 fixture；StrictMode 2.0 |
| Windows PowerShell 5.1 `tests/Test-Core.ps1 -NoPause` | 78 通过 / 0 失败 | 同上 |
| 两种 PowerShell `tests/Test-Features.ps1 -NoPause` | 各 19 通过 / 0 失败 | 排序真实模块/dispatcher、图标字节及沙箱 .lnk；未启动 Claude |
| 两种 PowerShell `tests/Test-Static.ps1` | 均通过 | 10 文件 UTF-8 BOM / AST，中英 165 键与占位符一致；保守词法变量审计 |
| `node tests/Test-Ui.cjs tests/evidence/v16` | 4 组中英/深浅色 + 2 组交互套件通过，无页面错误 | 行内删除按钮为 0，每行只有启动/打开/菜单；菜单删除确认/取消；拖动、刷新保序、键盘、Esc、保存失败回退及长列表滚动 |
| `python docs/dev/tools/check_docs.py` | 0 ERROR / 0 WARN | 原有偏好模板的占位符为 INFO |

截图人工查看：`table-zh-light.png` 行内无删除按钮，名称括号 `Personal (Baron)`、中文和圆点正常；1000px 紧凑布局检查无操作栏重叠。更多截图和测量见同目录 `ui-results.json`。

机器验收通过；M1 / M3 仍按用户硬规矩保留“待验收”。没有代填用户打分、没有把“要求通过验收”当作各项实机行为已经通过的证据。未读登录数据、调用订阅 usage 接口、修改注册表、真实桌面或用户数据；未启动 Claude。

尚须 Windows 实机确认：所有按钮与真实快捷方式标签；桌面图标重建；拖动后关闭重开保序；关闭 launcher 后 Claude 继续运行且无残留 PowerShell；测试档案的回收站/大目录行为；启动脚本参数；实际目录隔离。勿将 mock 成功当作这些行为的证明。
