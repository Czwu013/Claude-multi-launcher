#!/usr/bin/env python3
"""为某个里程碑生成下一轮验收卡。

用法：
    python new_review.py M1 [--root .]

规则：
  - 轮次自动 +1（已有 M1_r1.md 就生成 M1_r2.md）
  - 第 2 轮起，自动把 feedback_log.md 里该里程碑状态为"待复验"的条目写进"本轮复验"，
    人只需要点 ✓ / ✗，不必重新通玩一遍
"""
import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dk_common as dk  # noqa: E402


def find_template(root):
    candidates = [
        root / "docs/dev/reviews/_TEMPLATE_review.md",
        Path(__file__).resolve().parent.parent / f"assets/templates/{dk.get_lang()}/core/docs/dev/reviews/_TEMPLATE_review.md",
    ]
    for c in candidates:
        if c.exists():
            return c
    sys.exit(dk.L("找不到验收卡模板 _TEMPLATE_review.md", "Review template _TEMPLATE_review.md not found"))


def pending_recheck(root, ms):
    log = root / "docs/dev/feedback_log.md"
    if not log.exists():
        return []
    t = dk.find_table(dk.read(log), "编号", "状态")
    if not t:
        return []
    header, rows = t
    i_id, i_src, i_dim = dk.col(header, "编号"), dk.col(header, "来源"), dk.col(header, "维度")
    i_text, i_want = dk.col(header, "人的原话"), dk.col(header, "想要")
    i_status, i_note = dk.col(header, "状态"), dk.col(header, "处理记录")
    out = []
    for r in rows:
        if dk.PLACEHOLDER in " ".join(r):
            continue
        st = dk.cell(r, i_status).lower()
        if not dk.cell(r, i_src).startswith(ms) or not ("待复验" in st or "awaiting re-check" in st):
            continue
        bits = [dk.cell(r, i_dim), dk.cell(r, i_text)]
        line = f"{dk.cell(r, i_id)} {dk.L('：', ': ').join(b for b in bits if b)}"
        if dk.cell(r, i_want):
            line += dk.L(f"（想要：{dk.cell(r, i_want)}）", f" (wants: {dk.cell(r, i_want)})")
        if dk.cell(r, i_note):
            line += f" → {dk.cell(r, i_note)}"
        out.append(line)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("milestone", help="里程碑编号，如 M1")
    ap.add_argument("--root", default=".", help="项目根目录，默认当前目录")
    a = ap.parse_args()

    ms = a.milestone.strip().upper()
    if not re.fullmatch(r"M\d+", ms):
        sys.exit("里程碑编号形如 M0、M1、M12 / Milestone id looks like M0, M1, M12")
    root = Path(a.root).resolve()
    dk.detect_lang(root)
    rdir = root / "docs/dev/reviews"
    if not rdir.exists():
        sys.exit(dk.L(f"找不到 {rdir}，请先运行 init.py", f"{rdir} not found; run init.py first"))

    rounds = [n for n, _ in dk.review_files(rdir).get(ms, [])]
    n = (max(rounds) + 1) if rounds else 1
    out = rdir / f"{ms}_r{n}.md"
    if out.exists():
        sys.exit(dk.L(f"已存在：{out}", f"Already exists: {out}"))

    text = dk.read(find_template(root)).replace("{{Mx}}", ms).replace("{{N}}", str(n))

    if n > 1:
        items = pending_recheck(root, ms)
        if items:
            block = "\n".join(f"- {it}" for it in items)
            text = text.replace("- 无（第 1 轮）", block).replace("- None (round 1)", block)
        else:
            none = dk.L("- 无（没有待复验的反馈）", "- None (no feedback awaiting re-check)")
            text = text.replace("- 无（第 1 轮）", none).replace("- None (round 1)", none)

    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(dk.L(f"已生成：{out.relative_to(root)}", f"Created: {out.relative_to(root)}"))
    print(dk.L("下一步：填好「AI 部分」（先自测，机器能查的别让人查），然后：",
               "Next: fill in the \"AI part\" (self-test first; don't make the human check what a machine can), then:"))
    print(f"  python docs/dev/tools/build_panel.py docs/dev/reviews/{out.name}")


if __name__ == "__main__":
    main()
