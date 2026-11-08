#!/usr/bin/env python3
"""检查 docs/dev 是否符合 vibecodingflow 的规则，并统计返工与分派情况。

用法：
    python check_docs.py [项目根目录] [--strict] [--stats] [--brief] [--progress]
    python check_docs.py --suggest docs/dev/reviews/M1_r1.md

有 ERROR 时退出码为 1。--strict 把 WARN 也当作错误，并要求不能残留 {{ 占位符。
--brief 输出 ≤15 行的状态摘要（给新会话开工用，也被 SessionStart hook 使用）。
--progress 按里程碑显示任务进度条（任务表「结果」列非空即算该任务完成），不调用模型。

主要检查：
  - 标「完成」的里程碑，必须有人签字、结论为「通过」的最新验收卡（AI 不能自己宣布完成）
  - 验收卡结论必须与打分一致，不一致要写覆盖原因
  - 里程碑进入待验收 / 完成时，DESIGN 第 6 节「验收基准」必须已填（人没有尺子就没法打分）
  - 计划任务表：路由给子代理的任务必须有文件范围和机器验证；文件范围重叠的并行任务会警告
  - 欠账每条都有"怎样才算还清"
  - 索引里的链接存在、状态值合法、文件改过但索引日期没更新
  - 连续两轮返工 → 提示"熔断，换方案"
  - 一致性：进行中的里程碑要有计划文件；待验收 / 完成时不能还留着未完成的任务；主会话任务也要写验证方式
  - AGENTS.md / CURRENT_STATE.md 不能长（每次开工都读，越长越费 token）
"""
import argparse
import os
import re
import statistics
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dk_common as dk  # noqa: E402

STATUS_OK = ("最新", "待更新", "归档")
MS_STATUS = ("待做", "进行中", "待验收", "完成")
FB_STATUS_PREFIX = ("待处理", "已修改", "已关闭", "不改")
ROUTES = ("主", "sonnet", "haiku", "opus")
DELEGATED = ("sonnet", "haiku", "opus")
RESULT_RE = re.compile(r"^(一次通过|升级|返修\d+次)?$")


class Report:
    def __init__(self):
        self.items = []

    def add(self, level, msg):
        self.items.append((level, msg))

    def count(self, level):
        return sum(1 for lv, _ in self.items if lv == level)

    def messages(self, level):
        return [m for lv, m in self.items if lv == level]


def git_date(root, path):
    try:
        r = subprocess.run(
            ["git", "-C", str(root), "log", "-1", "--format=%cs", "--", str(path)],
            capture_output=True, text=True, timeout=10,
        )
        return (r.stdout.strip() or None) if r.returncode == 0 else None
    except Exception:
        return None


def clean(s):
    return s.replace("*", "").strip()


# ---------- 读取 ----------

def milestone_status(root):
    p = root / "docs/dev/plans/README.md"
    if not p.exists():
        return {}
    t = dk.find_table(dk.read(p), "里程碑", "状态")
    if not t:
        return {}
    header, rows = t
    i_ms, i_st = dk.col(header, "里程碑"), dk.col(header, "状态")
    out = {}
    for r in rows:
        m = re.match(r"(M\d+)", clean(dk.cell(r, i_ms)))
        if m:
            out[m.group(1)] = dk.canon(clean(dk.cell(r, i_st)))
    return out


def load_reviews(root):
    parsed = {}
    for ms, lst in dk.review_files(root / "docs/dev/reviews").items():
        parsed[ms] = []
        for n, path in lst:
            text = dk.read(path)
            parsed[ms].append((n, path, text, dk.parse_review(text)))
    return parsed


def signed(p):
    return bool(p["signer"]) and bool(dk.DATE_RE.fullmatch(p["date"] or ""))


def norm_route(s):
    s = clean(s).lower()
    if s in ("主", "主会话", "main", "main session"):
        return "主"
    return s


def load_tasks(root):
    """读 plans/Mx_*.md 里带「任务」「路由」列的任务表。占位符行跳过。"""
    out = []
    for p in sorted((root / "docs/dev/plans").glob("M*_*.md")):
        ms = re.match(r"(M\d+)", p.name)
        if not ms:
            continue
        for header, rows in dk.tables(dk.read(p)):
            i_task, i_route = dk.col(header, "任务"), dk.col(header, "路由")
            if i_task is None or i_route is None:
                continue
            i_scope, i_check, i_res = dk.col(header, "文件范围"), dk.col(header, "机器验证"), dk.col(header, "结果")
            for r in rows:
                if dk.PLACEHOLDER in " ".join(r):
                    continue
                out.append({
                    "ms": ms.group(1), "file": p.name, "id": dk.cell(r, 0),
                    "task": dk.cell(r, i_task), "scope": dk.cell(r, i_scope),
                    "check": dk.cell(r, i_check), "route": norm_route(dk.cell(r, i_route)),
                    "result": dk.canon(clean(dk.cell(r, i_res))),
                })
    return out


