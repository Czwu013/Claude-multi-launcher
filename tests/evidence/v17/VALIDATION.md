# v17 发布整理验证

日期：2026-11-09。

- 本轮仅修改文档，程序、UI、测试脚本逐文件与 v16 比较，全部字节一致；SHA-256 清单见同目录 runtime-sha256.json。
- 本轮实际运行 Test-Static.ps1：10 个 PowerShell 文件 UTF-8 BOM / AST 检查通过，中英 165 键与占位符一致，保守词法变量审计通过。
- 本轮实际运行 check_docs.py：0 ERROR / 0 WARN。偏好模板占位符仅 INFO。
- 核心各 78/78、特性各 19/19（PowerShell 7 / Windows PowerShell 5.1），以及 Playwright 4 组截图用例和 2 组交互套件，为 v16 已运行证据；本轮未重复运行。详见 ../v16/VALIDATION.md。
- 打包检查：ZIP CRC、逐文件字节、BOM、必备文件、源码包无凭据/用户配置或官方图标/应用二进制；未包含真实本机用户名路径。
- 保留名称、原图标、菜单删除和圆点排序；没有启动 Claude、读取登录数据、调用订阅接口或修改注册表。
- M1 / M3 保持待验收。真实隔离、窗口生命周期、回收站等待验项见 ../../../../docs/dev/CURRENT_STATE.md。源码包尚未上传 GitHub。
