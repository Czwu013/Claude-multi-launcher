<!-- 用途：开发记录的总入口。AI 每次开工先读这里。
     维护规则：改任何 docs/dev 下的文档，都要同步更新下表的「最后更新」和「状态」。
     docs/dev/tools/check_docs.py 会检查这里的链接、状态值和过期情况。 -->
# 开发记录总入口

> 设计意图只在设计文档：`../design/DESIGN.md`。本文件夹只记**代码实际是什么样**，以及过程中的决定、欠账和验收。

## 文档索引

状态：**最新** = 与代码一致 · **待更新** = 已知过期，已在欠账里记一笔 · **归档** = 已移入 `archive/`

| 文档 | 用途 | 最后更新 | 状态 |
| --- | --- | --- | --- |
| [CURRENT_STATE.md](CURRENT_STATE.md) | 代码现在实际做到什么（≤100 行） | 2026-11-09 · v20 · M1/M3 待验收 | 最新 |
| [HANDOFF.md](HANDOFF.md) | v13 历史交接依据，当前状态看 CURRENT_STATE | 2026-11-09 | 归档 |
| [../POLICY_REVIEW.en.md](../POLICY_REVIEW.en.md) | 英文政策说明，链接中文详细核查 | 2026-11-09 | 最新 |
| [../POLICY_REVIEW.md](../POLICY_REVIEW.md) | 官方政策事实、适用边界及未确认事项 | 2026-11-09 | 最新 |
| [DECISIONS.md](DECISIONS.md) | 重大决定与理由 | 2026-11-09 | 最新 |
| [DEVELOP_DEBT.md](DEVELOP_DEBT.md) | 欠账与还清标准 | 2026-11-09 | 最新 |
| [known_mismatches.md](known_mismatches.md) | 代码与设计的已知偏差 | 2026-11-08 | 最新 |
| [feedback_log.md](feedback_log.md) | 人的反馈条目与处理状态 | 2026-11-09 | 最新 |
| [contracts/](contracts/) | 必须遵守的规则 + 人的品味档案 | 2026-11-08 | 最新 |
| [archive/M3_gui_v14.md](archive/M3_gui_v14.md) | 旧 UI 阶段计划，原结果保留 | 2026-11-09 | 归档 |
| [plans/README.md](plans/README.md) | 里程碑状态与下一步 | 2026-11-09 | 最新 |
| [reviews/](reviews/) | 验收卡：AI 的交付说明 + 人的打分与结论 | 2026-11-09 | 最新 |

**需要时再建：** `audits/` `ledgers/` `references/` `roadmaps/` `bench/` `../research/` `../release_notes/`（初始化时加 `--full` 会带上模板）。

## 里程碑状态流转

```
待做 → 进行中 → 待验收 → 完成
          ↑         │
          └─────────┘  结论「返工」：退回
                       结论「小改后过」：AI 合并改一批，下一轮人只复验改过的几条
```

- **待验收**：AI 写完并自测（运行 / 截图 / 无报错），生成验收卡，把“已验证什么、请人重点判断什么”写清。
- **完成**：只有验收卡里 `结论：通过`，且有验收人和日期，才能标。**AI 不能自己标「完成」。**

## AI 开工顺序（只读这些）

1. 本文件 → `CURRENT_STATE.md` → `plans/README.md` → `contracts/`（含 `taste.md`）
2. 有未关闭的验收卡 / 反馈：先读最新一张验收卡和 `feedback_log.md` 里「待处理」的条目
3. 只做下一个里程碑；完成后更新 `CURRENT_STATE.md`、`plans/`、验收卡、`DECISIONS.md`（如有）、本表
4. 来不及更新的文档：在 `DEVELOP_DEBT.md` 记一笔，本表状态改为「待更新」
5. 收尾运行 `python docs/dev/tools/check_docs.py`

**默认不读：** `archive/` `research/` `references/` `audits/` 和历史验收卡。需要时再翻，省上下文。

## 文档变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-11-09 | v20：中英文 README 加入用户双窗口截图，原图和既有 GIF 均保留 |
| 2026-11-09 | v19：英文 README 首页、英文 UI/字幕 GIF 和英文政策摘要；中文材料保留并互链 |
| 2026-11-09 | v18：README 加入创建/启动两个 profile 的 mock 动图，标注模拟边界并保留实机待验项 |
| 2026-11-09 | v17：用户确认保留现名与原图标；非官方和禁止规避用途声明；政策说明客观化，准备 GitHub 源码包 |
| 2026-11-09 | v15 用户反馈：本机原图标、行内删除、圆点排序与持久化；M3 待验收；不加 usage/重置时间 |
| 2026-11-09 | v14 收尾：核心 78 条自测、静态与 mock 截图验证、D-022 范围边界及待验收证据 |
| 2026-11-08 | 建立 docs/dev 文档体系 |