# ---------- 各项检查 ----------

def check_index(root, R):
    p = root / "docs/dev/README.md"
    if not p.exists():
        R.add("ERROR", dk.L("缺少 docs/dev/README.md（总入口）", "Missing docs/dev/README.md (the index)"))
        return
    text = dk.read(p)
    t = dk.find_table(text, "文档", "最后更新")
    if not t:
        R.add("WARN", dk.L("docs/dev/README.md 里找不到文档索引表", "No document index table found in docs/dev/README.md"))
        return
    header, rows = t
    i_doc, i_upd, i_st = dk.col(header, "文档"), dk.col(header, "最后更新"), dk.col(header, "状态")
    for r in rows:
        doc, upd, st = dk.cell(r, i_doc), dk.cell(r, i_upd), dk.canon(clean(dk.cell(r, i_st)))
        link = re.search(r"\]\(([^)]+)\)", doc)
        target = (p.parent / link.group(1)) if link else None
        if target is not None and not target.exists():
            R.add("ERROR", dk.L(f"索引里的链接不存在：{link.group(1)}", f"Broken link in the index: {link.group(1)}"))
        if st and st not in STATUS_OK:
            R.add("WARN", dk.L(f"索引状态「{st}」不是 {'/'.join(STATUS_OK)} 之一（{doc}）",
                               f"Index status \"{st}\" is not one of {'/'.join(dk.tv(s) for s in STATUS_OK)} ({doc})"))
        d = dk.DATE_RE.search(upd)
        if d and target is not None and target.exists() and st != "归档":
            gd = git_date(root, target)
            if gd and gd > d.group(0):
                R.add("WARN", dk.L(f"{link.group(1)} 在 {gd} 提交过，索引「最后更新」还是 {d.group(0)}",
                                   f"{link.group(1)} was committed on {gd}, but the index \"Last updated\" still says {d.group(0)}"))
    for f in sorted((root / "docs/dev").glob("*.md")):
        if f.name != "README.md" and f.name not in text:
            R.add("WARN", dk.L(f"docs/dev/{f.name} 没有登记到索引", f"docs/dev/{f.name} is not listed in the index"))


def check_design_gate(root, R, ms_status):
    """验收基准没填，人就没有尺子。待验收 / 完成时报错，进行中时提醒。"""
    p = root / "docs/design/DESIGN.md"
    if not p.exists() or not ms_status:
        return
    text = dk.read(p)
    if len(text.splitlines()) <= 6 and "http" in text:
        return  # 设计文档放在线上，只留了一行链接
    sec = dk.strip_comments(dk.section(text, "6."))
    if dk.PLACEHOLDER not in sec:
        return
    states = set(ms_status.values())
    msg = dk.L("DESIGN 第 6 节「验收基准」还有未填的占位符：没有统一的尺子，人的打分没有意义，AI 也不知道目标。"
               "可以用 init.py --genre 带入类型预设，再按口味校准",
               "DESIGN §6 \"Acceptance baseline\" still has unfilled placeholders: without a shared yardstick, human scores "
               "mean little and the AI doesn't know the target. Use init.py --genre to bring in a genre preset, then calibrate it")
    if states & {"待验收", "完成"}:
        R.add("ERROR", msg)
    elif "进行中" in states:
        R.add("WARN", msg)


