<!-- 用途：AI 工具（Claude Code、Codex、Cursor 等）打开项目时最先读的文件。保持简短，只做指路。
     Claude Code 读的是 CLAUDE.md，初始化时已生成一份，内容就是一行 @AGENTS.md。 -->
# 给 AI 的开工说明

1. 先读 `docs/dev/README.md`，按「AI 开工顺序」来。只读那几个文件，不要通读整个 docs。
2. 设计意图：`docs/design/DESIGN.md`。代码实际状态：`docs/dev/CURRENT_STATE.md`。必须遵守的规则和人的偏好：`docs/dev/contracts/`。
3. 一次只做一个里程碑。最多标到「待验收」，**不能自己标「完成」**：只有人在验收卡上签字、结论为「通过」才算完成。
4. 交给人之前，机器能查的先自己查（能运行、无报错、截图、冒烟测试）。人的时间只用来判断手感、观感和取舍。
5. 交付验收时生成验收卡：`python docs/dev/tools/new_review.py Mx`，填好 AI 部分，再 `python docs/dev/tools/build_panel.py <验收卡>` 生成点选面板给人。
6. 收到人的反馈：一轮反馈合并成一批改，不要边读边改。主观意见先用两三行复述理解，再动手。
7. 同一问题连续两轮没过：停下来换方案，写进 `DECISIONS.md`，不要继续微调。
8. 文档来不及更新，就在 `docs/dev/DEVELOP_DEBT.md` 记一笔，写清「怎样才算还清」。
9. 收尾前运行 `python docs/dev/tools/check_docs.py`，有 ERROR 就先处理。
10. 小改动（≤3 个文件、没有设计取舍）不用建里程碑和验收卡：直接改、验证、提交。一次只做一个任务：做完建议 `/clear`，状态靠文件衔接（`check_docs.py --progress` 看进度）。
