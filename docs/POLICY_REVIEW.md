# Anthropic 政策核查

核查日期：2026-11-09。对象：v17 GitHub 源码包（程序与 v16 相同，仅整理文档）。结论是技术与条款的对照判断，不是 Anthropic 授权或法律意见。

## 核查结论与限度

**在所查资料中，没有找到专门禁止这种本地 Desktop 多实例启动方式的条文，也没有找到对本项目的明确许可。** 因此，本次核查不足以认定它违规，也不足以保证其获得官方认可或在所有使用场景下合规。

源码未发现凭据中转、订阅接口调用、账号自动轮换、服务转售或修改 Claude 程序的功能。工具只负责本地目录和进程启动，用户在官方应用内自行登录和操作；不能仅因为它通过脚本启动进程，就直接等同于脚本自动访问 Claude 服务。官方对自动化访问、账号共享及绕过保护措施的限制仍须遵守。

官方帮助文档说明了多个账号间的切换，不能把“拥有多个账号”本身一概视为违规；这也不等于官方承诺支持本工具的并行方式。工具不用于绕过用量限制、封禁或其他保护措施。

## 官方依据与适用范围

| 官方资料 | 核查要点 | 对本项目的影响 |
| --- | --- | --- |
| [Consumer Terms of Service](https://www.anthropic.com/legal/consumer-terms)，页面生效日 2025-10-08，§2、§3 | 禁止共享账号/凭据；限制非 API 的自动化访问、抓取和逆向工程；禁止绕过系统或保护措施 | 本地启动进程与自动发送请求需要分别判断；本条款没有专门评价该多开方式。项目不提供请求自动化、共享或转售，也不以规避限制为用途 |
| [Log in to your Claude account](https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account)，Authenticating to subscription plans / Developers / multiple accounts | 订阅面向订阅者使用原生应用；第三方接入优先 API，禁止冒充客户端或将第三方流量挤入订阅额度。官方说明个人/组织账号切换、不同邮箱需退出再登录 | 本项目仅调用用户已安装的原生程序，没有自己的 Claude 登录、请求代理或凭据管理；官方账号切换说明不能推导出并行独立目录获准 |
| [Anthropic Trademark Guidelines](https://www.anthropic.com/legal/trademark-guidelines)，生效日 2024-08-01 | 商标使用须获得具体许可及材料批准，不得暗示官方关联；不能擅改商标 | 项目保留现名用于标识兼容对象；快捷方式复用本机图标，仓库不分发或将其用作项目 Logo。未掌握具体授权证明，也不据此断言构成侵权；免责声明和 MIT 不是品牌许可 |
| [Claude Code legal and compliance](https://code.claude.com/docs/en/legal-and-compliance)，Authentication and credential use / name and logo | 限制第三方提供 Claude.ai 登录、收集/保存/中转会话凭据及代用户路由订阅请求；品牌使用有限制 | 这是 Claude Code 的具体说明，不能当作所有 Desktop 启动器的一概禁令或授权；项目继续不接触凭据，也不实现 OAuth usage 查询 |
| [Usage Policy 官方归档](https://www.anthropic.com/legal/archive/22742366-2ef0-4c7a-a833-6523f10d3944)，生效日 2025-09-15；[新版](https://www.anthropic.com/legal/aup) 标注 2026-11-12 | 当前新版生效日在核查日之后；旧归档可访问，但本次网页提取未展开 Universal Usage Standards 的全部细项 | 不把 11 月 12 日新版当作 11 月 9 日已生效条款；新版明确涉及规避封禁、多账号规避防护及未授权代理等，作为发布后应复核的边界，不冒充已完整核实旧版细项 |

## 源码事实与推断

- `Start-CmlProfile` 解析已安装的 Claude 路径，通过系统进程启动传入 `--user-data-dir`，短暂设置本进程环境变量后恢复。没有补丁、反编译或重新打包 Claude 的实现。Chromium 参数通用，不等于 Anthropic 官方支持它用于 Desktop 多开。
- `claude-multi-server.ps1` 仅在 `127.0.0.1` 随机端口提供 UI，校验 Host 和本地随机访问令牌。该令牌是启动器自己生成的，与 Claude 登录无关。未发现远程 Anthropic 请求或代理代码。
- 快捷方式扫描读取 `.lnk` 参数和启动脚本文本来识别目录；不解析 Cookie、会话或账号凭据。目录检查会枚举文件名/计算大小，不读取登录文件内容；本次测试只使用隔离沙箱。
- `Get-CmlIconPath` 从本机已安装应用提取关联图标并缓存；源码包不包含图标、Claude 二进制、快捷方式或用户 profile。本机快捷方式引用与公开分发图标是不同使用情境；本次未对其商标法适用作法律结论，也不将本机提取当作品牌许可。
- UI 不显示账号邮箱、套餐、额度或重置时间；没有自动挑账号、耗尽后切换、批量注册或付费代理功能。对本工具的核查不能证明用户实际使用方式、账号归属或组织授权符合条款。

## GitHub 发布安排

按用户 2026-11-09 的明确选择，保留 `claude-multi-launcher` / `Claude Multi Launcher` 名称和本机 Claude Desktop 快捷方式图标行为。README 首屏以中英文明确非官方，并说明不得用于规避限制、封禁、共享或转售。

发布内容为启动器源码、MIT、测试和已知限制，不包含凭据、用户配置、Claude 二进制或官方图标。Claude 名称用于说明兼容对象，官方图标不作为仓库 Logo 或发布素材；MIT 仅适用于本项目代码，不授予 Anthropic 商标或软件权利。

不把获得书面许可或改名换图标设为本次整理源码包的前置条件，也不声称未获许可就必然违规。若后续收到 Anthropic 的具体要求，依据当时有效条款调整。源码包尚未上传 GitHub。

README 已移除“各账号额度必然独立”和“记忆/临时目录已完全隔离”等未经验证的承诺。运行行为仍须按 `docs/dev/CURRENT_STATE.md` 的 Windows 清单验收，后续发布应重新核查当日生效条款。