def check_milestones(root, R, ms_status, reviews):
    for ms, status in ms_status.items():
        if status not in MS_STATUS:
            R.add("WARN", dk.L(f"{ms} 的状态「{status}」不是 {'/'.join(MS_STATUS)} 之一",
                               f"{ms} status \"{status}\" is not one of {'/'.join(dk.tv(s) for s in MS_STATUS)}"))
            continue
        rv = reviews.get(ms, [])
        latest = rv[-1] if rv else None
        if status == "完成":
            if not latest:
                R.add("ERROR", dk.L(f"{ms} 标了「完成」，但 reviews/ 里没有验收卡。完成只能由人验收后确认",
                                    f"{ms} is marked \"Done\" but reviews/ has no review card. Only a human review can confirm Done"))
                continue
            p = latest[3]
            problems = []
            if p["conclusion"] != "通过":
                problems.append(dk.L(f"最新验收卡（第 {latest[0]} 轮）结论是「{p['conclusion'] or '空'}」，不是「通过」",
                                     f"the latest review card (round {latest[0]}) has verdict \"{dk.tv(p['conclusion']) or 'empty'}\", not \"Pass\""))
            if not p["signer"]:
                problems.append(dk.L("缺验收人", "no reviewer"))
            if not dk.DATE_RE.fullmatch(p["date"] or ""):
                problems.append(dk.L("缺日期（格式 YYYY-MM-DD）", "no date (format YYYY-MM-DD)"))
            if problems:
                R.add("ERROR", dk.L(f"{ms} 标了「完成」但没有通过人的验收：", f"{ms} is marked \"Done\" but has not passed human review: ")
                      + dk.L("；", "; ").join(problems))
        elif status == "待验收":
            if not latest:
                R.add("ERROR", dk.L(f"{ms} 标了「待验收」，但没有验收卡。先运行 new_review.py {ms}",
                                    f"{ms} is marked \"In review\" but has no review card. Run new_review.py {ms} first"))
            elif dk.PLACEHOLDER in dk.section(latest[2], "AI 部分"):
                R.add("WARN", dk.L(f"{ms} 验收卡 {latest[1].name} 的「AI 部分」还有未填的占位符",
                                   f"{ms} review card {latest[1].name}: the \"AI part\" still has unfilled placeholders"))
            else:
                c = latest[3]["conclusion"]
                if c in ("返工", "小改后过"):
                    R.add("WARN", dk.L(f"{ms} 最新验收卡结论是「{c}」，状态应退回「进行中」，改完再生成下一轮验收卡",
                                       f"{ms} latest review verdict is \"{dk.tv(c)}\": set the status back to \"In progress\", fix, then create the next round's card"))
                elif c == "通过" and signed(latest[3]):
                    R.add("WARN", dk.L(f"{ms} 验收卡已签字通过，状态还是「待验收」，可以更新为「完成」",
                                       f"{ms} review card is signed Pass but the status is still \"In review\": you can update it to \"Done\""))
        elif status in ("待做", "进行中") and latest:
            p = latest[3]
            if p["conclusion"] == "通过" and signed(p):
                R.add("WARN", dk.L(f"{ms} 的验收卡已签字通过，状态还是「{status}」，可以更新为「完成」",
                                   f"{ms} review card is signed Pass but the status is still \"{dk.tv(status)}\": you can update it to \"Done\""))
    for ms in reviews:
        if ms_status and ms not in ms_status:
            R.add("WARN", dk.L(f"reviews/ 里有 {ms} 的验收卡，但 plans/README.md 里没有这个里程碑",
                               f"reviews/ has a card for {ms}, but plans/README.md has no such milestone"))


def check_reviews(R, reviews):
    for ms, lst in reviews.items():
        for n, path, _text, p in lst:
            name = path.name
            if not p["conclusion"]:
                continue
            if p["conclusion"] not in dk.VERDICTS:
                R.add("ERROR", dk.L(f"{name}：结论「{p['conclusion']}」不是 {'/'.join(dk.VERDICTS)} 之一",
                                    f"{name}: verdict \"{p['conclusion']}\" is not one of {'/'.join(dk.tv(v) for v in dk.VERDICTS)}"))
                continue
            if not p["scores"]:
                R.add("ERROR", dk.L(f"{name}：有结论但没有打分", f"{name}: has a verdict but no scores"))
                continue
            sug, why = dk.suggest_verdict(p["scores"], p["issues"])
            if p["conclusion"] != sug and not p["override"]:
                R.add("ERROR", dk.L(f"{name}：结论「{p['conclusion']}」与按分数得出的「{sug}」（{'；'.join(why)}）不一致，且没写覆盖原因",
                                    f"{name}: verdict \"{dk.tv(p['conclusion'])}\" differs from the score-based \"{dk.tv(sug)}\" ({'; '.join(why)}) and no override reason is given"))
            if p["suggested_in_card"] and p["suggested_in_card"] != sug:
                R.add("WARN", dk.L(f"{name}：卡里写的 AI 建议结论「{p['suggested_in_card']}」与分数得出的「{sug}」不符",
                                   f"{name}: the AI suggested verdict on the card (\"{dk.tv(p['suggested_in_card'])}\") does not match the score-based \"{dk.tv(sug)}\""))
            for d, sc in p["scores"].items():
                if (sc <= 2 or sc == 5) and not p["reasons"].get(d):
                    R.add("WARN", dk.L(f"{name}：「{d}」打了 {sc} 分，没写理由", f"{name}: \"{d}\" scored {sc} with no reason given"))
    for ms, lst in reviews.items():
        concl = [p["conclusion"] for _, _, _, p in lst if p["conclusion"]]
        if len(concl) >= 2 and concl[-1] == "返工" and concl[-2] == "返工":
            R.add("WARN", dk.L(f"{ms} 连续 2 轮返工：停止微调，换方案并写进 DECISIONS.md，必要时向人要参考对象（可交 dk-reviewer 做根因分析）",
                               f"{ms} reworked 2 rounds in a row (circuit breaker): stop tweaking, change approach and log it in DECISIONS.md; ask the human for a reference if needed (dk-reviewer can do a root-cause analysis)"))
        elif len(concl) >= 4 and concl[-1] != "通过":
            R.add("WARN", dk.L(f"{ms} 已经 {len(concl)} 轮仍未通过：里程碑可能太大，考虑拆分",
                               f"{ms} has had {len(concl)} rounds without passing: the milestone may be too big, consider splitting it"))


