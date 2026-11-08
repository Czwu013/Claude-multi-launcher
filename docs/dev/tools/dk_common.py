"""vibecodingflow 公共解析函数（纯标准库）。

其余脚本都依赖它：解析 Markdown 表格、小节、验收卡，并给出"建议结论"。
建议结论的规则只写在 suggest_verdict 里（build_panel 的网页里有一份等价的 JS，改规则时两处一起改）。
"""
import re
import sys
from pathlib import Path

# Windows 控制台默认编码可能打不出中文和 ✗ 之类的符号，统一成 UTF-8
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

PLACEHOLDER = "{{"
# 内部统一用中文 token 做"规范形式"；英文文档在解析时被换算成它们（见 canon），显示时再换回去（见 tv）。
VERDICTS = ("通过", "小改后过", "返工")
SEVERITIES = ("高", "中", "低")
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")

# ---------- 语言 ----------
# 解析端同时接受中英文；语言只影响脚本输出的文字、init 选用哪套模板。
_LANG = "zh"

# 英文 → 中文规范形式（小写比较）。键必须与 assets/templates/en 里的写法一致。
EN2ZH = {
    # 里程碑状态
    "to do": "待做", "in progress": "进行中", "in review": "待验收", "done": "完成",
    # 索引状态
    "current": "最新", "stale": "待更新", "archived": "归档",
    # 反馈状态（前缀匹配用，所以只放前缀）
    "open": "待处理", "fixed": "已修改", "closed": "已关闭", "won't fix": "不改",
    # 结论
    "pass": "通过", "pass with tweaks": "小改后过", "rework": "返工",
    # 严重度
    "high": "高", "medium": "中", "low": "低",
    # 路由
    "main": "主",
    # 任务结果
    "first pass": "一次通过", "escalated": "升级",
    # 维度
    "usable": "能用", "looks": "看着", "feel": "手感", "clarity": "清晰", "engaging": "想继续",
}
ZH2EN = {v: k for k, v in EN2ZH.items()}
ZH2EN_DISPLAY = {
    "待做": "To do", "进行中": "In progress", "待验收": "In review", "完成": "Done",
    "最新": "Current", "待更新": "Stale", "归档": "Archived",
    "待处理": "Open", "已修改": "Fixed", "已关闭": "Closed", "不改": "Won't fix",
    "通过": "Pass", "小改后过": "Pass with tweaks", "返工": "Rework",
    "高": "High", "中": "Medium", "低": "Low", "主": "main",
    "一次通过": "First pass", "升级": "Escalated",
    "能用": "Usable", "看着": "Looks", "手感": "Feel", "清晰": "Clarity", "想继续": "Engaging",
}
DIMS = {"zh": ["能用", "看着", "手感", "清晰", "想继续"], "en": ["Usable", "Looks", "Feel", "Clarity", "Engaging"]}

# 结构关键字别名：解析表头、小节标题、字段名时，中英文任一命中即可。
ALIASES = {
    "里程碑": ("里程碑", "Milestone"), "状态": ("状态", "Status"), "内容": ("内容", "Content"),
    "文档": ("文档", "Document"), "最后更新": ("最后更新", "Last updated"),
    "编号": ("编号", "ID"), "还清": ("还清", "Payoff"), "优先级": ("优先级", "Priority"),
    "来源": ("来源", "Source"), "维度": ("维度", "Dimension"), "严重": ("严重", "Severity"),
    "人的原话": ("人的原话", "Human's words"), "想要": ("想要", "What they want"),
    "处理记录": ("处理记录", "Handling"), "任务": ("任务", "Task"), "路由": ("路由", "Route"),
    "文件范围": ("文件范围", "File scope"), "机器验证": ("机器验证", "Machine check"),
    "结果": ("结果", "Result"),
    # 小节标题
    "人的部分": ("人的部分", "Human part"), "AI 部分": ("AI 部分", "AI part"),
    "怎么跑起来": ("怎么跑起来", "How to run"), "3 分钟体验路线": ("3 分钟体验路线", "3-minute test route"),
    "体验路线": ("体验路线", "test route"), "AI 已验证": ("AI 已验证", "Verified by AI"),
    "请你重点判断": ("请你重点判断", "Key questions"), "已知不足": ("已知不足", "Known shortcomings"),
    "本轮复验": ("本轮复验", "Re-check this round"), "打分": ("打分", "Scores"),
    "问题": ("问题", "Issues"), "好的地方": ("好的地方", "What's good"), "结论": ("结论", "Verdict"),
    "已还清": ("已还清", "Paid off"),
    # 验收卡字段
    "AI 建议结论": ("AI 建议结论", "AI suggested verdict"), "验收人": ("验收人", "Reviewer"),
    "日期": ("日期", "Date"), "覆盖原因": ("覆盖原因", "Override reason"),
}


