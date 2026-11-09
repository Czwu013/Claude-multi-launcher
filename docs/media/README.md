# Demo animations / 操作动图

- `clone-demo-en.gif`: English UI and captions, embedded in README.md.
- `clone-demo.gif`: Chinese UI and captions, embedded in README.zh-CN.md.
- Both demonstrate the real launcher HTML with mocked responses and sample data. No real Claude process or login is recorded. Each animation is approximately 29 seconds, 1040×790, and loops.


`clone-demo.gif`：约 29 秒，1040×790，循环播放。

录制方式：Playwright + Edge 操作 `ui/index.html`，使用示例名称和全 mock 接口响应。创建 Personal、Work，分别发出启动请求并显示真实 UI 的首次启动提示；末尾用说明卡解释同一程序与不同数据目录。鼠标高亮和字幕为后期添加。

没有打开真实 Claude、创建真实 profile/快捷方式、读取登录数据或录制官方登录。“已启动过”只是启动请求状态，不表示登录成功；实际登录应逐个在官方应用内完成。此动图用于说明操作流程，不作为真实 Claude 多开、隔离或生命周期验收证据。

## User-provided screenshot

`two-claude-windows.png` is the unmodified image supplied by the user on November 9, 2026. It shows two Claude Desktop windows side by side and is embedded in both language versions of the README. It is a screenshot, not a project logo or a new automated test of account isolation.

## Test email sign-in illustrations

`login-test-en.gif` and `login-test-zh.gif` follow the user-provided sign-in sequence: browser-only sign-out, request login from Test, open the email link, cancel “Open Claude?”, choose “Log in with code”, and enter the code back in Test. Each contains 9 scenes, approximately 40 seconds, with cursor highlights. In v22 the generic cards were replaced with separate, re-created Claude desktop, Gmail inbox/message and browser-prompt layouts. Both GIFs are 1280×900, 44 encoded frames and 39.02 seconds. They are illustrative reconstructions, not recordings of an actual sign-in or verified copies of current authentication screens. The final scene includes the previously supplied two-window screenshot as an example, not the result of this tutorial. `test@example.com` and `DEMO-CODE` are placeholders. The offline renderer made no network requests and accessed no mailbox, account, credential or login data. A separate anonymous public-page reference attempt encountered a verification interstitial; it was not bypassed or used as tutorial artwork.

The user's browser-only sign-out behavior is not independently verified here. Official help distinguishes an all-session operation that signs out desktop apps; the README links that source and warns against confusing the two. The original create-profile GIFs and user-provided screenshot remain unchanged.

## Original launcher mark (v24)

The project mark is `../../assets/launcher.png` with Windows sizes in `../../assets/launcher.ico`: two original gray rounded windows and a launch arrow, generated for this project. It is not Claude's official logo. The README and native launcher use it; profile links continue to use the locally extracted official app icon. The generation prompt is recorded in `../../assets/DESIGN.md`.