def _scope_tokens(scope):
    return [t.lstrip("./") for t in re.split(r"[,，、;；\s]+", scope) if t.strip()]


def _overlap(a, b):
    return a == b or a.startswith(b.rstrip("/") + "/") or b.startswith(a.rstrip("/") + "/")


def check_plans(root, R):
    tasks = load_tasks(root)
    for t in tasks:
        label = f"{t['file']} {t['id'] or '某任务'}"
        if t["route"] not in ROUTES:
            R.add("WARN", dk.L(f"{label}：路由「{t['route']}」应为 {' / '.join(ROUTES)} 之一",
                               f"{label}: route \"{t['route']}\" should be one of {' / '.join(dk.tv(r) for r in ROUTES)}"))
            continue
        if t["route"] in DELEGATED:
            missing = [n for n, v in ((dk.L("文件范围", "File scope"), t["scope"]), (dk.L("机器验证", "Machine check"), t["check"])) if not v]
            if missing:
                R.add("ERROR", dk.L(f"{label}：路由给 {t['route']} 但缺{'、'.join(missing)}，不可委派（没有边界和验证标准，无法判断它做对没有）",
                                    f"{label}: routed to {t['route']} but missing {', '.join(missing)} — not delegable (no boundary or verification standard to judge whether it was done right)"))
        if not RESULT_RE.match(t["result"]):
            R.add("WARN", dk.L(f"{label}：结果「{t['result']}」应为 一次通过 / 返修N次 / 升级 或留空",
                               f"{label}: result \"{t['result']}\" should be First pass / Retry Nx / Escalated, or empty"))
    by_ms = {}
    for t in tasks:
        if t["route"] in DELEGATED and not t["result"] and t["scope"]:
            by_ms.setdefault(t["ms"], []).append(t)
    for ms, lst in by_ms.items():
        for i in range(len(lst)):
            for j in range(i + 1, len(lst)):
                a, b = _scope_tokens(lst[i]["scope"]), _scope_tokens(lst[j]["scope"])
                if any(_overlap(x, y) for x in a for y in b):
                    R.add("WARN", dk.L(f"{ms} 的 {lst[i]['id']} 与 {lst[j]['id']} 文件范围重叠：不要并行，改成串行或拆开范围",
                                       f"{ms}: {lst[i]['id']} and {lst[j]['id']} have overlapping file scopes — don't run them in parallel; serialize or split the scopes"))


