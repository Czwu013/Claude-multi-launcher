# v15 验证记录

2026-11-09 · M3 待验收，用户签字和真实桌面体验仍未完成。

## Windows 运行验证
| 环境 | Test-Core.ps1 | Test-Features.ps1 |
| --- | --- | --- |
| Windows PowerShell 5.1.26100.9818 | 78/78 | 19/19 |
| PowerShell 7.6.9 | 78/78 | 19/19 |

Test-Features 使用真实核心模块和 server dispatcher 验证排序：重读保存顺序、大小写、全档案字段不变、全局设置不变、重复/缺失/未知名称拒绝、非法请求不修改配置。
图标来自本机已安装 Claude Desktop，只在临时沙箱保存；比较提取图标字节，检查真实沙箱 .lnk 的 IconLocation、隐藏启动参数、旧图标重建以及保护同名非本工具快捷方式。沙箱退出后清理，不修改真实桌面。

## 静态及网页验证
- Test-Static：10 个 PowerShell 文件均有效 UTF-8 BOM，AST 解析通过；中英各 165 键及占位符一致；保守词法变量审计通过。核心自测开启 StrictMode 2.0，未证明所有未覆盖分支的运行行为。
- Playwright + Edge：4 组中英/深浅色标签截图；2 组深浅色交互套件；1000px 宽的英文行操作无列重叠，均通过，无页面错误。
- 交互包括实际鼠标拖动、保存后刷新保序、Esc 取消、键盘移动/边界、服务端拒绝后回退、可见删除按钮的确认/取消、长列表边缘自动滚动。全部网络请求 mock，不启动真实 launcher server 或 Claude。
- 初版拖动失败通过事件轨迹定位为 moving DOM 导致 lostpointercapture；改为稳定容器捕获后回归通过（D-026）。UI 测试中的多元素等待和确认文案定位也已修正，没有降低业务断言。
- check_docs.py：0 ERROR / 0 WARN；旧阶段计划已归档，未验收工作仍保留在欠账，未标记通过。原偏好/反馈模板占位符仅为 INFO。

## 复跑
在项目根目录：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Core.ps1 -NoPause
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Features.ps1 -NoPause
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Core.ps1 -NoPause
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Features.ps1 -NoPause
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Static.ps1
python docs/dev/tools/check_docs.py
```

特性测试图标部分要求本机已安装 Claude Desktop。
可选：本机已有 Node、Playwright、Edge 时执行 `node tests/Test-Ui.cjs <截图目录>`；CML_PLAYWRIGHT_MODULE 可以指定现有 Playwright 模块路径，launcher 运行本身不依赖这些测试工具。

## 验收边界
本轮未启动 Claude，未实际删除用户数据，未修改真实桌面或注册表，未读取令牌、cookie 或登录数据。
用户确认 usage 和重置时间都不加，没有官方用量页入口或手动倒计时。
真实 Explorer 图标显示、操作手感、真实服务重开保序等请按 docs/dev/reviews/M3_r1.md 验收；旧生命周期、回收站、目录隔离与真实标签映射项继续保留。
