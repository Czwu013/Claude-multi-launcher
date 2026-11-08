# v14 交付验证记录

日期：2026-11-09。里程碑：待验收。

- Windows PowerShell 5.1.26100.9818：Test-Core 78 通过 / 0 失败。
- PowerShell 7.6.9：Test-Core 78 通过 / 0 失败。
- Test-Static：9 个 PowerShell 文件有效 UTF-8 BOM、AST 解析通过；中英各 160 键及占位符一致；保守词法变量引用审计通过。
- Test-Ui：Playwright + Microsoft Edge，无真实服务、所有请求 mock，中英 × 深浅色四组通过；截图与 ui-results.json 在同目录。
- check_docs.py：0 ERROR / 0 WARN；未修改偏好/反馈模板的占位符只产生 INFO。

## 改动
- Test-Core 增加 11 条快捷方式标签映射断言和 1 条摘要空标签断言，共 78 条；临时目录里生成真实 .lnk，验证脚本参数、脚本内容、直接 data-dir、路径规范化、跳过自身/无关脚本、空/缺失扫描目录等。
- 标签扫描增加可选 Places，默认搜索范围不变；桌面路径获取支持尚不存在的目录并有回退，修复首轮 24/1 的失败。
- 原有删除预览测试在删除档案之后调用，改为在改名/删除之前调用；此处是修复用例顺序，没有降低断言要求。
- New-DesktopShortcut.ps1 补 UTF-8 BOM；新增可复跑静态检查与 UI mock 检查。
- D-022 与 DEBT-012 固定不做登录/邮箱/套餐/额度/重置时间；D-023 记录本轮 Windows 验证分工；更新交接、状态、索引和验收卡。

## 复跑
在项目根目录：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Core.ps1 -NoPause
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Core.ps1 -NoPause
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Static.ps1
python docs/dev/tools/check_docs.py
```

可选 UI 测试需要本机已有 Node、Playwright 与 Edge：`node tests/Test-Ui.cjs <截图目录>`。
若 Playwright 不在标准模块路径，CML_PLAYWRIGHT_MODULE 可指定其模块绝对路径。该变量只用于测试，不属于 launcher 的运行依赖。

## 验证边界
没有读取令牌、cookie 或登录数据，没有调用订阅用量接口、改注册表、启动 Claude 或实际删除用户数据。浏览器使用临时隔离上下文；测试不写真实桌面快捷方式。
词法审计不证明所有分支都能在 StrictMode 下运行，运行覆盖仅限核心自测。
真实标签映射、入口闪窗/按钮、关闭进程与 Claude 独立运行、实际回收站/大目录行为、配置和临时目录隔离及 launch.vbs 参数仍待用户验收，见 docs/dev/reviews/M1_r2.md。