def check_consistency(root, R, ms_status):
    """计划与状态是否对得上。机器能查的部分；语义上的缺漏（MVP 条目有没有对应任务）由 AI 按 SKILL.md 的一致性检查步骤做。"""
    tasks = load_tasks(root)
    plans = root / "docs/dev/plans"
    for ms, status in ms_status.items():
        if status == "进行中" and ms != "M0" and not list(plans.glob(f"{ms}_*.md")):
            R.add("WARN", dk.L(f"{ms} 已是「进行中」，但 plans/ 里没有 {ms}_*.md 计划文件：先写任务表（每个任务写明验证方式）再动手",
                               f"{ms} is \"In progress\" but plans/ has no {ms}_*.md plan file: write the task table (with a check for every task) before building"))
        if status in ("待验收", "完成"):
            pending = [t for t in tasks if t["ms"] == ms and not t["result"]]
            if pending:
                ids = ", ".join(t["id"] or "?" for t in pending[:5])
                R.add("WARN", dk.L(f"{ms} 状态是「{status}」，但任务表里还有 {len(pending)} 个任务没有结果（{ids}）：做完并填结果，或移出本里程碑",
                                   f"{ms} is \"{dk.tv(status)}\" but {len(pending)} task(s) in the table have no result ({ids}): finish them and fill the result, or move them out"))
    for t in tasks:
        if t["route"] == "主" and not t["result"] and not t["check"]:
            R.add("WARN", dk.L(f"{t['file']} {t['id'] or '某任务'}：没写验证方式，没法判断它做对没有",
                               f"{t['file']} {t['id'] or 'a task'}: no check written, so there is no way to tell it was done right"))


def check_debt(root, R):
    p = root / "docs/dev/DEVELOP_DEBT.md"
    if not p.exists():
        return
    text = re.split(r"(?m)^##\s*(?:已还清|Paid off)", dk.read(p))[0]
    t = dk.find_table(text, "编号", "还清")
    if not t:
        return
    header, rows = t
    i_id, i_pay = dk.col(header, "编号"), dk.col(header, "还清")
    for r in rows:
        if dk.PLACEHOLDER in " ".join(r):
            continue
        if not dk.cell(r, i_pay):
            R.add("ERROR", dk.L(f"{dk.cell(r, i_id) or '某条欠账'} 没写「怎样才算还清」",
                                f"{dk.cell(r, i_id) or 'A debt entry'} has no \"Payoff criteria\""))


def check_feedback(root, R):
    p = root / "docs/dev/feedback_log.md"
    if not p.exists():
        return
    t = dk.find_table(dk.read(p), "编号", "状态")
    if not t:
        return
    header, rows = t
    i_id, i_sev, i_st = dk.col(header, "编号"), dk.col(header, "严重"), dk.col(header, "状态")
    open_high = 0
    for r in rows:
        if dk.PLACEHOLDER in " ".join(r):
            continue
        sev, st = dk.canon(dk.cell(r, i_sev)), dk.canon(dk.cell(r, i_st))
        if sev and sev not in dk.SEVERITIES:
            R.add("WARN", dk.L(f"{dk.cell(r, i_id)} 严重度「{sev}」应为 高/中/低", f"{dk.cell(r, i_id)} severity \"{sev}\" should be High/Medium/Low"))
        if st and not st.startswith(FB_STATUS_PREFIX):
            R.add("WARN", dk.L(f"{dk.cell(r, i_id)} 状态「{st}」应为 待处理 / 已修改，待复验 / 已关闭 / 不改",
                               f"{dk.cell(r, i_id)} status \"{st}\" should be Open / Fixed, awaiting re-check / Closed / Won't fix"))
        if sev == "高" and not st.startswith(("已关闭", "不改")):
            open_high += 1
    if open_high:
        R.add("INFO", dk.L(f"有 {open_high} 条高严重度反馈未关闭", f"{open_high} high-severity feedback item(s) still open"))


def check_lean(root, R):
    for rel, limit in (("AGENTS.md", 40), ("docs/dev/CURRENT_STATE.md", 100)):
        p = root / rel
        if p.exists():
            n = len(dk.read(p).splitlines())
            if n > limit:
                R.add("WARN", dk.L(f"{rel} 有 {n} 行，超过 {limit} 行。每次开工都要读，越短越省 token",
                                   f"{rel} has {n} lines, over the {limit}-line limit. It is read at every start-up; shorter saves tokens"))


def check_placeholders(root, R, strict):
    files = [root / "README.md", root / "AGENTS.md"] + list((root / "docs").rglob("*.md"))
    found = []
    for f in files:
        if not f.exists() or f.name.startswith("_TEMPLATE") or "tools" in f.parts:
            continue
        n = dk.read(f).count(dk.PLACEHOLDER)
        if n:
            found.append((f.relative_to(root), n))
    if found:
        found.sort(key=lambda x: -x[1])
        shown = dk.L("、", ", ").join(f"{p}({n})" for p, n in found[:8])
        more = dk.L(f" 等 {len(found)} 个文件", f" and {len(found) - 8} more file(s)") if len(found) > 8 else ""
        R.add("ERROR" if strict else "INFO", dk.L(f"还有 {{{{ 占位符未替换：{shown}{more}", f"Unreplaced {{{{ placeholders remain: {shown}{more}"))