def set_lang(lang):
    global _LANG
    _LANG = "en" if str(lang).lower().startswith("en") else "zh"
    return _LANG


def get_lang():
    return _LANG


def detect_lang(root):
    """项目语言：环境变量 DK_LANG > docs/dev/.lang > 默认 zh（兼容旧项目）。"""
    import os
    env = os.environ.get("DK_LANG")
    if env:
        return set_lang(env)
    try:
        f = Path(root) / "docs" / "dev" / ".lang"
        if f.exists():
            return set_lang(f.read_text(encoding="utf-8").strip())
    except Exception:
        pass
    return set_lang("zh")


def L(zh, en):
    """按当前语言选文字。"""
    return en if _LANG == "en" else zh


def canon(value):
    """把英文 token 换算成中文规范形式；中文或未知的原样返回。"""
    v = (value or "").strip()
    low = v.lower().replace("’", "'")
    if low in EN2ZH:
        return EN2ZH[low]
    for en in ("fixed", "closed", "open", "won't fix"):  # 反馈状态常带后缀，如 "Fixed, awaiting re-check"
        if low.startswith(en):
            return v if v[:1] in "已待不" else EN2ZH[en] + v[len(en):]
    m = re.fullmatch(r"retry\s*(\d+)\s*x?", low)
    if m:
        return f"返修{m.group(1)}次"
    return v


def tv(token):
    """显示用：规范形式 → 当前语言。"""
    if _LANG == "en":
        t = ZH2EN_DISPLAY.get(token)
        if t:
            return t
        m = re.fullmatch(r"返修(\d+)次", token or "")
        if m:
            return f"Retry {m.group(1)}x"
    return token


def alias(keyword):
    return ALIASES.get(keyword, (keyword,))


def _hit(text, keyword):
    low = text.lower()
    return any(a.lower() in low for a in alias(keyword))


def read(path):
    return Path(path).read_text(encoding="utf-8")


# ---------- Markdown 表格 ----------

def _cells(line):
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [c.strip() for c in line.split("|")]


def _is_sep(line):
    return bool(re.match(r"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$", line))


def tables(text):
    """返回 [(表头单元格列表, 行列表(每行是单元格列表))]。忽略 HTML 注释里的内容。"""
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    lines = text.splitlines()
    out, i = [], 0
    while i < len(lines) - 1:
        if "|" in lines[i] and _is_sep(lines[i + 1]):
            header = _cells(lines[i])
            rows, j = [], i + 2
            while j < len(lines) and "|" in lines[j] and lines[j].strip():
                rows.append(_cells(lines[j]))
                j += 1
            out.append((header, rows))
            i = j
        else:
            i += 1
    return out


def find_table(text, *must_have):
    """找到表头同时包含所有关键词的第一张表，返回 (header, rows) 或 None。"""
    for header, rows in tables(text):
        joined = " ".join(header)
        if all(_hit(joined, k) for k in must_have):
            return header, rows
    return None


def col(header, keyword):
    for i, h in enumerate(header):
        if _hit(h, keyword):
            return i
    return None


def cell(row, idx):
    return row[idx].strip() if idx is not None and idx < len(row) else ""


# ---------- 小节 ----------

def section(text, title_prefix):
    """取以 title_prefix 开头的标题下的内容，直到同级或更高级标题。找不到返回空串。"""
    lines = text.splitlines()
    start, level = None, None
    for i, ln in enumerate(lines):
        m = re.match(r"^(#{1,6})\s*(.*)$", ln)
        if m and any(m.group(2).strip().lower().startswith(a.lower()) for a in alias(title_prefix)):
            start, level = i + 1, len(m.group(1))
            break
    if start is None:
        return ""
    body = []
    for ln in lines[start:]:
        m = re.match(r"^(#{1,6})\s", ln)
        if m and len(m.group(1)) <= level:
            break
        body.append(ln)
    return "\n".join(body)