def run_checks(root, strict=False):
    """跑全部检查。返回 (Report, 里程碑状态, 验收卡)。供命令行和 hook 共用。"""
    R = Report()
    if os.environ.get("DK_LANG") or (root / "docs/dev/.lang").exists():
        dk.detect_lang(root)
    ms_status = milestone_status(root)
    reviews = load_reviews(root)
    check_index(root, R)
    check_design_gate(root, R, ms_status)
    check_milestones(root, R, ms_status, reviews)
    check_reviews(R, reviews)
    check_plans(root, R)
    check_consistency(root, R, ms_status)
    check_debt(root, R)
    check_feedback(root, R)
    check_lean(root, R)
    check_placeholders(root, R, strict)
    return R, ms_status, reviews


# ---------- 摘要 ----------

def _rows(path, *keys):
    if not path.exists():
        return None, []
    t = dk.find_table(dk.read(path), *keys)
    if not t:
        return None, []
    header, rows = t
    return header, [r for r in rows if dk.PLACEHOLDER not in " ".join(r)]


def progress_rows(tasks):
    """按里程碑统计任务进度：任务表「结果」列非空即算完成。返回 [(里程碑, 已完成, 总数)]，按编号排序。"""
    by = {}
    for t in tasks:
        d = by.setdefault(t["ms"], [0, 0])
        d[1] += 1
        d[0] += 1 if t["result"] else 0
    return sorted(((m, d, n) for m, (d, n) in by.items()), key=lambda r: int(r[0][1:]))


def bar(done, total, width=10):
    n = round(done * width / total) if total else 0
    return "#" * n + "-" * (width - n)


def print_progress(root):
    dk.detect_lang(root)
    ms_status = milestone_status(root)
    rows = {m: (d, n) for m, d, n in progress_rows(load_tasks(root))}
    if not ms_status and not rows:
        print(dk.L("还没有里程碑，没有可显示的进度。", "No milestones yet, nothing to show."))
        return
    total_d = total_n = 0
    for m in sorted(set(ms_status) | set(rows), key=lambda x: int(x[1:])):
        st = dk.tv(ms_status.get(m, "")) or "-"
        if m in rows:
            d, n = rows[m]
            total_d, total_n = total_d + d, total_n + n
            print(f"{m:<5} {st:<12} [{bar(d, n, 20)}] {d}/{n}")
        else:
            print(f"{m:<5} {st:<12} " + dk.L("（任务表里还没有任务）", "(no tasks in the table yet)"))
    if total_n:
        print(f"{dk.L('合计', 'Total'):<18} [{bar(total_d, total_n, 20)}] {total_d}/{total_n}")


def brief(root):
    """≤15 行的状态摘要：新会话开工时一眼看清现状，替代读一堆文件。"""
    dk.detect_lang(root)
    R, ms_status, reviews = run_checks(root)
    lines = [dk.L("[vibecodingflow 状态]", "[vibecodingflow status]")]
    if ms_status:
        lines.append(dk.L("里程碑：", "Milestones: ") + " · ".join(f"{k} {dk.tv(v)}" for k, v in ms_status.items()))
        prog = [(m, d, n) for m, d, n in progress_rows(load_tasks(root)) if ms_status.get(m) != "完成"]
        if prog:
            lines.append(dk.L("任务进度：", "Task progress: ") + " · ".join(f"{m} [{bar(d, n)}] {d}/{n}" for m, d, n in prog[:3]))
        cur = next((k for k, v in ms_status.items() if v in ("进行中", "待验收")), None) \
            or next((k for k, v in ms_status.items() if v == "待做"), None)
        if cur:
            line = dk.L(f"当前：{cur}（{ms_status[cur]}）", f"Current: {cur} ({dk.tv(ms_status[cur])})")
            rv = reviews.get(cur)
            if rv:
                n, path, _t, p = rv[-1]
                line += dk.L(f"；最新验收卡 {path.name}，结论 {p['conclusion'] or '未验收'}",
                             f"; latest review card {path.name}, verdict {dk.tv(p['conclusion']) or 'not yet reviewed'}")
            lines.append(line)
    header, rows = _rows(root / "docs/dev/feedback_log.md", "编号", "状态")
    if header:
        i_sev, i_st = dk.col(header, "严重"), dk.col(header, "状态")
        opened = [r for r in rows if not dk.canon(dk.cell(r, i_st)).startswith(("已关闭", "不改"))]
        high = sum(1 for r in opened if dk.canon(dk.cell(r, i_sev)) == "高")
        if opened:
            lines.append(dk.L(f"未结反馈：{len(opened)} 条（高 {high}）", f"Open feedback: {len(opened)} (high {high})"))
    header, rows = _rows(root / "docs/dev/DEVELOP_DEBT.md", "编号", "还清")
    if header and rows:
        i_pri = dk.col(header, "优先级")
        high = sum(1 for r in rows if dk.canon(dk.cell(r, i_pri)) == "高")
        lines.append(dk.L(f"欠账：{len(rows)} 条（高 {high}）", f"Debt: {len(rows)} item(s) (high {high})"))
    for m in R.messages("ERROR")[:3]:
        lines.append("✗ " + m)
    for m in [m for m in R.messages("WARN") if "连续" in m or "circuit breaker" in m][:2]:
        lines.append("! " + m)
    lines.append(dk.L("开工：读 docs/dev/README.md 的「AI 开工顺序」；收尾运行 python docs/dev/tools/check_docs.py",
                      "Start: read the \"AI start-up order\" in docs/dev/README.md; at the end run python docs/dev/tools/check_docs.py"))
    return "\n".join(lines[:15])


# ---------- 统计 ----------

def print_stats(reviews):
    if not reviews:
        print(dk.L("还没有验收卡，没有可统计的数据。", "No review cards yet, nothing to count."))
        return
    print(dk.L("里程碑      轮数  各轮结论                  各轮平均分", "Milestone   Rounds  Verdicts per round        Avg score per round"))
    first_pass, rounds_to_pass, all_issues = [], [], []
    for ms in sorted(reviews, key=lambda m: int(m[1:])):
        lst = reviews[ms]
        concl = [dk.tv(p["conclusion"]) or dk.L("（未验收）", "(not reviewed)") for _, _, _, p in lst]
        avgs = [f"{statistics.mean(p['scores'].values()):.1f}" if p["scores"] else "-" for _, _, _, p in lst]
        print(f"{ms:<10}  {len(lst):<4}  {' → '.join(concl):<22}  {' → '.join(avgs)}")
        done = [p["conclusion"] for _, _, _, p in lst if p["conclusion"]]
        if done:
            first_pass.append(done[0] == "通过")
            if "通过" in done:
                rounds_to_pass.append(done.index("通过") + 1)
        for _, _, _, p in lst:
            all_issues += p["issues"]
    print()
    if first_pass:
        print(dk.L(f"首轮直接通过率：{sum(first_pass)}/{len(first_pass)}（{100 * sum(first_pass) // len(first_pass)}%）",
                   f"First-round pass rate: {sum(first_pass)}/{len(first_pass)} ({100 * sum(first_pass) // len(first_pass)}%)"))
    if rounds_to_pass:
        print(dk.L(f"平均几轮通过：{statistics.mean(rounds_to_pass):.1f}", f"Average rounds to pass: {statistics.mean(rounds_to_pass):.1f}"))
    if all_issues:
        by_dim, by_sev = {}, {}
        for dim, sev, _, _ in all_issues:
            by_dim[dim] = by_dim.get(dim, 0) + 1
            by_sev[sev] = by_sev.get(sev, 0) + 1
        sep = dk.L("，", ", ")
        print(dk.L("问题数（按维度）：", "Issues by dimension: ") + sep.join(f"{k} {v}" for k, v in sorted(by_dim.items(), key=lambda x: -x[1])))
        print(dk.L("问题数（按严重度）：", "Issues by severity: ") + sep.join(f"{dk.tv(k)} {by_sev.get(k, 0)}" for k in dk.SEVERITIES))
        top = max(by_dim.items(), key=lambda x: x[1])
        if top[1] >= 3:
            print(dk.L(f"提示：「{top[0]}」类问题出现 {top[1]} 次，考虑提炼进 contracts/taste.md 或调参面板，别再逐条改。",
                       f"Hint: \"{top[0]}\" issues came up {top[1]} times; distill them into contracts/taste.md or the tuning panel instead of fixing one by one."))


def delegation_stats(tasks):
    """按路由统计任务完成情况，用数据校准"谁该做什么"。"""
    out = []
    for route in ROUTES:
        mine = [t for t in tasks if t["route"] == route]
        if not mine:
            continue
        done = [t for t in mine if t["result"]]
        first = sum(1 for t in done if t["result"] == "一次通过")
        esc = sum(1 for t in done if t["result"] == "升级")
        rework = [int(re.search(r"\d+", t["result"]).group()) for t in done if t["result"].startswith("返修")]
        out.append({"route": route, "total": len(mine), "done": len(done), "first": first,
                    "esc": esc, "rework_avg": (sum(rework) / len(rework)) if rework else 0.0})
    return out