def strip_comments(s):
    return re.sub(r"<!--.*?-->", "", s, flags=re.S)


def bullets(s):
    """取列表项（- / * / 1.），去掉编号，忽略注释和含占位符的项。"""
    s = strip_comments(s)
    items = []
    for ln in s.splitlines():
        m = re.match(r"^\s*(?:[-*]|\d+[.、)])\s+(.*\S)\s*$", ln)
        if m and PLACEHOLDER not in m.group(1):
            items.append(m.group(1))
    return items


# ---------- 验收卡 ----------

ISSUE_RE = re.compile(
    r"^\s*(?:\d+[.、)]|[-*])\s*\[(?P<dim>[^\]]+)\]\s*\[(?P<sev>高|中|低|High|Medium|Low)\]\s*(?P<rest>.*\S)\s*$"
)


def _field(s, name):
    names = "|".join(re.escape(a) for a in alias(name))
    m = re.search(r"^\s*(?:" + names + r")[^:：\n]*[:：][ \t]*(.*)$", s, flags=re.M | re.I)
    return m.group(1).strip() if m else ""


def _has_field(s, name):
    names = "|".join(re.escape(a) for a in alias(name))
    return bool(re.search(r"^\s*(?:" + names + r")[:：]", s, flags=re.M | re.I))


def parse_review(text):
    """解析验收卡里"人的部分"。返回 dict：scores / reasons / issues / conclusion / suggested_in_card /
    signer / date / override。"""
    human = section(text, "人的部分")
    score_sec = strip_comments(section(human, "打分"))
    scores, reasons = {}, {}
    for ln in score_sec.splitlines():
        if "|" not in ln or _is_sep(ln):
            continue
        c = _cells(ln)
        if len(c) >= 2 and re.fullmatch(r"[1-5]", c[1]):
            scores[c[0]] = int(c[1])
            reasons[c[0]] = c[2] if len(c) > 2 else ""

    issues = []
    for ln in strip_comments(section(human, "问题")).splitlines():
        m = ISSUE_RE.match(ln)
        if m:
            parts = re.split(r"\s*[|｜]\s*", m.group("rest"), maxsplit=1)
            issues.append(
                (m.group("dim").strip(), canon(m.group("sev")), parts[0].strip(), parts[1].strip() if len(parts) > 1 else "")
            )

    concl = strip_comments(section(human, "结论"))
    return {
        "scores": scores,
        "reasons": reasons,
        "issues": issues,
        "conclusion": canon(_field(concl, "结论")) if _has_field(concl, "结论") else "",
        "suggested_in_card": canon(_field(concl, "AI 建议结论")),
        "signer": _field(concl, "验收人"),
        "date": _field(concl, "日期"),
        "override": _field(concl, "覆盖原因"),
    }


def suggest_verdict(scores, issues):
    """建议结论规则：
    返工     ：任一维度 ≤2 分，或有"高"严重度问题
    小改后过 ：（不满足返工）任一维度 =3 分，或有"中"严重度问题
    通过     ：其余（全部 ≥4 分，且只有低严重度问题或没有问题）
    缺打分返回 None。"""
    if not scores:
        return None, []
    lo = min(scores.values())
    why = []
    if lo <= 2:
        why.append(L(f"有维度 ≤2 分（最低 {lo}）", f"a dimension scored ≤2 (lowest {lo})"))
    if any(sev == "高" for _, sev, _, _ in issues):
        why.append(L("有高严重度问题", "a high-severity issue"))
    if why:
        return "返工", why
    if lo == 3:
        why.append(L("有维度 =3 分", "a dimension scored 3"))
    if any(sev == "中" for _, sev, _, _ in issues):
        why.append(L("有中严重度问题", "a medium-severity issue"))
    if why:
        return "小改后过", why
    return "通过", [L("全部 ≥4 分，无中高严重度问题", "all scores ≥4, no medium/high issues")]


def review_files(reviews_dir):
    """返回 {里程碑: [(轮次, 路径), ...]}，按轮次排序。文件名形如 M1_r2.md。"""
    out = {}
    for p in Path(reviews_dir).glob("M*_r*.md"):
        m = re.fullmatch(r"(M\d+)_r(\d+)\.md", p.name)
        if m:
            out.setdefault(m.group(1), []).append((int(m.group(2)), p))
    for v in out.values():
        v.sort()
    return out