def print_delegation_stats(tasks):
    rows = delegation_stats(tasks)
    if not rows:
        return
    print(dk.L("\n分派统计（计划任务表）", "\nDelegation stats (plan task tables)"))
    print(dk.L("路由    任务  已完成  一次通过率  升级  平均返修", "Route   Tasks Done    First-pass  Esc.  Avg retries"))
    for r in rows:
        rate = f"{100 * r['first'] // r['done']}%" if r["done"] else "-"
        print(f"{dk.tv(r['route']):<7} {r['total']:<5} {r['done']:<7} {rate:<10}  {r['esc']:<4}  {r['rework_avg']:.1f}")
    for r in rows:
        if r["route"] in DELEGATED and r["done"] >= 10:
            rate = r["first"] / r["done"]
            if rate < 0.6:
                print(dk.L(f"提示：{r['route']} 一次通过率 {int(rate * 100)}%（<60%）：收紧委派条件，或把这类任务留给更高级别。",
                           f"Hint: {r['route']} first-pass rate {int(rate * 100)}% (<60%): tighten the delegation criteria, or keep this kind of task on a stronger model."))
            elif rate >= 0.9 and r["route"] == "sonnet":
                print(dk.L("提示：sonnet 一次通过率 ≥90%：可以试着下放更多任务，或把机械活交给 haiku。",
                           "Hint: sonnet first-pass rate ≥90%: try delegating more, or hand the mechanical work to haiku."))
    if all(r["done"] < 10 for r in rows if r["route"] in DELEGATED):
        print(dk.L("（每个路由完成 ≥10 个任务后，统计才有参考价值。）", "(Stats only become meaningful after ≥10 completed tasks per route.)"))


def suggest_cmd(path):
    p = dk.parse_review(dk.read(path))
    if not p["scores"]:
        sys.exit(dk.L("这张验收卡还没有打分", "This review card has no scores yet"))
    sug, why = dk.suggest_verdict(p["scores"], p["issues"])
    print(dk.L("打分：", "Scores: ") + " ".join(f"{k}{v}" for k, v in p["scores"].items()))
    if p["issues"]:
        print(dk.L(f"问题：{len(p['issues'])} 条（", f"Issues: {len(p['issues'])} (") + dk.L("、", ", ").join(f"{d}-{dk.tv(s)}" for d, s, _, _ in p["issues"]) + dk.L("）", ")"))
    else:
        print(dk.L("问题：无", "Issues: none"))
    print(dk.L(f"建议结论：{dk.tv(sug)}（{'；'.join(why)}）", f"Suggested verdict: {dk.tv(sug)} ({'; '.join(why)})"))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root", nargs="?", default=".")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--stats", action="store_true")
    ap.add_argument("--brief", action="store_true")
    ap.add_argument("--progress", action="store_true")
    ap.add_argument("--suggest", metavar="验收卡.md")
    a = ap.parse_args()

    if a.suggest:
        dk.detect_lang(Path(a.suggest).resolve().parent.parent.parent.parent)
        return suggest_cmd(a.suggest)

    root = Path(a.root).resolve()
    dk.detect_lang(root)
    if not (root / "docs/dev").is_dir():
        sys.exit(dk.L(f"{root} 下没有 docs/dev，先运行 init.py", f"No docs/dev under {root}; run init.py first"))

    if a.brief:
        print(brief(root))
        return
    if a.progress:
        print_progress(root)
        return

    R, _ms, reviews = run_checks(root, a.strict)
    icons = {"ERROR": "✗ ERROR", "WARN": "! WARN ", "INFO": "· INFO "}
    for level in ("ERROR", "WARN", "INFO"):
        for lv, msg in R.items:
            if lv == level:
                print(f"{icons[lv]}  {msg}")
    e, w = R.count("ERROR"), R.count("WARN")
    print(dk.L(f"\n{e} 个错误，{w} 个警告" + ("。全部通过。" if not e and not w else "。"),
               f"\n{e} error(s), {w} warning(s)" + (". All checks passed." if not e and not w else ".")))

    if a.stats:
        print()
        print_stats(reviews)
        print_delegation_stats(load_tasks(root))

    sys.exit(1 if e or (a.strict and w) else 0)


if __name__ == "__main__":
    main()
